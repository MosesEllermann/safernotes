from __future__ import annotations

from rest_framework import viewsets

from apps.tenants.models import Membership, Organization
from apps.tenants.serializers import MembershipSerializer, OrganizationSerializer


class OrganizationViewSet(viewsets.ModelViewSet):
    serializer_class = OrganizationSerializer

    def get_queryset(self):
        return Organization.objects.filter(memberships__user=self.request.user).distinct()


class MembershipViewSet(viewsets.ModelViewSet):
    serializer_class = MembershipSerializer

    def get_queryset(self):
        return Membership.objects.filter(tenant__memberships__user=self.request.user).distinct()

