from __future__ import annotations

from apps.notes.models import CollaboratorRole, NoteKeyGrant
from apps.notes.permissions import can_read_note, can_share_note, can_write_note


def test_note_owner_can_read_write_and_share(note, owner_user):
    assert can_read_note(owner_user, note)
    assert can_write_note(owner_user, note)
    assert can_share_note(owner_user, note)


def test_viewer_can_read_but_not_write_or_share(note, owner_user, recipient_user, encrypted_payload):
    NoteKeyGrant.objects.create(
        note=note,
        recipient_user=recipient_user,
        sender_user=owner_user,
        role=CollaboratorRole.VIEWER,
        encrypted_note_key=encrypted_payload,
        grant_signature=b"signature",
    )

    assert can_read_note(recipient_user, note)
    assert not can_write_note(recipient_user, note)
    assert not can_share_note(recipient_user, note)


def test_editor_can_read_and_write_but_not_share(note, owner_user, recipient_user, encrypted_payload):
    NoteKeyGrant.objects.create(
        note=note,
        recipient_user=recipient_user,
        sender_user=owner_user,
        role=CollaboratorRole.EDITOR,
        encrypted_note_key=encrypted_payload,
        grant_signature=b"signature",
    )

    assert can_read_note(recipient_user, note)
    assert can_write_note(recipient_user, note)
    assert not can_share_note(recipient_user, note)

