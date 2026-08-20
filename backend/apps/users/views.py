from __future__ import annotations

from rest_framework import generics, response, views

from apps.users.models import User
from apps.users.serializers import PublicKeysSerializer, UserPreferencesSerializer, UserSerializer


class MeView(generics.RetrieveAPIView):
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class PreferencesView(views.APIView):
    def patch(self, request):
        serializer = UserPreferencesSerializer(
            instance=request.user, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        profile = serializer.save()
        return response.Response({"locale": profile.locale})


class PublicKeysView(generics.RetrieveAPIView):
    queryset = User.objects.select_related("key_material")
    serializer_class = PublicKeysSerializer
