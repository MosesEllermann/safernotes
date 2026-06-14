from __future__ import annotations

from apps.notes.sync import SyncBatchSerializer
from apps.notes.sync_models import SyncOperationReceipt


def test_sync_receipt_replay_shape(db, owner_user):
    receipt = SyncOperationReceipt.objects.create(
        user=owner_user,
        idempotency_key="client-op-1",
        operation_type="change_state",
        result={"status": "ok", "note_id": "note-id", "version": 2},
    )

    assert receipt.result["status"] == "ok"
    assert receipt.idempotency_key == "client-op-1"


def test_sync_batch_accepts_valid_idempotent_operation():
    serializer = SyncBatchSerializer(
        data={
            "operations": [
                {
                    "idempotency_key": "client-op-1",
                    "type": "change_state",
                    "note_id": "00000000-0000-0000-0000-000000000002",
                    "payload": {"state": "archived"},
                }
            ]
        }
    )

    assert serializer.is_valid()

