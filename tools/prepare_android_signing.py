"""Decode CI signing secrets into a private directory outside the checkout."""

import argparse
import base64
import binascii
import os
from pathlib import Path
import re


def prepare(destination: Path, environment: dict[str, str]) -> None:
    decoded = {}
    for name in ("ANDROID_KEYSTORE_BASE64", "ANDROID_KEY_PROPERTIES_BASE64"):
        value = environment.get(name, "")
        if not value:
            raise ValueError(f"Missing GitHub secret: {name}")
        try:
            decoded[name] = base64.b64decode("".join(value.split()), validate=True)
        except (ValueError, binascii.Error):
            raise ValueError(f"Invalid base64 in GitHub secret: {name}") from None
        if not decoded[name]:
            raise ValueError(f"Empty GitHub secret: {name}")
    try:
        properties = decoded["ANDROID_KEY_PROPERTIES_BASE64"].decode("utf-8")
    except UnicodeDecodeError:
        raise ValueError("Android signing properties must be UTF-8 text") from None
    for name in ("storePassword", "keyPassword", "keyAlias"):
        if not re.search(rf"(?m)^\s*{name}\s*[:=]\s*\S", properties):
            raise ValueError(f"Missing Android signing property: {name}")
    # Old secrets can contain a developer-machine or Gradle-relative path.
    # Both files live together in the runner's private temporary directory now.
    properties = re.sub(r"(?m)^[ \t]*storeFile\s*[:=].*(?:\n|$)", "", properties)
    properties = properties.rstrip() + "\nstoreFile=upload-keystore.jks\n"
    if destination.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        raise ValueError("Signing files must be outside the repository")
    destination.mkdir(mode=0o700, parents=False, exist_ok=False)
    for name, content in (
        ("upload-keystore.jks", decoded["ANDROID_KEYSTORE_BASE64"]),
        ("key.properties", properties.encode()),
    ):
        with (destination / name).open("xb") as stream:
            os.chmod(destination / name, 0o600)
            stream.write(content)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.destination, dict(os.environ))
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")
    print("Private Android signing files prepared.")


if __name__ == "__main__":
    main()
