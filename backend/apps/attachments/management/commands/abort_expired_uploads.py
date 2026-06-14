from __future__ import annotations

from django.core.management.base import BaseCommand

from apps.attachments.lifecycle import abort_expired_uploads


class Command(BaseCommand):
    help = "Abort expired encrypted attachment upload targets."

    def handle(self, *args, **options):
        count = abort_expired_uploads()
        self.stdout.write(self.style.SUCCESS(f"Aborted {count} expired attachment uploads."))

