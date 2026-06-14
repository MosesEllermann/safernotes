from __future__ import annotations

from types import SimpleNamespace

import pytest


@pytest.fixture
def encrypted_payload():
    return {
        "version": 1,
        "algorithm": "XCHACHA20_POLY1305",
        "nonce": "nonce",
        "ciphertext": "ciphertext",
    }


@pytest.fixture
def owner_user(db, django_user_model):
    return django_user_model.objects.create_user(email="owner@example.com", password="strong-password")


@pytest.fixture
def recipient_user(db, django_user_model):
    return django_user_model.objects.create_user(email="recipient@example.com", password="strong-password")


@pytest.fixture
def tenant(db, owner_user, encrypted_payload):
    from apps.tenants.models import Membership, Organization

    organization = Organization.objects.create(name_ciphertext=encrypted_payload, owner_user=owner_user)
    Membership.objects.create(tenant=organization, user=owner_user, role="owner")
    return organization


@pytest.fixture
def note(db, tenant, owner_user, encrypted_payload):
    from apps.notes.models import Note

    return Note.objects.create(
        tenant=tenant,
        owner_user=owner_user,
        encrypted_payload=encrypted_payload,
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )


@pytest.fixture
def request_for(owner_user):
    def build(user=None, auth=None):
        return SimpleNamespace(user=user or owner_user, auth=auth)

    return build

