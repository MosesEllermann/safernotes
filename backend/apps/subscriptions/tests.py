from __future__ import annotations

from apps.attachments.models import TenantStorageUsage
from apps.subscriptions.plans import policy_for_plan
from apps.subscriptions.usage import usage_report_for_tenant


def test_plan_policy_defaults_to_free_for_unknown_plan():
    assert policy_for_plan("unknown").key == "free"


def test_free_plan_includes_500_mb_storage():
    assert policy_for_plan("free").storage_bytes == 500 * 1024 * 1024


def test_paid_plans_have_clear_storage_steps():
    assert policy_for_plan("essential").storage_bytes == 5 * 1024 * 1024 * 1024
    assert policy_for_plan("pro").storage_bytes == 25 * 1024 * 1024 * 1024


def test_enterprise_policy_enables_enterprise_controls():
    policy = policy_for_plan("enterprise")

    assert policy.sso_ready
    assert policy.audit_controls
    assert policy.data_residency


def test_usage_report_exposes_counts_not_content(db, tenant, note):
    TenantStorageUsage.objects.create(
        tenant=tenant,
        ciphertext_bytes_used=1024,
        attachments_count=1,
    )
    report = usage_report_for_tenant(tenant)

    assert report["tenant"] == str(tenant.id)
    assert report["usage"]["notes_count"] == 1
    assert report["usage"]["notes_bytes_used"] == note.storage_bytes
    assert report["usage"]["attachments_bytes_used"] == 1024
    assert report["usage"]["storage_bytes_used"] == note.storage_bytes + 1024
    assert report["usage"]["ciphertext_bytes_used"] == note.storage_bytes + 1024
    assert "encrypted_payload" not in str(report)
    assert "server-hash" not in str(report)


def test_deleted_notes_do_not_consume_workspace_quota(db, tenant, note):
    note.state = "deleted"
    note.save(update_fields=["state", "updated_at"])

    report = usage_report_for_tenant(tenant)

    assert report["usage"]["notes_count"] == 0
    assert report["usage"]["notes_bytes_used"] == 0
    assert report["usage"]["storage_bytes_used"] == 0
