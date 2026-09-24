"""Private, persistent ciphertext storage; never served as static/media files."""

from __future__ import annotations

import hashlib
import os
import shutil
import stat
import tempfile
from pathlib import Path

from django.conf import settings


def object_path(object_key: str) -> Path:
    # Logical keys never become filesystem paths, even for older database entries.
    filename = hashlib.sha256(object_key.encode("utf-8")).hexdigest()
    return Path(settings.ATTACHMENT_ROOT) / filename


def write_ciphertext(object_key: str, source) -> None:
    destination = object_path(object_key)
    root = destination.parent
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink():
        raise OSError("Attachment root must not be a symbolic link.")
    # Same-filesystem replacement: interrupted writes leave the old object intact.
    fd, temporary = tempfile.mkstemp(prefix=".upload-", dir=root)
    try:
        with os.fdopen(fd, "wb") as target:
            shutil.copyfileobj(source, target, length=64 * 1024)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


def open_ciphertext(object_key: str):
    path = object_path(object_key)
    if path.parent.is_symlink():
        raise OSError("Attachment root must not be a symbolic link.")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise OSError("Attachment must be a regular file.")
        return os.fdopen(fd, "rb")
    except BaseException:
        os.close(fd)
        raise
