from __future__ import annotations

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import decorators, exceptions, response, viewsets

from apps.attachments.quota import can_store_note_bytes, locked_usage_for_tenant
from apps.audit.events import record_audit_event
from apps.core.abuse import increment_metadata_limit
from apps.core.emails import send_share_invitation_email
from apps.notes.models import (
    Label,
    Note,
    NoteConflict,
    NoteKeyGrant,
    ShareInvitation,
    ShareInvitationStatus,
)
from apps.notes.permissions import can_share_note, can_write_note
from apps.notes.serializers import (
    ConflictResolutionSerializer,
    GrantRevocationSerializer,
    LabelSerializer,
    NoteConflictSerializer,
    NoteKeyGrantSerializer,
    NoteSerializer,
    NoteStateSerializer,
    OwnerNoteKeySerializer,
    OwnershipTransferSerializer,
    ShareInvitationDecisionSerializer,
    ShareInvitationSerializer,
)
from apps.notifications.models import Notification


class NoteViewSet(viewsets.ModelViewSet):
    serializer_class = NoteSerializer

    def get_queryset(self):
        return Note.objects.filter(
            Q(owner_user=self.request.user)
            | Q(key_grants__recipient_user=self.request.user, key_grants__revoked_at__isnull=True)
        ).distinct()

    def perform_update(self, serializer):
        if not can_write_note(self.request.user, serializer.instance):
            raise exceptions.PermissionDenied("Viewer role cannot edit encrypted note payloads.")
        serializer.save()

    def perform_destroy(self, instance):
        if not can_write_note(self.request.user, instance):
            raise exceptions.PermissionDenied("Viewer role cannot delete notes.")
        instance.state = "deleted"
        instance.deleted_at = timezone.now()
        instance.save(update_fields=["state", "deleted_at", "updated_at"])

    @decorators.action(detail=False, methods=["post"], url_path="trash/empty")
    def empty_trash(self, request):
        trashed_notes = list(self.get_queryset().filter(state="trashed"))
        writable_ids = [note.id for note in trashed_notes if can_write_note(request.user, note)]
        if not writable_ids:
            return response.Response({"deleted_count": 0})

        deleted_at = timezone.now()
        with transaction.atomic():
            deleted_count = Note.objects.filter(id__in=writable_ids, state="trashed").update(
                state="deleted",
                deleted_at=deleted_at,
                updated_at=deleted_at,
            )
        return response.Response({"deleted_count": deleted_count})

    @decorators.action(detail=True, methods=["post"], url_path="sharing/key")
    def store_owner_key(self, request, pk=None):
        note = self.get_object()
        if note.owner_user != request.user:
            raise exceptions.PermissionDenied("Only note owners can store the owner note key.")
        serializer = OwnerNoteKeySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        grant = (
            NoteKeyGrant.objects.filter(note=note, recipient_user=request.user)
            .order_by("-updated_at")
            .first()
        )
        values = {
            "sender_user": request.user,
            "role": "owner",
            "encrypted_note_key": serializer.validated_data["encrypted_note_key"],
            "grant_signature": serializer.validated_data["grant_signature"],
            "revoked_at": None,
            "revoked_reason": "",
        }
        if grant is None:
            grant = NoteKeyGrant.objects.create(note=note, recipient_user=request.user, **values)
        else:
            for field, value in values.items():
                setattr(grant, field, value)
            grant.save(update_fields=[*values, "updated_at"])
        return response.Response(NoteKeyGrantSerializer(grant, context={"request": request}).data)

    @decorators.action(detail=True, methods=["get"], url_path="sharing")
    def sharing(self, request, pk=None):
        note = self.get_object()
        if note.owner_user != request.user:
            raise exceptions.PermissionDenied("Only note owners can manage access.")
        participants = [
            {
                "id": str(grant.id),
                "type": "grant",
                "email": grant.recipient_user.email,
                "role": grant.role,
                "status": "accepted",
            }
            for grant in note.key_grants.select_related("recipient_user")
            .filter(revoked_at__isnull=True)
            .exclude(recipient_user=note.owner_user)
        ]
        participants.extend(
            {
                "id": str(invitation.id),
                "type": "invitation",
                "email": invitation.recipient_user.email,
                "role": invitation.role,
                "status": invitation.status,
            }
            for invitation in note.share_invitations.select_related("recipient_user").filter(
                status=ShareInvitationStatus.PENDING
            )
        )
        return response.Response({"results": participants})

    @decorators.action(detail=True, methods=["patch"], url_path="state")
    def state(self, request, pk=None):
        note = self.get_object()
        if not can_write_note(request.user, note):
            raise exceptions.PermissionDenied("Viewer role cannot change note state.")
        serializer = NoteStateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        next_state = serializer.validated_data["state"]
        previous_bytes = 0 if note.state == "deleted" else note.storage_bytes
        next_bytes = 0 if next_state == "deleted" else note.storage_bytes
        with transaction.atomic():
            usage = locked_usage_for_tenant(note.tenant)
            if not can_store_note_bytes(
                note.tenant,
                previous_bytes=previous_bytes,
                next_bytes=next_bytes,
                attachment_usage=usage,
            ):
                raise exceptions.ValidationError("Workspace storage quota exceeded.")
            note.state = next_state
            note.deleted_at = timezone.now() if note.state == "deleted" else None
            note.save(update_fields=["state", "deleted_at", "updated_at"])
        return response.Response(NoteSerializer(note, context={"request": request}).data)

    @decorators.action(detail=True, methods=["get"])
    def conflicts(self, request, pk=None):
        note = self.get_object()
        conflicts = NoteConflict.objects.filter(note=note, resolved_at__isnull=True)
        return response.Response(NoteConflictSerializer(conflicts, many=True).data)

    @decorators.action(
        detail=True, methods=["post"], url_path=r"conflicts/(?P<conflict_id>[^/.]+)/resolve"
    )
    def resolve_conflict(self, request, pk=None, conflict_id=None):
        note = self.get_object()
        if not can_write_note(request.user, note):
            raise exceptions.PermissionDenied("Viewer role cannot resolve note conflicts.")
        serializer = ConflictResolutionSerializer(data=request.data or {})
        serializer.is_valid(raise_exception=True)
        conflict = get_object_or_404(
            NoteConflict, note=note, id=conflict_id, resolved_at__isnull=True
        )
        if serializer.validated_data["resolved"]:
            conflict.resolved_at = timezone.now()
            conflict.save(update_fields=["resolved_at", "updated_at"])
        return response.Response(NoteConflictSerializer(conflict).data)

    @decorators.action(detail=True, methods=["post"], url_path="transfer-owner")
    def transfer_owner(self, request, pk=None):
        note = self.get_object()
        if not can_share_note(request.user, note):
            raise exceptions.PermissionDenied("Only note owners can transfer ownership.")
        serializer = OwnershipTransferSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_owner = serializer.validated_data["new_owner_user"]
        if new_owner == request.user:
            raise exceptions.ValidationError("New owner is already the current owner.")

        grant, _ = NoteKeyGrant.objects.update_or_create(
            note=note,
            recipient_user=new_owner,
            defaults={
                "sender_user": request.user,
                "role": "owner",
                "encrypted_note_key": serializer.validated_data["encrypted_note_key"],
                "grant_signature": serializer.validated_data["transfer_signature"],
                "revoked_at": None,
                "revoked_reason": "",
            },
        )
        previous_owner = note.owner_user
        note.owner_user = new_owner
        note.save(update_fields=["owner_user", "updated_at"])
        NoteKeyGrant.objects.filter(
            note=note, recipient_user=previous_owner, revoked_at__isnull=True
        ).update(
            role="editor",
            updated_at=timezone.now(),
        )
        notification_payload = serializer.validated_data.get("encrypted_notification_payload")
        if notification_payload:
            Notification.objects.create(
                user=new_owner,
                type="ownership_transfer",
                encrypted_payload=notification_payload,
            )
        record_audit_event(
            event_type="sharing.owner_transferred",
            actor_user=request.user,
            tenant=note.tenant,
            target_type="note",
            target_id=note.id,
            metadata={
                "new_owner_user_id": str(new_owner.id),
                "previous_owner_user_id": str(previous_owner.id),
            },
        )
        return response.Response(NoteKeyGrantSerializer(grant, context={"request": request}).data)


class NoteKeyGrantViewSet(viewsets.ModelViewSet):
    serializer_class = NoteKeyGrantSerializer

    def get_queryset(self):
        return NoteKeyGrant.objects.filter(
            Q(note__owner_user=self.request.user)
            | Q(
                note__key_grants__recipient_user=self.request.user,
                note__key_grants__revoked_at__isnull=True,
            )
        ).distinct()

    def perform_create(self, serializer):
        allowed, count = increment_metadata_limit("share_invite", str(self.request.user.id))
        if not allowed:
            raise exceptions.ValidationError(
                {"detail": "Share invitation rate limit exceeded.", "count": count}
            )
        note = serializer.validated_data["note"]
        if not can_share_note(self.request.user, note):
            raise exceptions.PermissionDenied("Only note owners can share encrypted note keys.")
        grant = serializer.save()
        record_audit_event(
            event_type="sharing.grant_created",
            actor_user=self.request.user,
            tenant=note.tenant,
            target_type="note_key_grant",
            target_id=grant.id,
            metadata={
                "note_id": str(note.id),
                "recipient_user_id": str(grant.recipient_user_id),
                "role": grant.role,
            },
        )

    def perform_update(self, serializer):
        if not can_share_note(self.request.user, serializer.instance.note):
            raise exceptions.PermissionDenied("Only note owners can change note key grants.")
        serializer.save()

    def perform_destroy(self, instance):
        if not can_share_note(self.request.user, instance.note):
            raise exceptions.PermissionDenied("Only note owners can revoke note key grants.")
        serializer = GrantRevocationSerializer(data=self.request.data or {})
        serializer.is_valid(raise_exception=True)
        instance.revoked_at = timezone.now()
        instance.revoked_reason = serializer.validated_data.get("reason", "")
        instance.save(update_fields=["revoked_at", "revoked_reason", "updated_at"])
        record_audit_event(
            event_type="sharing.grant_revoked",
            actor_user=self.request.user,
            tenant=instance.note.tenant,
            target_type="note_key_grant",
            target_id=instance.id,
            metadata={"reason": instance.revoked_reason, "note_id": str(instance.note_id)},
        )


class ShareInvitationViewSet(viewsets.ModelViewSet):
    serializer_class = ShareInvitationSerializer

    def get_queryset(self):
        return ShareInvitation.objects.filter(
            Q(sender_user=self.request.user) | Q(recipient_user=self.request.user)
        ).distinct()

    @decorators.action(detail=False, methods=["get"], url_path="contacts")
    def contacts(self, request):
        invitations = (
            self.get_queryset()
            .select_related("sender_user", "recipient_user")
            .order_by("-created_at")[:100]
        )
        contacts = []
        seen = set()
        for invitation in invitations:
            other_user = (
                invitation.recipient_user
                if invitation.sender_user_id == request.user.id
                else invitation.sender_user
            )
            email = other_user.email
            normalized = email.casefold()
            if normalized in seen:
                continue
            seen.add(normalized)
            contacts.append(
                {
                    "email": email,
                    "last_role": invitation.role,
                    "last_direction": "sent"
                    if invitation.sender_user_id == request.user.id
                    else "received",
                    "last_invited_at": invitation.created_at,
                }
            )
            if len(contacts) >= 12:
                break
        return response.Response({"results": contacts})

    def perform_create(self, serializer):
        note = serializer.validated_data["note"]
        if not can_share_note(self.request.user, note):
            raise exceptions.PermissionDenied("Only note owners can invite collaborators.")
        invitation = serializer.save()
        if not getattr(serializer, "invitation_created", True):
            return
        notification_payload = getattr(serializer, "encrypted_notification_payload", None)
        if notification_payload:
            Notification.objects.create(
                user=invitation.recipient_user,
                type="share_invitation",
                encrypted_payload=notification_payload,
            )
        send_share_invitation_email(invitation)
        record_audit_event(
            event_type="sharing.invitation_created",
            actor_user=self.request.user,
            tenant=note.tenant,
            target_type="share_invitation",
            target_id=invitation.id,
            metadata={
                "note_id": str(note.id),
                "recipient_user_id": str(invitation.recipient_user_id),
                "role": invitation.role,
            },
        )

    def perform_destroy(self, instance):
        if instance.sender_user != self.request.user:
            raise exceptions.PermissionDenied("Only invitation senders can revoke invitations.")
        instance.status = ShareInvitationStatus.REVOKED
        instance.revoked_at = timezone.now()
        instance.save(update_fields=["status", "revoked_at", "updated_at"])
        record_audit_event(
            event_type="sharing.invitation_revoked",
            actor_user=self.request.user,
            tenant=instance.note.tenant,
            target_type="share_invitation",
            target_id=instance.id,
        )

    @decorators.action(detail=True, methods=["post"])
    def decide(self, request, pk=None):
        invitation = self.get_object()
        if invitation.recipient_user != request.user:
            raise exceptions.PermissionDenied("Only invitation recipients can accept or decline.")
        if invitation.status != ShareInvitationStatus.PENDING:
            raise exceptions.ValidationError("Invitation is no longer pending.")
        serializer = ShareInvitationDecisionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        decision = serializer.validated_data["decision"]
        if decision == "decline":
            invitation.status = ShareInvitationStatus.DECLINED
            invitation.declined_at = timezone.now()
            invitation.save(update_fields=["status", "declined_at", "updated_at"])
            record_audit_event(
                event_type="sharing.invitation_declined",
                actor_user=request.user,
                tenant=invitation.note.tenant,
                target_type="share_invitation",
                target_id=invitation.id,
            )
            return response.Response(
                ShareInvitationSerializer(invitation, context={"request": request}).data
            )

        grant = (
            NoteKeyGrant.objects.filter(
                note=invitation.note, recipient_user=invitation.recipient_user
            )
            .order_by("-updated_at")
            .first()
        )
        values = {
            "sender_user": invitation.sender_user,
            "role": invitation.role,
            "encrypted_note_key": invitation.encrypted_note_key,
            "grant_signature": invitation.invitation_signature,
            "source_invitation": invitation,
            "revoked_at": None,
            "revoked_reason": "",
        }
        if grant is None:
            grant = NoteKeyGrant.objects.create(
                note=invitation.note,
                recipient_user=invitation.recipient_user,
                **values,
            )
        else:
            for field, value in values.items():
                setattr(grant, field, value)
            grant.save(update_fields=[*values, "updated_at"])
        invitation.status = ShareInvitationStatus.ACCEPTED
        invitation.accepted_at = timezone.now()
        invitation.save(update_fields=["status", "accepted_at", "updated_at"])
        record_audit_event(
            event_type="sharing.invitation_accepted",
            actor_user=request.user,
            tenant=invitation.note.tenant,
            target_type="share_invitation",
            target_id=invitation.id,
            metadata={"grant_id": str(grant.id)},
        )
        return response.Response(
            {
                "invitation": ShareInvitationSerializer(
                    invitation, context={"request": request}
                ).data,
                "grant": NoteKeyGrantSerializer(grant, context={"request": request}).data,
            }
        )


class LabelViewSet(viewsets.ModelViewSet):
    serializer_class = LabelSerializer

    def get_queryset(self):
        return Label.objects.filter(owner_user=self.request.user)
