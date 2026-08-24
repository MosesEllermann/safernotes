from __future__ import annotations

from rest_framework import exceptions, generics, response, views

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


class PublicKeysLookupView(views.APIView):
    def get(self, request):
        email = request.query_params.get("email", "").strip()
        if not email:
            raise exceptions.ValidationError({"email": "Email is required."})
        user = User.objects.select_related("key_material").filter(email__iexact=email).first()
        if user is None:
            raise exceptions.NotFound("No user found for this email.")
        return response.Response(PublicKeysSerializer(user).data)
