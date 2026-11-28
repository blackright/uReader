"""Allow official data names without allowing archive traversal or shell metacharacters."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('capture-french-quality.py'))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class FrontendPathTests(unittest.TestCase):
    def test_upstream_names_including_space(self):
        for path in ('voices/!v/Mr serious', 'lang/roa/fr', 'phontab', 'en_dict'):
            self.assertTrue(capture.valid_frontend_path(path), path)

    def test_traversal_absolute_and_command_text_rejected(self):
        for path in ('../private', '/absolute', 'a/../b', 'a//b', './a', 'a\\b',
                     'x;echo', '$(command)', 'x\nfile', 'C:/outside'):
            self.assertFalse(capture.valid_frontend_path(path), path)


if __name__ == '__main__':
    unittest.main()
