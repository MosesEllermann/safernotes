from __future__ import annotations

import io
import os
import stat

import pytest

from apps.attachments.storage import object_path, open_ciphertext, write_ciphertext


@pytest.fixture(autouse=True)
def private_storage(settings, tmp_path):
    settings.ATTACHMENT_ROOT = tmp_path / "private-attachments"
    return settings.ATTACHMENT_ROOT


@pytest.mark.parametrize("key", ["attachments/tenant/note/id", "../../outside", "/etc/passwd", "a\\b", ""])
def test_keys_cannot_escape_storage_and_reads_are_persistent(private_storage, key):
    content = b"encrypted-content" * 10000
    write_ciphertext(key, io.BytesIO(content))
    path = object_path(key)
    assert path.parent == private_storage
    assert len(path.name) == 64
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    # Reopening is independent of the process's in-memory upload state.
    for _ in range(2):
        with open_ciphertext(key) as stored:
            assert stored.read() == content


def test_interrupted_write_preserves_old_file_and_removes_temporary(private_storage):
    write_ciphertext("key", io.BytesIO(b"original"))

    class BrokenSource:
        reads = 0

        def read(self, size):
            self.reads += 1
            if self.reads == 1:
                return b"partial"
            raise OSError("disk failure")

    with pytest.raises(OSError):
        write_ciphertext("key", BrokenSource())
    with open_ciphertext("key") as stored:
        assert stored.read() == b"original"
    assert list(private_storage.iterdir()) == [object_path("key")]


def test_failed_replace_does_not_publish_or_leave_temporary(private_storage, monkeypatch):
    def fail(*args):
        raise OSError("storage full")

    monkeypatch.setattr("apps.attachments.storage.os.replace", fail)
    with pytest.raises(OSError):
        write_ciphertext("key", io.BytesIO(b"data"))
    assert list(private_storage.iterdir()) == []


def test_symlink_is_not_read_or_written_through(private_storage, tmp_path):
    private_storage.mkdir()
    outside = tmp_path / "outside"
    outside.write_bytes(b"private")
    object_path("key").symlink_to(outside)
    with pytest.raises(OSError):
        open_ciphertext("key")
    write_ciphertext("key", io.BytesIO(b"ciphertext"))
    assert outside.read_bytes() == b"private"
    assert not object_path("key").is_symlink()
    with open_ciphertext("key") as stored:
        assert stored.read() == b"ciphertext"


def test_symlink_root_is_rejected(private_storage, tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    private_storage.symlink_to(outside, target_is_directory=True)
    with pytest.raises(OSError):
        write_ciphertext("key", io.BytesIO(b"ciphertext"))
    with pytest.raises(OSError):
        open_ciphertext("key")
    assert list(outside.iterdir()) == []


def test_nonregular_file_is_rejected_without_blocking(private_storage):
    private_storage.mkdir()
    os.mkfifo(object_path("key"))
    with pytest.raises(OSError):
        open_ciphertext("key")


def test_missing_file_raises_without_creating_storage(private_storage):
    with pytest.raises(FileNotFoundError):
        open_ciphertext("missing")
    assert not private_storage.exists()
