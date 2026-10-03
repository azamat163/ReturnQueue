#!/usr/bin/env python3
"""Offline tests: invalid signing inputs fail before any actual signing/upload."""
import base64
import copy
import datetime
import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
REPOSITORY = DIRECTORY.parent.parent
module_spec = importlib.util.spec_from_file_location("profile_options", DIRECTORY / "profile-options.py")
module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(module)


class SigningProfileTests(unittest.TestCase):
    def setUp(self):
        self.certificate = b"synthetic DER for fingerprint checking; never a signing credential"
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest().upper()
        self.profile = {
            "UUID": "12345678-1234-1234-1234-123456789012",
            "TeamIdentifier": ["TEAM123456"],
            "Platform": ["iOS"],
            "ApplicationIdentifierPrefix": ["PREFIX1234"],
            "DeveloperCertificates": [self.certificate],
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
            "Entitlements": {
                "application-identifier": "PREFIX1234.com.example.returnqueue",
                "com.apple.developer.team-identifier": "TEAM123456",
                "get-task-allow": False,
            },
        }

    def options(self, profile=None, **changes):
        settings = {"team": "TEAM123456", "bundle": "com.example.returnqueue", "certificate": self.fingerprint}
        settings.update(changes)
        return module.export_options(profile or self.profile, **settings)

    def test_export_does_not_upload_or_change_version(self):
        uuid, options = self.options()
        self.assertEqual(options["destination"], "export")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])
        self.assertEqual(options["provisioningProfiles"], {"com.example.returnqueue": uuid})

    def test_wrong_app_team_certificate_fail(self):
        for change in ({"bundle": "com.other.app"}, {"team": "OTHER12345"}, {"certificate": "0" * 40}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.options(**change)

    def test_development_adhoc_enterprise_and_expired_fail(self):
        for update in (
            {"ProvisionedDevices": ["device"]},
            {"ProvisionsAllDevices": True},
            {"ExpirationDate": datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=1)},
        ):
            candidate = copy.deepcopy(self.profile)
            candidate.update(update)
            with self.subTest(update=update), self.assertRaises(ValueError):
                self.options(candidate)
        candidate = copy.deepcopy(self.profile)
        candidate["Entitlements"]["get-task-allow"] = True
        with self.assertRaises(ValueError):
            self.options(candidate)

    def test_wildcard_profile_fails(self):
        candidate = copy.deepcopy(self.profile)
        candidate["Entitlements"]["application-identifier"] = "PREFIX1234.*"
        with self.assertRaises(ValueError):
            self.options(candidate)

    def test_release_scripts_fail_without_protected_ci_ref(self):
        # Neither script gets beyond preflight, creates keychains, reads credentials, nor uploads.
        environment = {name: value for name, value in os.environ.items() if not name.startswith(("CI_", "IOS_", "ASC_", "TESTFLIGHT_"))}
        for script in ("archive-ios.sh", "upload-testflight.sh"):
            result = subprocess.run(["bash", str(DIRECTORY / script)], cwd=REPOSITORY,
                                    env=environment, capture_output=True, text=True)
            with self.subTest(script=script):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Release setup error:", result.stderr)

    def test_debug_trace_is_rejected_before_credential_access(self):
        environment = dict(os.environ, CI_DEBUG_TRACE="true")
        for script in ("archive-ios.sh", "upload-testflight.sh"):
            result = subprocess.run(["bash", str(DIRECTORY / script)], cwd=REPOSITORY,
                                    env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Disable CI_DEBUG_TRACE", result.stderr)

    def test_binary_secret_decoding_preserves_bytes_and_private_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            encoded = Path(directory) / "encoded"
            output = Path(directory) / "binary"
            binary = b"\x00\x80\xff\n\rsecret fixture"
            encoded.write_bytes(base64.encodebytes(binary))
            result = subprocess.run([sys.executable, str(DIRECTORY / "decode-file.py"), str(encoded), str(output)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_bytes(), binary)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("secret fixture", result.stdout + result.stderr)

    def test_invalid_encoded_secret_and_overwrite_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            encoded = Path(directory) / "encoded"
            output = Path(directory) / "binary"
            for content in (b"invalid@base64", b""):
                encoded.write_bytes(content)
                result = subprocess.run([sys.executable, str(DIRECTORY / "decode-file.py"), str(encoded), str(output)],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())
            encoded.write_bytes(base64.b64encode(b"replacement"))
            output.write_bytes(b"existing")
            result = subprocess.run([sys.executable, str(DIRECTORY / "decode-file.py"), str(encoded), str(output)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b"existing")


if __name__ == "__main__":
    unittest.main()
