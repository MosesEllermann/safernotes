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

    def as_dict(self) -> dict:
        return asdict(self)


PLAN_POLICIES = {
    "free": PlanPolicy(
        key="free",
        storage_bytes=100 * 1024 * 1024,
        max_notes=500,
        max_attachment_bytes=10 * 1024 * 1024,
        max_collaborators_per_note=3,
        version_history_days=0,
        team_workspaces=False,
        sso_ready=False,
        audit_controls=False,
        data_residency=False,
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
    ),
}


def policy_for_plan(plan: str) -> PlanPolicy:
    return PLAN_POLICIES.get(plan, PLAN_POLICIES["free"])

