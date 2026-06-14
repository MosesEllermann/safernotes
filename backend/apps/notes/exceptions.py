from __future__ import annotations

from rest_framework.exceptions import APIException


class VersionConflict(APIException):
    status_code = 409
    default_detail = "Encrypted note version conflict."
    default_code = "version_conflict"

