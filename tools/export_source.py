"""Export reviewed working-tree source without Git history or ignored local data."""

from __future__ import annotations

import argparse
from pathlib import Path
import zipfile

from check_source import ROOT, inspect_source, source_paths


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New ZIP path outside this repository")
    args = parser.parse_args()
    destination = args.output.resolve()
    if destination.is_relative_to(ROOT):
        parser.error("Choose a destination outside the repository.")
    paths = source_paths(ROOT)
    findings = inspect_source(ROOT, paths)
    if findings:
        parser.exit(1, "\n".join(findings) + "\n")
    # Exclusive creation avoids replacing an existing source release.
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for relative in paths:
            path = ROOT / relative
            if path.is_file():
                archive.write(path, Path("safernotes") / relative)
    print("Source export created without history, ignored files or local credentials.")


if __name__ == "__main__":
    main()
