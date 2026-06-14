from __future__ import annotations

from apps.notes.models import CollaboratorRole, Note, NoteKeyGrant

WRITE_ROLES = {CollaboratorRole.OWNER, CollaboratorRole.EDITOR}
SHARE_ROLES = {CollaboratorRole.OWNER}


def user_role_for_note(user, note: Note) -> str | None:
    if not user or not user.is_authenticated:
        return None
    if note.owner_user_id == user.id:
        return CollaboratorRole.OWNER
    grant = (
        NoteKeyGrant.objects.filter(note=note, recipient_user=user, revoked_at__isnull=True)
        .order_by("-created_at")
        .first()
    )
    return grant.role if grant else None


def can_read_note(user, note: Note) -> bool:
    return user_role_for_note(user, note) is not None


def can_write_note(user, note: Note) -> bool:
    return user_role_for_note(user, note) in WRITE_ROLES


def can_share_note(user, note: Note) -> bool:
    return user_role_for_note(user, note) in SHARE_ROLES

