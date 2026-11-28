"""Atomic checkpoint regressions without filesystem or model access."""
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch


class CheckpointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('renderer',Path(__file__).with_name('render-narration-reference.py'))
        cls.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.module)

    def test_transient_windows_sharing_failure_is_retried(self):
        with patch.object(Path,'open',return_value=io.StringIO()),patch.object(Path,'replace',side_effect=[PermissionError('locked'),None]) as replace,patch.object(self.module.time,'sleep'):
            self.module.dump(Path('index.json'),{'status':'generated'})
            self.assertEqual(replace.call_count,2)

    def test_permanent_failure_is_bounded_and_pending_file_is_retained(self):
        with patch.object(Path,'open',return_value=io.StringIO()),patch.object(Path,'replace',side_effect=PermissionError('locked')) as replace,patch.object(Path,'unlink') as unlink,patch.object(self.module.time,'sleep'):
            with self.assertRaises(PermissionError):self.module.dump(Path('index.json'),{'status':'generated'})
            self.assertLessEqual(replace.call_count,30)
            unlink.assert_not_called()


if __name__=='__main__':unittest.main()
