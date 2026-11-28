"""Protect against dropped phonemes and context overflow at the export boundary."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('exporter', Path(__file__).with_name('export-kokoro-onnx.py'))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class ExportInputTests(unittest.TestCase):
    def test_both_boundaries_and_order_preserved(self):
        self.assertEqual(exporter.token_ids('ab a', {'a': 1, 'b': 2, ' ': 3}), [0, 1, 2, 3, 1, 0])

    def test_unknown_phonemes_not_silently_dropped(self):
        with self.assertRaises(ValueError):
            exporter.token_ids('ax', {'a': 1})

    def test_context_limit_includes_boundary_tokens(self):
        self.assertEqual(len(exporter.token_ids('a' * 510, {'a': 1})), 512)
        with self.assertRaises(ValueError):
            exporter.token_ids('a' * 511, {'a': 1})

    def test_empty_input_rejected(self):
        with self.assertRaises(ValueError):
            exporter.token_ids('', {})


if __name__ == '__main__':
    unittest.main()
