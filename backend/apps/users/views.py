from __future__ import annotations

from rest_framework import generics

from apps.users.models import User
from apps.users.serializers import PublicKeysSerializer, UserSerializer


class MeView(generics.RetrieveAPIView):
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class PublicKeysView(generics.RetrieveAPIView):
    queryset = User.objects.select_related("key_material")
    serializer_class = PublicKeysSerializer

