from __future__ import annotations

from apps.subscriptions.plans import policy_for_plan
from apps.subscriptions.usage import usage_report_for_tenant


def test_plan_policy_defaults_to_free_for_unknown_plan():
    assert policy_for_plan("unknown").key == "free"


def test_enterprise_policy_enables_enterprise_controls():
    policy = policy_for_plan("enterprise")

    assert policy.sso_ready
    assert policy.audit_controls
    assert policy.data_residency


def test_usage_report_exposes_counts_not_content(db, tenant, note):
    report = usage_report_for_tenant(tenant)

    assert report["tenant"] == str(tenant.id)
    assert report["usage"]["notes_count"] == 1
    assert "encrypted_payload" not in str(report)
    assert "server-hash" not in str(report)
