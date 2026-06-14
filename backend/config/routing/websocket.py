"""Websocket URL routing."""

from __future__ import annotations

from django.urls import path

from apps.collaboration.consumers import EncryptedNoteConsumer

websocket_urlpatterns = [
    path("ws/v1/notes/<uuid:note_id>/", EncryptedNoteConsumer.as_asgi()),
]

