from __future__ import annotations

from apps.audit.events import record_audit_event


def test_audit_event_redacts_sensitive_metadata(db, owner_user):
    event = record_audit_event(
        event_type="test.event",
        actor_user=owner_user,
        target_type="user",
        target_id=owner_user.id,
        metadata={
            "access_token": "raw-token",
            "nested": {"ciphertext": "secret", "safe": "ok"},
        },
    )

    assert event.metadata["access_token"] == "[REDACTED]"
    assert event.metadata["nested"]["ciphertext"] == "[REDACTED]"
    assert event.metadata["nested"]["safe"] == "ok"
    assert event.signature

