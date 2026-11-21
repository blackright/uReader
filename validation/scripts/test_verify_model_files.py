import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "verify_model_files", Path(__file__).with_name("verify-model-files.py"))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class VerifyFilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.entry = {"relativePath": "voices/test.f16", "byteSize": 3,
                      "sha256": hashlib.sha256(b"abc").hexdigest()}
        (self.root / "voices").mkdir()

    def test_valid_file_is_unchanged(self):
        path = self.root / "voices/test.f16"
        path.write_bytes(b"abc")
        self.assertEqual(verifier.verify(self.root, [self.entry]), [])
        self.assertEqual(path.read_bytes(), b"abc")

    def test_missing_file(self):
        self.assertIn("absent", verifier.verify(self.root, [self.entry])[0])

    def test_truncated_file(self):
        (self.root / "voices/test.f16").write_bytes(b"ab")
        self.assertIn("taille", verifier.verify(self.root, [self.entry])[0])

    def test_same_size_corruption(self):
        (self.root / "voices/test.f16").write_bytes(b"xyz")
        self.assertIn("SHA-256", verifier.verify(self.root, [self.entry])[0])

    def test_unsafe_and_duplicate_entries(self):
        for path in ["../test", "/test", "C:/test", "voices\\test", "voices/./test"]:
            with self.assertRaises(ValueError):
                verifier.verify(self.root, [{**self.entry, "relativePath": path}])
        with self.assertRaises(ValueError):
            verifier.verify(self.root, [self.entry, self.entry])


if __name__ == "__main__":
    unittest.main()
