from __future__ import annotations

from django.urls import reverse
from django.utils import timezone

from apps.attachments.models import Attachment, TenantStorageUsage
from apps.audit.models import AuditEvent
from apps.authentication.models import EmailVerificationCode, KeyMaterial, RecoveryCode, Session
from apps.devices.models import Device
from apps.notes.models import Note, NoteConflict, NoteKeyGrant, ShareInvitation
from apps.users.admin_site import owner_admin_site
from apps.users.models import Profile


def create_staff_user(django_user_model):
    return django_user_model.objects.create_user(
        email="operator@example.com",
        password="operator-password",
        is_staff=True,
    )


def create_owner_admin(django_user_model):
    return django_user_model.objects.create_superuser(
        email="owner-admin@example.com",
        password="owner-admin-password",
    )


def configure_account(owner_user, tenant):
    owner_user.default_tenant = tenant
    owner_user.email_verified_at = timezone.now()
    owner_user.save(update_fields=["default_tenant", "email_verified_at", "updated_at"])
    TenantStorageUsage.objects.create(
        tenant=tenant,
        ciphertext_bytes_used=1024,
        attachments_count=2,
    )


def test_owner_admin_requires_superuser_access(client, django_user_model):
    index_url = reverse("owner_admin:index")
    normal_user = django_user_model.objects.create_user(
        email="normal@example.com",
        password="normal-password",
    )

    anonymous_response = client.get(index_url)
    assert anonymous_response.status_code == 302
    assert reverse("owner_admin:login") in anonymous_response.url

    client.force_login(normal_user)
    normal_response = client.get(index_url)
    assert normal_response.status_code == 302
    assert reverse("owner_admin:login") in normal_response.url

    client.force_login(create_staff_user(django_user_model))
    staff_response = client.get(index_url)
    assert staff_response.status_code == 302
    assert reverse("owner_admin:login") in staff_response.url

    client.force_login(create_owner_admin(django_user_model))
    owner_response = client.get(index_url)
    assert owner_response.status_code == 200
    assert b"Owner dashboard" in owner_response.content
    assert b"safernotes-admin.css" in owner_response.content
    assert b"safernotes-brand__label" in owner_response.content


def test_owner_dashboard_shows_operational_health_without_encrypted_content(
    client,
    django_user_model,
    owner_user,
    recipient_user,
    tenant,
    note,
    encrypted_payload,
):
    configure_account(owner_user, tenant)
    ShareInvitation.objects.create(
        note=note,
        sender_user=owner_user,
        recipient_user=recipient_user,
        role="editor",
        encrypted_note_key={**encrypted_payload, "ciphertext": "share-key-secret"},
        invitation_signature=b"invite-signature-secret",
    )
    client.force_login(create_owner_admin(django_user_model))

    response = client.get(reverse("owner_admin:index"))
    page = response.content.decode()

    assert response.status_code == 200
    assert "Operations overview" in page
    assert "Pending invites" in page
    assert "Encrypted notes" in page
    assert "Inspect sharing invites" in page
    assert owner_user.email in page
    assert "share-key-secret" not in page
    assert "invite-signature-secret" not in page


def test_share_invitation_admin_is_read_only_and_hides_crypto_material(
    client,
    django_user_model,
    owner_user,
    recipient_user,
    note,
    encrypted_payload,
):
    invitation = ShareInvitation.objects.create(
        note=note,
        sender_user=owner_user,
        recipient_user=recipient_user,
        role="editor",
        encrypted_note_key={**encrypted_payload, "ciphertext": "share-key-secret"},
        invitation_signature=b"invite-signature-secret",
    )
    client.force_login(create_owner_admin(django_user_model))

    responses = (
        client.get(reverse("owner_admin:notes_shareinvitation_changelist")),
        client.get(reverse("owner_admin:notes_shareinvitation_change", args=(invitation.pk,))),
    )
    rendered = "\n".join(response.content.decode() for response in responses)

    assert all(response.status_code == 200 for response in responses)
    assert owner_user.email in rendered
    assert recipient_user.email in rendered
    assert "share-key-secret" not in rendered
    assert "invite-signature-secret" not in rendered
    assert "encrypted_note_key" not in rendered
    assert "invitation_signature" not in rendered


def test_user_admin_shows_only_operational_metadata(
    client,
    django_user_model,
    owner_user,
    tenant,
    note,
):
    configure_account(owner_user, tenant)
    client.force_login(create_owner_admin(django_user_model))

    response = client.get(reverse("owner_admin:users_user_changelist"))
    page = response.content.decode()

    assert response.status_code == 200
    assert owner_user.email in page
    assert "active" in page
    assert "1.0 KB" in page
    assert ">1<" in page


def test_account_deactivation_requires_confirmation_and_is_reversible(
    client,
    django_user_model,
    owner_user,
):
    client.force_login(create_owner_admin(django_user_model))
    changelist_url = reverse("owner_admin:users_user_changelist")
    action_payload = {
        "action": "deactivate_accounts",
        "_selected_action": str(owner_user.pk),
        "index": "0",
    }

    confirmation = client.post(changelist_url, action_payload)
    owner_user.refresh_from_db()
    assert confirmation.status_code == 200
    assert b"Confirm account deactivation" in confirmation.content
    assert owner_user.is_active

    deactivated = client.post(changelist_url, {**action_payload, "apply": "yes"})
    owner_user.refresh_from_db()
    assert deactivated.status_code == 302
    assert not owner_user.is_active
    assert owner_user.status == "suspended"
    assert AuditEvent.objects.filter(event_type="admin.account.deactivated").exists()

    activated = client.post(
        changelist_url,
        {
            "action": "activate_accounts",
            "_selected_action": str(owner_user.pk),
            "index": "0",
        },
    )
    owner_user.refresh_from_db()
    assert activated.status_code == 302
    assert owner_user.is_active
    assert owner_user.status == "active"
    assert AuditEvent.objects.filter(event_type="admin.account.activated").exists()


def test_account_export_contains_metadata_but_no_auth_material(
    client,
    django_user_model,
    owner_user,
):
    client.force_login(create_owner_admin(django_user_model))

    response = client.post(
        reverse("owner_admin:users_user_changelist"),
        {
            "action": "export_accounts_csv",
            "_selected_action": str(owner_user.pk),
            "index": "0",
        },
    )

    csv_export = response.content.decode()
    assert response.status_code == 200
    assert response["Content-Type"] == "text/csv"
    assert owner_user.email in csv_export
    assert owner_user.password not in csv_export


def test_admin_never_renders_sensitive_auth_or_crypto_material(
    client,
    django_user_model,
    owner_user,
    tenant,
):
    configure_account(owner_user, tenant)
    KeyMaterial.objects.create(
        user=owner_user,
        kdf_params={"memory": 65536},
        password_salt=b"password-salt-secret",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key={"ciphertext": "master-key-secret"},
        encrypted_private_encryption_key={"ciphertext": "private-encryption-secret"},
        encrypted_private_signing_key={"ciphertext": "private-signing-secret"},
        recovery_wrapper={"ciphertext": "recovery-wrapper-secret"},
    )
    password_hash = owner_user.password
    client.force_login(create_owner_admin(django_user_model))

    responses = (
        client.get(reverse("owner_admin:users_user_change", args=(owner_user.pk,))),
    )
    rendered = "\n".join(response.content.decode() for response in responses)

    assert all(response.status_code == 200 for response in responses)
    for forbidden_value in (
        password_hash,
        "password-salt-secret",
        "master-key-secret",
        "private-encryption-secret",
        "private-signing-secret",
        "recovery-wrapper-secret",
    ):
        assert forbidden_value not in rendered

    for forbidden_field in (
        "encrypted_master_key",
        "encrypted_private_encryption_key",
        "encrypted_private_signing_key",
        "recovery_wrapper",
    ):
        assert forbidden_field not in rendered


def test_sensitive_models_are_not_registered_in_admin():
    for sensitive_model in (
        KeyMaterial,
        Session,
        RecoveryCode,
        EmailVerificationCode,
        Device,
        Profile,
        Note,
        NoteKeyGrant,
        NoteConflict,
        Attachment,
        AuditEvent,
    ):
        assert sensitive_model not in owner_admin_site._registry
