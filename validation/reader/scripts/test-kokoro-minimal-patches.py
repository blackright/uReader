"""Minimal phoneme edits must leave every unrelated baseline input unchanged."""
import importlib.util
from pathlib import Path
import unittest


class MinimalPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('patches',Path(__file__).with_name('kokoro-minimal-patches.py'))
        cls.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.m)

    def test_untargeted_segment_is_identical(self):
        phones='sa vˈwa, sɛ lə ʁˈɛst.'
        self.assertEqual(self.m.patch('Sa voix, le reste.',phones),{'phonemes':phones,'changes':[]})

    def test_only_the_reported_word_changes(self):
        old='lˈe mˈøbl səʁˈɔ̃ ɔːθəntˈiːks.'
        new=self.m.patch('Les meubles seront authentiques.',old)
        self.assertEqual(new['phonemes'],'lˈe mˈøbl səʁˈɔ̃ otɑ̃tˈik.')
        self.assertEqual(len(new['changes']),1)

    def test_mismatch_fails_without_guessing(self):
        with self.assertRaises(ValueError):self.m.patch('authentiques','different phones')

    def test_subword_does_not_trigger_override(self):
        old='ʒɑ̃tlmˈɑ̃'
        self.assertEqual(self.m.patch('agentlemanlike',old)['phonemes'],old)

    def test_each_changed_range_explains_exact_reconstruction(self):
        old='ʒɑ̃tlmˈɑ̃ et ɔːθəntˈiːks.'
        result=self.m.patch('gentleman et authentiques.',old)
        reconstructed=old
        for change in reversed(result['changes']):
            reconstructed=reconstructed[:change['baselineStart']]+change['replacement']+reconstructed[change['baselineEnd']:]
        self.assertEqual(reconstructed,result['phonemes'])

    def test_all_four_reported_words(self):
        for word,old,new in self.m.PATCHES:
            self.assertEqual(self.m.patch(word,old)['phonemes'],new)

    def test_nelly_has_no_speculative_phoneme_replacement(self):
        original='mˈis nˈɛli,'
        self.assertEqual(self.m.patch('miss Nelly,',original)['changes'],[])


if __name__=='__main__':unittest.main()
