import base64
import hashlib
import json
import pathlib
import stat
import subprocess
import tempfile
import unittest


class UpdateSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="prism-signing-tests-")
        cls.addClassCleanup(cls.workspace.cleanup)
        cls.tool = pathlib.Path(cls.workspace.name) / "sign-update"
        source = pathlib.Path(__file__).with_name("sign-update.swift")
        if not source.is_file():
            raise AssertionError("Update signing tool must exist")
        subprocess.run(["/usr/bin/xcrun", "swiftc", str(source), "-o", str(cls.tool)], check=True, capture_output=True)

    def test_manifest_binds_exact_bytes_and_key_is_private(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            key = root / "keys" / "update.key"
            public = subprocess.check_output([str(self.tool), "generate-key", str(key)], text=True).strip()
            self.assertEqual(len(base64.b64decode(public, validate=True)), 32)
            self.assertEqual(stat.S_IMODE(key.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(key.parent.stat().st_mode), 0o700)
            dmg = root / "Prism-1.14.1-universal-test.dmg"
            dmg.write_bytes(b"Synthetic update archive fixture\n")
            out = root / "release"
            subprocess.run([str(self.tool), "sign", str(key), str(dmg), "1.14.1", str(out), "15.0"], check=True, capture_output=True)
            manifest = json.loads((out / "update-manifest.json").read_bytes())
            self.assertEqual(manifest, {
                "version": "1.14.1", "fileName": dmg.name,
                "sha256": hashlib.sha256(dmg.read_bytes()).hexdigest(),
                "size": dmg.stat().st_size, "bundleIdentifier": "com.prism.app",
                "minimumSystemVersion": "15.0",
            })
            self.assertEqual(len(base64.b64decode((out / "update-manifest.sig").read_text().strip(), validate=True)), 64)
            verified = subprocess.run([str(self.tool), "verify", public, str(out / "update-manifest.json"), str(out / "update-manifest.sig")], capture_output=True)
            self.assertEqual(verified.returncode, 0)
            (out / "update-manifest.json").write_bytes(b'{"version":"99.0.0"}')
            tampered = subprocess.run([str(self.tool), "verify", public, str(out / "update-manifest.json"), str(out / "update-manifest.sig")], capture_output=True)
            self.assertNotEqual(tampered.returncode, 0)

    def test_key_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            key = pathlib.Path(folder) / "keys" / "update.key"
            subprocess.run([str(self.tool), "generate-key", str(key)], check=True, capture_output=True)
            before = key.read_bytes()
            second = subprocess.run([str(self.tool), "generate-key", str(key)], capture_output=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(key.read_bytes(), before)

    def test_invalid_asset_name_and_version_are_not_signed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            key = root / "keys" / "update.key"
            subprocess.run([str(self.tool), "generate-key", str(key)], check=True, capture_output=True)
            archive = root / "wrong.dmg"
            archive.write_bytes(b"fixture")
            result = subprocess.run([str(self.tool), "sign", str(key), str(archive), "1.14.1", str(root / "release"), "15.0"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / "release" / "update-manifest.sig").exists())


if __name__ == "__main__":
    unittest.main()
