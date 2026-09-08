from __future__ import annotations

import json

from django.db import migrations, models


def _storage_size(note) -> int:
    serialized = json.dumps(
        note.encrypted_payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return len(serialized.encode("utf-8")) + len(note.payload_hash or b"")


def backfill_note_storage_bytes(apps, schema_editor):
    Note = apps.get_model("notes", "Note")
    pending = []
    for note in Note.objects.only(
        "id",
        "encrypted_payload",
        "payload_hash",
    ).iterator(chunk_size=500):
        note.storage_bytes = _storage_size(note)
        pending.append(note)
        if len(pending) == 500:
            Note.objects.bulk_update(pending, ["storage_bytes"])
            pending.clear()
    if pending:
        Note.objects.bulk_update(pending, ["storage_bytes"])


class Migration(migrations.Migration):
    dependencies = [
        ("notes", "0002_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="storage_bytes",
            field=models.PositiveBigIntegerField(default=0, editable=False),
        ),
        migrations.RunPython(
            backfill_note_storage_bytes,
            reverse_code=migrations.RunPython.noop,
        ),
    ]
