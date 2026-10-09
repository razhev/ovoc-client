#!/usr/bin/env python3
"""Bind a locally built framework to the pinned source and required patches.

This is a build consistency check, not a signature against a malicious local
builder. The receipt lives beside the framework and applies before codesigning.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ADAPTER_COMMIT = "8bb3da50ae2ad07c76a815bc670e9e70e0e3e3ad"
OPENVPN3_COMMIT = "e901077a05a5e3d018260d0955acb1a21e05578d"
PATCH = ROOT / "patches/openvpn3-aead-auth-tag.patch"
CONNECTION_REFCOUNT_PATCH = ROOT / "patches/openvpn3-cloak-connection-refcount.patch"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def receipt_path(framework):
    return framework.with_suffix(".build.json")


def expected_receipt(framework, patch=PATCH, connection_patch=CONNECTION_REFCOUNT_PATCH):
    return {
        "schema": 3,
        "adapterCommit": ADAPTER_COMMIT,
        "openvpn3Commit": OPENVPN3_COMMIT,
        "aeadPatchSHA256": digest(patch),
        "connectionRefcountPatchSHA256": digest(connection_patch),
        "binarySHA256": digest(framework / "OpenVPNAdapter"),
    }


def verify(framework, patch=PATCH, connection_patch=CONNECTION_REFCOUNT_PATCH):
    actual = json.loads(receipt_path(framework).read_text())
    expected = expected_receipt(framework, patch, connection_patch)
    if actual != expected:
        raise ValueError("бинарник, исходники или патчи не соответствуют квитанции сборки")


def record(framework, source):
    # Invoked only after a successful source build, never by the verifier.
    for repo, expected in [(source, ADAPTER_COMMIT), (source / "Sources/OpenVPN3", OPENVPN3_COMMIT)]:
        actual = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
        if actual != expected:
            raise ValueError("неожиданный коммит исходников")
    for patch in (PATCH, CONNECTION_REFCOUNT_PATCH):
        subprocess.run(["git", "-C", str(source / "Sources/OpenVPN3"), "apply", "--reverse", "--check", str(patch)], check=True)
    receipt_path(framework).write_text(json.dumps(expected_receipt(framework), indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["record", "verify"])
    parser.add_argument("--framework", type=Path, default=ROOT / "Frameworks/OpenVPNAdapter.framework")
    parser.add_argument("--source", type=Path, default=ROOT / "build/OpenVPNAdapter-src")
    args = parser.parse_args()
    try:
        if args.command == "record":
            record(args.framework, args.source)
        else:
            verify(args.framework)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL происхождение фреймворка: {error}. Выполните make framework.")
        return 1
    print("PASS происхождение фреймворка: бинарник связан с исходниками и текущими патчами AEAD и Connection refcount")
    return 0


if __name__ == "__main__":
    sys.exit(main())
