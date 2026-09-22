"""Create a private self-hosting environment without overwriting existing secrets."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import secrets


def create_environment(destination: Path) -> None:
    template = Path(__file__).resolve().parents[1] / ".env.selfhost.example"
    values = {
        "SECRET_KEY": secrets.token_hex(32),
        "POSTGRES_PASSWORD": secrets.token_hex(32),
        "MINIO_ROOT_PASSWORD": secrets.token_hex(32),
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
    args = parser.parse_args()
    try:
        create_environment(args.output)
    except FileExistsError:
        parser.exit(1, "Environment already exists; its credentials were left unchanged.\n")
    print("Private environment created. Review URLs and SMTP before starting Docker.")


if __name__ == "__main__":
    main()
