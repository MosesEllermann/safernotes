"""Check source distributions for credentials and local machine artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
PRIVATE_SUFFIXES = {".jks", ".keystore", ".pem", ".p12", ".pfx", ".sqlite", ".sqlite3", ".db", ".sql", ".log"}
PRIVATE_PARTS = {".git", ".local", ".venv", ".dart-tool", ".dart_tool", "node_modules", "Pods", "__pycache__", "private-attachments"}
PATTERNS = {
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"),
    "access token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-)?[A-Za-z0-9_-]{25,}|sk_(?:live|test)_[A-Za-z0-9]{20,}|creem_(?:live|test)_[A-Za-z0-9_-]{15,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{35})\b"),
    "personal machine path": re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
}


def source_paths(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root, check=True, capture_output=True,
    )
    return sorted({Path(name) for name in result.stdout.decode().split("\0") if name})


def inspect_source(root: Path, paths: list[Path]) -> list[str]:
    findings = []
    for relative in paths:
        path = root / relative
        if path.is_symlink():
            findings.append(f"{relative}: symbolic link requires manual review")
            continue
        if not path.is_file():
            continue
        if (
            PRIVATE_PARTS.intersection(relative.parts)
            or path.suffix.lower() in PRIVATE_SUFFIXES
            or path.name in {"key.properties", "CLIENT_ID", ".DS_Store"}
            or (path.name.startswith(".env") and path.name not in {".env.example", ".env.selfhost.example"})
        ):
            findings.append(f"{relative}: private/generated file")
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        for description, pattern in PATTERNS.items():
            for match in pattern.finditer(data):
                line = data.count(b"\n", 0, match.start()) + 1
                findings.append(f"{relative}:{line}: {description} (value omitted)")
    return findings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", type=Path, help="Inspect an unpacked source export")
    args = parser.parse_args()
    root = args.tree.resolve() if args.tree else ROOT
    paths = (
        [p.relative_to(root) for p in root.rglob("*") if p.is_file() or p.is_symlink()]
        if args.tree else source_paths(root)
    )
    findings = inspect_source(root, paths)
    if findings:
        parser.exit(1, "\n".join(findings) + "\n")
    count = sum((root / path).is_file() for path in paths)
    print(f"Source checks passed for {count} files.")


if __name__ == "__main__":
    main()
