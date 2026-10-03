#!/usr/bin/env python3
"""Decode a base64 GitLab File variable to a private binary signing input."""
import base64
import binascii
import os
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 3:
        print("Usage: decode-file.py encoded-file binary-output", file=sys.stderr)
        return 1
    try:
        encoded = b"".join(Path(sys.argv[1]).read_bytes().split())
        decoded = base64.b64decode(encoded, validate=True)
        if not decoded:
            raise ValueError("Empty signing file")
        with os.fdopen(os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as output:
            output.write(decoded)
    except (OSError, ValueError, binascii.Error):
        print("Cannot decode signing File variable; check its base64 encoding and output path.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
