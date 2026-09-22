# Contributing

Use [the development guide](docs/DEVELOPMENT.md) to set up the project.
Keep changes focused and describe the behavior being changed and how you checked it.

Before submitting backend changes, run Django checks, the migration check and pytest.
For client changes, run Flutter analysis and the relevant tests.

Never commit credentials, signing keys, database copies, device caches, account
records or screenshots containing real notes. Use fictional data in tests.
Local environment files and generated output are excluded from Git and Docker
build contexts.

Preserve the client-side encryption boundary: the server must never receive
plaintext note titles, bodies, checklist items or attachment contents.

Contributions are distributed under the project's AGPL-3.0-or-later license.
Retain third-party copyright and license notices.
