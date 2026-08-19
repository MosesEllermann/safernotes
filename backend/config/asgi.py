"""ASGI entrypoint for HTTP and websocket traffic."""

from __future__ import annotations

import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.production")

django_asgi_app = get_asgi_application()

from apps.authentication.websocket import BearerTokenAuthMiddleware  # noqa: E402
from config.routing.websocket import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": BearerTokenAuthMiddleware(URLRouter(websocket_urlpatterns)),
    }
)
