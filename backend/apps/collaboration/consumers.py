from __future__ import annotations

import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.utils import timezone

from apps.collaboration.models import CollaborationPresence, SyncEvent, SyncEventAck
from apps.notes.models import Note
from apps.notes.permissions import can_read_note, can_write_note


def valid_encrypted_event_payload(event):
    required = {"note_version", "encrypted_delta", "event_signature"}
    envelope_keys = {"version", "algorithm", "nonce", "ciphertext"}
    encrypted_delta = event.get("encrypted_delta")
    return (
        event.get("type") == "encrypted.event"
        and required.issubset(event)
        and isinstance(encrypted_delta, dict)
        and envelope_keys.issubset(encrypted_delta)
    )


@database_sync_to_async
def note_access(user, note_id):
    note = Note.objects.filter(id=note_id).first()
    if note is None:
        return None, False, False
    return note, can_read_note(user, note), can_write_note(user, note)


@database_sync_to_async
def replay_events(note, since_id=None):
    queryset = SyncEvent.objects.filter(note=note).order_by("created_at")
    if since_id:
        queryset = queryset.filter(id__gt=since_id)
    return [
        {
            "id": str(event.id),
            "note": str(event.note_id),
            "tenant": str(event.tenant_id),
            "actor_user": str(event.actor_user_id),
            "note_version": event.note_version,
            "encrypted_delta": event.encrypted_delta,
            "event_signature": bytes(event.event_signature).decode("utf-8"),
            "created_at": event.created_at.isoformat(),
        }
        for event in queryset[:100]
    ]


@database_sync_to_async
def persist_event(user, note, payload):
    event = SyncEvent.objects.create(
        tenant=note.tenant,
        note=note,
        actor_user=user,
        note_version=payload["note_version"],
        encrypted_delta=payload["encrypted_delta"],
        event_signature=payload["event_signature"].encode("utf-8"),
    )
    return {
        "id": str(event.id),
        "note": str(event.note_id),
        "tenant": str(event.tenant_id),
        "actor_user": str(event.actor_user_id),
        "note_version": event.note_version,
        "encrypted_delta": event.encrypted_delta,
        "event_signature": payload["event_signature"],
        "created_at": event.created_at.isoformat(),
    }


@database_sync_to_async
def acknowledge_event(user, session, event_id):
    event = SyncEvent.objects.filter(id=event_id).first()
    if event is None:
        return False
    device = getattr(session, "device", None)
    SyncEventAck.objects.update_or_create(
        event=event,
        user=user,
        device=device,
        defaults={"received_at": timezone.now()},
    )
    return True


@database_sync_to_async
def mark_presence(user, note, session, status):
    device = getattr(session, "device", None)
    presence, _ = CollaborationPresence.objects.update_or_create(
        note=note,
        user=user,
        device=device,
        defaults={"status": status},
    )
    return str(presence.id)


class EncryptedNoteConsumer(AsyncWebsocketConsumer):
    """Relays encrypted collaboration payloads without inspecting note contents."""

    async def connect(self):
        self.note_id = self.scope["url_route"]["kwargs"]["note_id"]
        self.user = self.scope.get("user")
        if not self.user or not self.user.is_authenticated:
            await self.close(code=4401)
            return
        self.note, self.can_read, self.can_write = await note_access(self.user, self.note_id)
        if not self.can_read:
            await self.close(code=4403)
            return
        self.group_name = f"note:{self.note_id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await mark_presence(self.user, self.note, self.scope.get("auth"), "online")
        await self.send(
            text_data=json.dumps(
                {
                    "type": "presence",
                    "status": "online",
                    "user_id": str(self.user.id),
                }
            )
        )
        replay_since = self.scope.get("query_string", b"").decode("utf-8")
        replay_id = None
        for part in replay_since.split("&"):
            if part.startswith("since_event_id="):
                replay_id = part.split("=", 1)[1]
        events = await replay_events(self.note, replay_id)
        await self.send(text_data=json.dumps({"type": "replay", "events": events}))

    async def disconnect(self, close_code):
        if hasattr(self, "group_name"):
            await mark_presence(self.user, self.note, self.scope.get("auth"), "offline")
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        event = json.loads(text_data)
        event_type = event.get("type")
        if event_type == "ack":
            stored = await acknowledge_event(self.user, self.scope.get("auth"), event.get("event_id"))
            await self.send(
                text_data=json.dumps(
                    {"type": "ack.received", "event_id": event.get("event_id"), "stored": stored}
                )
            )
            return
        if not self.can_write:
            await self.send(text_data=json.dumps({"type": "error", "code": "viewer_cannot_publish"}))
            return
        if not valid_encrypted_event_payload(event):
            await self.send(text_data=json.dumps({"type": "error", "code": "invalid_encrypted_event"}))
            return
        event = await persist_event(self.user, self.note, event)
        event["type"] = "encrypted.event"
        await self.channel_layer.group_send(
            self.group_name,
            {
                "type": "encrypted.event",
                "payload": event,
            },
        )

    async def encrypted_event(self, event):
        await self.send(text_data=json.dumps(event["payload"]))
