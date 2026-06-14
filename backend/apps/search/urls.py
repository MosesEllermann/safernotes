from __future__ import annotations

from django.urls import path

from apps.search.views import SearchStatusView

urlpatterns = [path("status", SearchStatusView.as_view(), name="search-status")]

