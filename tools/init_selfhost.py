"""Create a private self-hosting environment without overwriting existing secrets."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import secrets
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from config.public_url import public_origin


def create_environment(destination: Path, url: str = "http://localhost:8080") -> None:
    template = Path(__file__).resolve().parents[1] / ".env.selfhost.example"
    values = {
        "PUBLIC_URL": public_origin(url),
        "SECRET_KEY": secrets.token_hex(32),
        "POSTGRES_PASSWORD": secrets.token_hex(32),
    }
    lines = []
    for line in template.read_text().splitlines():
        name = line.partition("=")[0]
        lines.append(f"{name}={values[name]}" if name in values else line)
    # Exclusive creation protects an existing installation's credentials.
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(".env"))
    parser.add_argument("--url", default="http://localhost:8080", help="Public HTTPS URL (or local test URL).")
    args = parser.parse_args()
    try:
        create_environment(args.output, args.url)
    except FileExistsError:
        parser.exit(1, "Environment already exists; its credentials were left unchanged.\n")
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    print("Private environment created. Start with docker compose up --build -d.")


if __name__ == "__main__":
    main()
