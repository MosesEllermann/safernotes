from pathlib import Path
import stat
import tempfile
import unittest

from check_source import inspect_source
from init_selfhost import create_environment


class SourceToolsTest(unittest.TestCase):
    def test_public_url_is_the_only_public_address(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / ".env"
            create_environment(destination, "https://notes.example.com/")
            contents = destination.read_text()
            self.assertIn("PUBLIC_URL=https://notes.example.com\n", contents)
            for name in ("ALLOWED_HOSTS", "CORS_ALLOWED_ORIGINS", "APP_BASE_URL", "WEBSITE_BASE_URL"):
                self.assertNotIn(name + "=", contents)

    def test_invalid_public_url_does_not_create_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / ".env"
            for url in ("https://", "https://host/path", "https://user:pwd@host", "http://example.com", "https://host?x=1", "https://host#fragment", "https://host\nINJECT=value"):
                with self.assertRaises(ValueError):
                    create_environment(destination, url)
                self.assertFalse(destination.exists())

    def test_environment_has_independent_secrets_and_cannot_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / ".env"
            create_environment(destination)
            original = destination.read_bytes()
            values = dict(
                line.split("=", 1) for line in original.decode().splitlines()
                if line and not line.startswith("#")
            )
            secrets = [values[name] for name in ("SECRET_KEY", "POSTGRES_PASSWORD", "MINIO_ROOT_PASSWORD")]
            self.assertEqual(len(set(secrets)), 3)
            self.assertTrue(all(len(value) == 64 for value in secrets))
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
            with self.assertRaises(FileExistsError):
                create_environment(destination)
            self.assertEqual(destination.read_bytes(), original)

    def test_private_files_and_tokens_are_rejected_without_echoing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".env").write_text("private config")
            token = "ghp_" + "A" * 36
            (root / "source.txt").write_text(token)
            findings = inspect_source(root, [Path(".env"), Path("source.txt")])
            self.assertEqual(len(findings), 2)
            self.assertNotIn(token, "\n".join(findings))

    def test_symlink_cannot_include_external_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "external.txt").symlink_to("/nonexistent/private-file")
            self.assertIn("symbolic link", inspect_source(root, [Path("external.txt")])[0])


if __name__ == "__main__":
    unittest.main()
