#!/usr/bin/env python3
"""Bind a locally built framework to the pinned sources and transport patches.

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
CLOAK_COMMIT = "884ac4fa0d4a8e014e18ca1dc4a40b18bc9e4291"
NATIVE_PATCH = ROOT / "patches/openvpn3-cloak-async-io.patch"
CLOAK_PATCH = ROOT / "patches/cloak-connection-lifetime.patch"
PATCH = ROOT / "patches/openvpn3-aead-auth-tag.patch"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def receipt_path(framework):
    return framework.with_suffix(".build.json")


def expected_receipt(framework, patch=PATCH):
    return {
        "schema": 2,
        "cloakCommit": CLOAK_COMMIT,
        "goToolchain": "go1.22.2",
        "nativePatchSHA256": digest(NATIVE_PATCH),
        "cloakPatchSHA256": digest(CLOAK_PATCH),
        "adapterCommit": ADAPTER_COMMIT,
        "openvpn3Commit": OPENVPN3_COMMIT,
        "aeadPatchSHA256": digest(patch),
        "binarySHA256": digest(framework / "OpenVPNAdapter"),
    }


def verify(framework, patch=PATCH):
    actual = json.loads(receipt_path(framework).read_text())
    expected = expected_receipt(framework, patch)
    if actual != expected:
        raise ValueError("бинарник, исходники или транспортные патчи не соответствуют квитанции сборки")


def record(framework, source):
    # Invoked only after a successful source build, never by the verifier.
    for repo, expected in [(source, ADAPTER_COMMIT), (source / "Sources/OpenVPN3", OPENVPN3_COMMIT)]:
        actual = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
        if actual != expected:
            raise ValueError("неожиданный коммит исходников")
    subprocess.run(["git", "-C", str(source / "Sources/OpenVPN3"), "apply", "--reverse", "--check", str(PATCH)], check=True)
    subprocess.run(["git", "-C", str(source / "Sources/OpenVPN3"), "apply", "--reverse", "--check", str(NATIVE_PATCH)], check=True)
    cloak = source.parent / "Cloak-src"
    if subprocess.check_output(["git", "-C", str(cloak), "rev-parse", "HEAD"], text=True).strip() != CLOAK_COMMIT:
        raise ValueError("неожиданный коммит Cloak")
    subprocess.run(["git", "-C", str(cloak), "apply", "--reverse", "--check", str(CLOAK_PATCH)], check=True)
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
    print("PASS происхождение фреймворка: бинарник связан с исходниками и текущими транспортными патчами")
    return 0


if __name__ == "__main__":
    sys.exit(main())
