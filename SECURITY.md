# Security

Do not include access tokens, note contents, recovery material or account data
in public bug reports. Report vulnerabilities through the repository's private
security reporting feature when available. Otherwise ask a maintainer for a
private reporting channel without publishing exploit details or private data.

Each self-hosted installation generates its own server and storage credentials
with `python3 tools/init_selfhost.py`. Keep `.env` and backups private and use
HTTPS for remote access. Signing keys for app distribution belong outside the
source checkout.

The secret and personal-data checks in this project reduce accidental disclosure;
they do not replace reviewing changes before committing or publishing.
