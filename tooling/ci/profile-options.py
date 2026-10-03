#!/usr/bin/env python3
"""Validate a decoded App Store profile and emit Xcode export options.

Only the UUID is printed. The profile and generated plist stay outside artifacts.
"""
import argparse
import datetime
import hashlib
import plistlib
import re
import sys
from pathlib import Path


def export_options(profile, team, bundle, certificate):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    uuid = profile.get("UUID", "")
    require(bool(re.fullmatch(r"[A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12}", uuid)), "Invalid profile UUID")
    require(team in profile.get("TeamIdentifier", []), "Profile team does not match IOS_TEAM_ID")
    require("iOS" in profile.get("Platform", []), "Profile is not for iOS")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    entitlements = profile.get("Entitlements", {})
    require(
        any(entitlements.get("application-identifier") == f"{prefix}.{bundle}" for prefix in prefixes),
        "Profile requires an explicit matching bundle identifier",
    )
    require(entitlements.get("com.apple.developer.team-identifier") == team, "Entitlement team mismatch")
    require(entitlements.get("get-task-allow") is False, "A distribution profile is required")
    require(not profile.get("ProvisionedDevices"), "Ad hoc/development profiles are unsupported")
    require(not profile.get("ProvisionsAllDevices"), "Enterprise profiles are unsupported")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime.datetime), "Profile expiration is missing")
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=datetime.timezone.utc)
    require(expiry > datetime.datetime.now(datetime.timezone.utc), "Profile has expired")
    fingerprints = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
    require(certificate.upper() in fingerprints, "Signing certificate is absent from this profile")
    return uuid, {
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "manual",
        "teamID": team,
        "signingCertificate": certificate.upper(),
        "provisioningProfiles": {bundle: uuid},
        "manageAppVersionAndBuildNumber": False,
        "stripSwiftSymbols": True,
        "uploadSymbols": True,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("profile")
    parser.add_argument("output")
    parser.add_argument("--team", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--certificate", required=True)
    args = parser.parse_args()
    try:
        profile = plistlib.loads(Path(args.profile).read_bytes())
        uuid, options = export_options(profile, args.team, args.bundle, args.certificate)
        Path(args.output).write_bytes(plistlib.dumps(options))
    except (ValueError, OSError, plistlib.InvalidFileException, TypeError) as error:
        print(f"Invalid signing profile: {error}", file=sys.stderr)
        return 1
    print(uuid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
