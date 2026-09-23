"""Keep short-lived transfer credentials out of HTTP access logs."""

import logging
import re


class RedactTransferToken(logging.Filter):
    def filter(self, record):
        message = record.getMessage()
        if "/attachments/" in message and "token=" in message:
            record.msg = re.sub(r"([?&]token=)[^\s&\"]+", r"\1[redacted]", message)
            record.args = ()
        return True
