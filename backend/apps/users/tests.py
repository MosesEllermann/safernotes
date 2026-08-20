from __future__ import annotations

from rest_framework.test import APIRequestFactory, force_authenticate

from apps.users.views import PreferencesView


def test_preferences_view_updates_locale(db, django_user_model):
    user = django_user_model.objects.create_user(
        email="locale@example.com", password="strong-password"
    )
    request = APIRequestFactory().patch(
        "/api/v1/users/me/preferences",
        {"locale": "de"},
        format="json",
    )
    force_authenticate(request, user=user)

    response = PreferencesView.as_view()(request)

    assert response.status_code == 200
    assert response.data["locale"] == "de"
    user.profile.refresh_from_db()
    assert user.profile.locale == "de"
