from __future__ import annotations

from rest_framework.test import APIRequestFactory, force_authenticate

from apps.notes.models import Note
from apps.notes.sync import SyncBatchSerializer, SyncBatchView
from apps.notes.sync_models import SyncOperationReceipt
from apps.notes.views import NoteViewSet


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


def test_sync_batch_created_note_is_visible_in_note_list(db, owner_user, tenant, encrypted_payload):
    request = APIRequestFactory().post(
        "/api/v1/notes/sync/batch",
        {
            "operations": [
                {
                    "idempotency_key": "android-note-1",
                    "type": "upsert_note",
                    "payload": {
                        "tenant": str(tenant.id),
                        "encrypted_payload": encrypted_payload,
                        "payload_hash": "client-hash",
                        "client_updated_at": "2026-08-19T00:00:00Z",
                    },
                }
            ]
        },
        format="json",
    )
    force_authenticate(request, user=owner_user)

    response = SyncBatchView.as_view()(request)

    assert response.status_code == 200
    assert response.data["results"][0]["status"] == "ok"
    assert Note.objects.filter(owner_user=owner_user).count() == 1

    list_request = APIRequestFactory().get("/api/v1/notes/")
    force_authenticate(list_request, user=owner_user)
    list_response = NoteViewSet.as_view({"get": "list"})(list_request)

    assert list_response.status_code == 200
    assert len(list_response.data["results"]) == 1
    assert list_response.data["results"][0]["id"] == response.data["results"][0]["note_id"]
