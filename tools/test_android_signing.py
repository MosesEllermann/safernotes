import base64
from pathlib import Path
import tempfile
import unittest

from prepare_android_signing import prepare


class AndroidSigningTest(unittest.TestCase):
    def environment(self):
        properties = (
            "storePassword=test-password\nkeyPassword=test-password\n"
            "keyAlias=upload\nstoreFile=old/location/upload-keystore.jks\n"
        )
        return {
            "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"test-keystore-fixture").decode(),
            "ANDROID_KEY_PROPERTIES_BASE64": base64.b64encode(properties.encode()).decode(),
        }

    def test_external_signing_directory_and_legacy_path(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "signing"
            prepare(destination, self.environment())
            key = destination / "upload-keystore.jks"
            properties = destination / "key.properties"
            self.assertEqual(key.read_bytes(), b"test-keystore-fixture")
            self.assertIn("storeFile=upload-keystore.jks\n", properties.read_text())
            self.assertNotIn("old/location", properties.read_text())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            self.assertEqual(properties.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                prepare(destination, self.environment())

    def test_invalid_secrets_do_not_create_files_or_echo_values(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "signing"
            with self.assertRaisesRegex(ValueError, "Missing GitHub secret"):
                prepare(destination, {})
            environment = self.environment()
            environment["ANDROID_KEYSTORE_BASE64"] = "bad-value!"
            with self.assertRaises(ValueError) as caught:
                prepare(destination, environment)
            self.assertNotIn("bad-value", str(caught.exception))
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
