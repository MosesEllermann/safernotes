from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class PlanPolicy:
    key: str
    storage_bytes: int
    max_notes: int | None
    max_attachment_bytes: int
    max_collaborators_per_note: int
    version_history_days: int
    team_workspaces: bool
    sso_ready: bool
    audit_controls: bool
    data_residency: bool
    monthly_price_eur_cents: int | None
    yearly_price_eur_cents: int | None
    billing_interval_note: str

    def as_dict(self) -> dict:
        return asdict(self)


PLAN_POLICIES = {
    "free": PlanPolicy(
        key="free",
        storage_bytes=500 * 1024 * 1024,
        max_notes=500,
        max_attachment_bytes=10 * 1024 * 1024,
        max_collaborators_per_note=3,
        version_history_days=0,
        team_workspaces=False,
        sso_ready=False,
        audit_controls=False,
        data_residency=False,
        monthly_price_eur_cents=0,
        yearly_price_eur_cents=0,
        billing_interval_note="free",
    ),
    "essential": PlanPolicy(
        key="essential",
        storage_bytes=5 * 1024 * 1024 * 1024,
        max_notes=5000,
        max_attachment_bytes=100 * 1024 * 1024,
        max_collaborators_per_note=5,
        version_history_days=90,
        team_workspaces=False,
        sso_ready=False,
        audit_controls=False,
        data_residency=False,
        monthly_price_eur_cents=150,
        yearly_price_eur_cents=1800,
        billing_interval_note="yearly-first",
    ),
    "pro": PlanPolicy(
        key="pro",
        storage_bytes=25 * 1024 * 1024 * 1024,
        max_notes=None,
        max_attachment_bytes=250 * 1024 * 1024,
        max_collaborators_per_note=25,
        version_history_days=365,
        team_workspaces=False,
        sso_ready=False,
        audit_controls=False,
        data_residency=False,
        monthly_price_eur_cents=500,
        yearly_price_eur_cents=6000,
        billing_interval_note="yearly-first",
    ),
    "team": PlanPolicy(
        key="team",
        storage_bytes=250 * 1024 * 1024 * 1024,
        max_notes=None,
        max_attachment_bytes=1024 * 1024 * 1024,
        max_collaborators_per_note=100,
        version_history_days=365,
        team_workspaces=True,
        sso_ready=False,
        audit_controls=True,
        data_residency=False,
        monthly_price_eur_cents=1500,
        yearly_price_eur_cents=15000,
        billing_interval_note="per workspace, monthly or yearly",
    ),
    "enterprise": PlanPolicy(
        key="enterprise",
        storage_bytes=1024 * 1024 * 1024 * 1024,
        max_notes=None,
        max_attachment_bytes=5 * 1024 * 1024 * 1024,
        max_collaborators_per_note=1000,
        version_history_days=3650,
        team_workspaces=True,
        sso_ready=True,
        audit_controls=True,
        data_residency=True,
        monthly_price_eur_cents=None,
        yearly_price_eur_cents=None,
        billing_interval_note="custom contract",
    ),
}


def policy_for_plan(plan: str) -> PlanPolicy:
    return PLAN_POLICIES.get(plan, PLAN_POLICIES["free"])
