"""French diagnostic frontend regressions; synthetic text, no runtime dependency."""
import importlib.util
from pathlib import Path
import unittest


class FrenchPreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('french',Path(__file__).with_name('kokoro-french-preparation.py'))
        cls.f=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.f)

    def test_english_switch_is_detected_even_with_tie_markers(self):
        for flags in ('(en)word(fr)','(^e^n)word(^f^r)'):
            with self.assertRaises(ValueError):self.f.phonemize('mot inconnu',lambda _:flags)

    def test_known_words_use_explicit_french_lexicon(self):
        text='Authentiques, enthousiastes, gentleman et rocking-chairs.'
        result=self.f.phonemize(text,lambda s:s)
        self.assertEqual(len(result['overrides']),4)
        self.assertIn('otɑ̃tˈik',result['phonemes'])
        self.assertNotIn('authentiques',result['phonemes'].lower())
        self.assertEqual(result['source'],text)

    def test_word_substrings_are_not_replaced(self):
        self.assertEqual(self.f.phonemize('gentlemanlike',lambda s:s)['overrides'],[])

    def test_liaison_before_vowel_exception(self):
        result=self.f.phonemize('des enthousiastes',lambda _: 'de')
        self.assertIn('dez',result['phonemes'])
        result=self.f.phonemize('seront authentiques',lambda _: 'səʁɔ̃')
        self.assertIn('səʁɔ̃t',result['phonemes'])
        result=self.f.phonemize('des, enthousiastes',lambda _: 'de,')
        self.assertNotIn('dez',result['phonemes'])

    def test_utf16_ranges_with_astral_character(self):
        result=self.f.phonemize('😀 Nelly',lambda s:s)
        self.assertEqual(result['overrides'][0]['startUtf16'],3)
        self.assertEqual(result['overrides'][0]['endUtf16'],8)

    def test_chunking_preserves_source_and_comma_without_period(self):
        text='Voici une phrase, elle continue, puis se termine ! Autre phrase.'
        chunks=self.f.chunks(text,lambda s:{'phonemes':s,'overrides':[]},limit=30)
        self.assertEqual(''.join(c['source'] for c in chunks),text)
        self.assertTrue(any(c['source'].rstrip().endswith(',') for c in chunks[:-1]))
        self.assertTrue(all(len(c['phonemes'])<=30 for c in chunks))
        self.assertEqual(chunks[-1]['endUtf16'],len(text))

    def test_no_pocket_token_cap_and_no_forced_capitalization(self):
        text='mot '*80+'fin.'
        chunks=self.f.chunks(text,lambda s:{'phonemes':'a'*40,'overrides':[]},limit=510)
        self.assertEqual(len(chunks),1)
        self.assertEqual(chunks[0]['source'],text)

    def test_unbreakable_oversize_word_fails(self):
        with self.assertRaises(ValueError):self.f.chunks('abcdefgh',lambda s:{'phonemes':s,'overrides':[]},limit=3)

    def test_dictionary_plural_forms_are_explicit(self):
        for text in ('authentique','authentiques','enthousiaste','enthousiastes','fervent','fervents'):
            result=self.f.phonemize(text,lambda s:s)
            self.assertEqual(len(result['overrides']),1)

    def test_nonbreaking_spaces_normalize_only_in_model_phonemes(self):
        source='École\u00a0! Bonjour\u202f?'
        row=self.f.phonemize(source,lambda s:s)
        self.assertEqual(row['source'],source)
        self.assertEqual(row['phonemes'],'École ! Bonjour ?')


if __name__=='__main__':unittest.main()
