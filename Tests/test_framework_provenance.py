import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("provenance", ROOT / "scripts/framework-provenance.py")
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class FrameworkProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.framework = Path(self.temp.name) / "OpenVPNAdapter.framework"
        self.framework.mkdir()
        self.binary = self.framework / "OpenVPNAdapter"
        self.binary.write_bytes(b"built with patch")
        self.patch = Path(self.temp.name) / "aead.patch"
        self.patch.write_bytes(b"patch v1")
        self.connection_patch = Path(self.temp.name) / "connection-refcount.patch"
        self.connection_patch.write_bytes(b"connection patch v1")
        self.send_patch = Path(self.temp.name) / "send-queue.patch"
        self.send_patch.write_bytes(b"send queue patch v1")
        self.registry_patch = Path(self.temp.name) / "registry.patch"
        self.registry_patch.write_bytes(b"registry patch v1")
        self.archive = Path(self.temp.name) / "source/Lib/ios/arm64/ck-ovpn-plugin.a"
        self.archive.parent.mkdir(parents=True)
        self.archive.write_bytes(b"patched Go archive")
        self.receipt = provenance.receipt_path(self.framework)
        self.receipt.write_text(json.dumps(provenance.expected_receipt(
            self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)))

    def testMatchingBuildPasses(self):
        provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testReplacingBinaryWithPrebuiltFailsEvenWithStaleReceipt(self):
        self.binary.write_bytes(b"unpatched prebuilt")
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testChangingPatchRequiresRebuild(self):
        self.patch.write_bytes(b"patch v2")
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testChangingConnectionPatchRequiresRebuild(self):
        self.connection_patch.write_bytes(b"connection patch v2")
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testChangingSendPatchRequiresRebuild(self):
        self.send_patch.write_bytes(b"send queue patch v2")
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testChangingRegistryPatchRequiresRebuild(self):
        self.registry_patch.write_bytes(b"registry patch v2")
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testChangingGoArchiveRequiresRebuild(self):
        self.archive.write_bytes(b"upstream archive without registry fix")
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testBuild10ReceiptRequiresRebuild(self):
        data = json.loads(self.receipt.read_text())
        data["schema"] = 3
        del data["sendQueuePatchSHA256"]
        self.receipt.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testRecordRejectsUnappliedSendPatchWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", provenance.OPENVPN3_COMMIT + "\n", provenance.CLOAK_COMMIT + "\n"
        ]), mock.patch.object(provenance.subprocess, "run", side_effect=[
            None, None, subprocess.CalledProcessError(1, ["git", "apply"])
        ]):
            with self.assertRaises(subprocess.CalledProcessError):
                provenance.record(self.framework, source)
        self.assertFalse(self.receipt.exists())

    def testOldAEADOnlyReceiptRequiresRebuild(self):
        data = json.loads(self.receipt.read_text())
        data["schema"] = 1
        del data["connectionRefcountPatchSHA256"]
        self.receipt.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testMissingReceiptFails(self):
        self.receipt.unlink()
        with self.assertRaises(FileNotFoundError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testWrongSourceCommitFails(self):
        data = json.loads(self.receipt.read_text())
        data["openvpn3Commit"] = "wrong"
        self.receipt.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            provenance.verify(self.framework, self.patch, self.connection_patch, self.send_patch, self.registry_patch, self.archive)

    def testRecordRejectsWrongAdapterHeadWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", return_value="wrong\n"), \
                mock.patch.object(provenance.subprocess, "run") as apply_patch:
            with self.assertRaises(ValueError):
                provenance.record(self.framework, source)
            apply_patch.assert_not_called()
        self.assertFalse(self.receipt.exists())

    def testRecordRejectsWrongOpenVPN3HeadWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", "wrong\n"
        ]), mock.patch.object(provenance.subprocess, "run") as apply_patch:
            with self.assertRaises(ValueError):
                provenance.record(self.framework, source)
            apply_patch.assert_not_called()
        self.assertFalse(self.receipt.exists())

    def testRecordRejectsWrongCloakHeadWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", provenance.OPENVPN3_COMMIT + "\n", "wrong\n"
        ]), mock.patch.object(provenance.subprocess, "run") as apply_patch:
            with self.assertRaises(ValueError):
                provenance.record(self.framework, source)
            apply_patch.assert_not_called()
        self.assertFalse(self.receipt.exists())

    def testRecordRejectsUnappliedPatchWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", provenance.OPENVPN3_COMMIT + "\n", provenance.CLOAK_COMMIT + "\n"
        ]), mock.patch.object(provenance.subprocess, "run", side_effect=
                              subprocess.CalledProcessError(1, ["git", "apply"])):
            with self.assertRaises(subprocess.CalledProcessError):
                provenance.record(self.framework, source)
        self.assertFalse(self.receipt.exists())

    def testRecordRejectsUnappliedConnectionPatchWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", provenance.OPENVPN3_COMMIT + "\n", provenance.CLOAK_COMMIT + "\n"
        ]), mock.patch.object(provenance.subprocess, "run", side_effect=[
            None, subprocess.CalledProcessError(1, ["git", "apply"])
        ]):
            with self.assertRaises(subprocess.CalledProcessError):
                provenance.record(self.framework, source)
        self.assertFalse(self.receipt.exists())

    def testRecordOfPinnedPatchedSourceProducesVerifiableReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", provenance.OPENVPN3_COMMIT + "\n", provenance.CLOAK_COMMIT + "\n"
        ]) as read_head, mock.patch.object(provenance.subprocess, "run") as apply_patch:
            provenance.record(self.framework, source)
            self.assertEqual(read_head.call_args_list, [
                mock.call(["git", "-C", str(source), "rev-parse", "HEAD"], text=True),
                mock.call(["git", "-C", str(source / "Sources/OpenVPN3"), "rev-parse", "HEAD"], text=True),
                mock.call(["git", "-C", str(provenance.CLOAK_SOURCE), "rev-parse", "HEAD"], text=True),
            ])
            self.assertEqual(apply_patch.call_args_list, [
                mock.call(["git", "-C", str(source / "Sources/OpenVPN3"), "apply", "--reverse", "--check", str(patch)], check=True)
                for patch in (provenance.PATCH, provenance.CONNECTION_REFCOUNT_PATCH, provenance.SEND_QUEUE_PATCH)
            ] + [mock.call(["git", "-C", str(provenance.CLOAK_SOURCE), "apply", "--reverse", "--check", str(provenance.REGISTRY_PATCH)], check=True)])
        provenance.verify(self.framework, archive=self.archive)
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt["binarySHA256"], provenance.digest(self.binary))
        self.assertEqual(receipt["aeadPatchSHA256"], provenance.digest(provenance.PATCH))
        self.assertEqual(receipt["connectionRefcountPatchSHA256"], provenance.digest(provenance.CONNECTION_REFCOUNT_PATCH))
        self.assertEqual(receipt["sendQueuePatchSHA256"], provenance.digest(provenance.SEND_QUEUE_PATCH))
        self.assertEqual(receipt["cloakCommit"], provenance.CLOAK_COMMIT)
        self.assertEqual(receipt["cloakRegistryPatchSHA256"], provenance.digest(provenance.REGISTRY_PATCH))
        self.assertEqual(receipt["cloakArchiveSHA256"], provenance.digest(self.archive))

    def testRecordRejectsUnappliedRegistryPatchWithoutReceipt(self):
        self.receipt.unlink()
        source = Path(self.temp.name) / "source"
        with mock.patch.object(provenance.subprocess, "check_output", side_effect=[
            provenance.ADAPTER_COMMIT + "\n", provenance.OPENVPN3_COMMIT + "\n", provenance.CLOAK_COMMIT + "\n"
        ]), mock.patch.object(provenance.subprocess, "run", side_effect=[
            None, None, None, subprocess.CalledProcessError(1, ["git", "apply"])
        ]) as apply_patch:
            with self.assertRaises(subprocess.CalledProcessError):
                provenance.record(self.framework, source)
            self.assertEqual(apply_patch.call_args, mock.call([
                "git", "-C", str(provenance.CLOAK_SOURCE), "apply", "--reverse", "--check", str(provenance.REGISTRY_PATCH)
            ], check=True))
        self.assertFalse(self.receipt.exists())


if __name__ == "__main__":
    unittest.main()
