import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WebsiteToolsTest(unittest.TestCase):
    def test_website_links(self):
        subprocess.run(["python3", str(ROOT / "tools/check_website.py")], check=True)

    def test_missing_secrets_stop_deployment(self):
        result = subprocess.run(
            ["bash", str(ROOT / "tools/deploy_website.sh")],
            env={"PATH": os.environ["PATH"]}, capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing GitHub secret: SPANEL_HOST", result.stdout)

    def test_upload_scope_and_private_file_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            fake_rsync = temporary / "rsync"
            fake_rsync.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
            fake_rsync.chmod(0o700)
            environment = {
                "PATH": f"{directory}:{os.environ['PATH']}",
                "TMPDIR": directory,
                "SPANEL_HOST": "host.example.test",
                "SPANEL_USER": "website",
                "SPANEL_LANDING_PATH": "/srv/website",
                "SPANEL_SSH_KEY": "test-fixture-not-a-key",
                "SPANEL_KNOWN_HOSTS": "test-fixture-not-a-host-key",
            }
            result = subprocess.run(
                ["bash", str(ROOT / "tools/deploy_website.sh")],
                env=environment, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = result.stdout.splitlines()
            self.assertNotIn("--delete", arguments)
            self.assertIn("--include=/*.html", arguments)
            self.assertIn("--include=/assets/***", arguments)
            self.assertIn("--exclude=*", arguments)
            self.assertEqual(arguments[-1], "website@host.example.test:/srv/website/")
            self.assertNotIn(environment["SPANEL_SSH_KEY"], result.stdout)
            self.assertEqual(list(temporary.iterdir()), [fake_rsync])
            for target in ["/", "/./", "/srv/../", "/srv/.", "relative"]:
                environment["SPANEL_LANDING_PATH"] = target
                rejected = subprocess.run(
                    ["bash", str(ROOT / "tools/deploy_website.sh")],
                    env=environment, capture_output=True,
                )
                self.assertNotEqual(rejected.returncode, 0)

    def test_apk_upload_is_explicit_and_requires_a_built_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            (temporary / "tools").mkdir()
            site = temporary / "website"
            (site / "downloads").mkdir(parents=True)
            for name in ("index.html", "docs.html"):
                (site / name).write_text("test page")
            script = temporary / "tools/deploy_website.sh"
            shutil.copyfile(ROOT / "tools/deploy_website.sh", script)
            fake_rsync = temporary / "rsync"
            fake_rsync.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
            fake_rsync.chmod(0o700)
            environment = {
                "PATH": f"{directory}:{os.environ['PATH']}",
                "SPANEL_HOST": "host.example.test",
                "SPANEL_USER": "website",
                "SPANEL_LANDING_PATH": "/srv/website",
                "SPANEL_SSH_KEY": "test-fixture-not-a-key",
                "SPANEL_KNOWN_HOSTS": "test-fixture-not-a-host-key",
                "DEPLOY_ANDROID_APK": "true",
            }
            missing = subprocess.run(["bash", str(script)], env=environment, capture_output=True)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn(b"Signed Android APK is missing", missing.stdout)
            (site / "downloads/safernotes-android.apk").write_bytes(b"test artifact")
            result = subprocess.run(
                ["bash", str(script)], env=environment, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--include=/downloads/safernotes-android.apk", result.stdout)
            self.assertNotIn("--delete", result.stdout)


if __name__ == "__main__":
    unittest.main()
