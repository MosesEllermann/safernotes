from __future__ import annotations

from django.urls import reverse
from django.utils import timezone

from apps.attachments.models import Attachment, TenantStorageUsage
from apps.audit.models import AuditEvent
from apps.authentication.models import EmailVerificationCode, KeyMaterial, RecoveryCode, Session
from apps.devices.models import Device
from apps.notes.models import Note, NoteConflict, NoteKeyGrant
from apps.subscriptions.models import Subscription
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
    tenant.plan = "essential"
    tenant.save(update_fields=["plan", "updated_at"])
    owner_user.default_tenant = tenant
    owner_user.email_verified_at = timezone.now()
    owner_user.save(update_fields=["default_tenant", "email_verified_at", "updated_at"])
    subscription = Subscription.objects.create(
        tenant=tenant,
        plan="essential",
        status="active",
        billing_provider="manual",
        provider_customer_id="provider-customer-secret",
        provider_subscription_id="provider-subscription-secret",
    )
    TenantStorageUsage.objects.create(
        tenant=tenant,
        ciphertext_bytes_used=1024,
        attachments_count=2,
    )
    return subscription


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
    assert "essential" in page
    assert "active" in page
    assert "manual" in page
    assert "1.0 KB" in page
    assert ">1<" in page


def test_subscription_plan_change_is_validated_synced_and_audited(
    client,
    django_user_model,
    owner_user,
    tenant,
):
    subscription = configure_account(owner_user, tenant)
    operator = create_owner_admin(django_user_model)
    client.force_login(operator)

    response = client.post(
        reverse("owner_admin:subscriptions_subscription_change", args=(subscription.pk,)),
        {"plan": "pro", "status": "active", "_save": "Save"},
    )

    assert response.status_code == 302
    subscription.refresh_from_db()
    tenant.refresh_from_db()
    assert subscription.plan == "pro"
    assert subscription.status == "active"
    assert tenant.plan == "pro"

    event = AuditEvent.objects.get(event_type="admin.subscription.changed")
    assert event.actor_user == operator
    assert event.tenant == tenant
    assert event.target_id == subscription.id
    assert event.metadata == {
        "changes": {"plan": {"from": "essential", "to": "pro"}},
        "source": "django-admin",
    }
    assert event.signature


def test_subscription_admin_rejects_invalid_plan_status_pair(
    client,
    django_user_model,
    owner_user,
    tenant,
):
    subscription = configure_account(owner_user, tenant)
    client.force_login(create_owner_admin(django_user_model))

    response = client.post(
        reverse("owner_admin:subscriptions_subscription_change", args=(subscription.pk,)),
        {"plan": "pro", "status": "canceled", "_save": "Save"},
    )

    assert response.status_code == 200
    assert b"Canceled or expired subscriptions must use the Free plan." in response.content
    subscription.refresh_from_db()
    tenant.refresh_from_db()
    assert subscription.plan == "essential"
    assert subscription.status == "active"
    assert tenant.plan == "essential"
    assert not AuditEvent.objects.filter(event_type="admin.subscription.changed").exists()


def test_admin_never_renders_sensitive_auth_or_crypto_material(
    client,
    django_user_model,
    owner_user,
    tenant,
):
    subscription = configure_account(owner_user, tenant)
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
        client.get(
            reverse(
                "owner_admin:subscriptions_subscription_change",
                args=(subscription.pk,),
            )
        ),
    )
    rendered = "\n".join(response.content.decode() for response in responses)

    assert all(response.status_code == 200 for response in responses)
    for forbidden_value in (
        password_hash,
        "provider-customer-secret",
        "provider-subscription-secret",
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
        "provider_customer_id",
        "provider_subscription_id",
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
