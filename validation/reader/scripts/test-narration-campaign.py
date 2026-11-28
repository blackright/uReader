"""Synthetic regression tests; no models, books or device required."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest
import tempfile
import json


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name+'.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tool = load('narration-campaign')
        cls.ratings = load('validate-narration-results')

    def fixture(self):
        rows = []
        for n in range(1, 21):
            text = 'École, l’amitié 😀.'
            rows.append({'id':f'P{n:02d}', 'sourceText':text,
                         'sourceSha256':hashlib.sha256(text.encode()).hexdigest()})
        corpus = {'corpusSha256':'a'*64, 'paragraphs':rows}
        prepared = [{'corpusId':p['id'], 'source':p['sourceText'], 'segments':[
            {'id':f'p-{chr(96+n)}-1', 'sourceText':p['sourceText'],
             'synthesisText':"École, l'amitié 😀.", 'sourceStart':0,
             'sourceEnd':len(p['sourceText'].encode('utf-16-le'))//2,
             'tokens':8, 'spans':[]}]} for n,p in enumerate(rows,1)]
        return corpus, prepared

    def test_twenty_unicode_paragraphs_and_bounded_batches(self):
        c,p = self.fixture()
        result = self.tool.plan_batches(c,p)
        self.assertEqual(sum(len(b['cases']) for b in result),20)
        self.assertTrue(all(len(b['cases'])<=8 for b in result))
        self.assertEqual(result[0]['cases'][0]['sourceText'],p[0]['source'])
        self.assertEqual(result[0]['cases'][0]['seed'],7201)

    def test_missing_or_reordered_paragraph_is_rejected(self):
        c,p = self.fixture()
        for bad in (p[:-1],p[::-1]):
            with self.assertRaises(ValueError):self.tool.plan_batches(c,bad)

    def test_changed_source_or_range_is_rejected(self):
        for field,value in [('sourceText','Other'),('sourceStart',1),('sourceEnd',1),('tokens',51)]:
            c,p=self.fixture();p[0]['segments'][0][field]=value
            with self.assertRaises(ValueError):self.tool.plan_batches(c,p)

    def test_hostile_and_duplicate_ids_are_rejected(self):
        for value in ('../escape-1','a/escape-1','p-b-1'):
            c,p=self.fixture();p[0]['segments'][0]['id']=value
            with self.assertRaises(ValueError):self.tool.plan_batches(c,p)

    def test_digest_and_take_bounds_are_checked(self):
        c,p=self.fixture();c['paragraphs'][0]['sourceSha256']='b'*64
        with self.assertRaises(ValueError):self.tool.plan_batches(c,p)
        c,p=self.fixture()
        with self.assertRaises(ValueError):self.tool.plan_batches(c,p,take=0)

    def test_transfer_preserves_unicode_values_and_hashes_exact_bytes(self):
        payload,digest=self.tool.transfer({'text':'École\r\n😀'})
        self.assertNotIn(b'\r\n',payload)
        self.assertEqual(hashlib.sha256(payload).hexdigest(),digest)
        import json
        self.assertEqual(json.loads(payload)['text'],'École\r\n😀')

    def test_null_ratings_remain_pending(self):
        row=self.ratings.blank('a'*64,'A','P01',1)
        result=self.ratings.validate({'corpusSha256':'a'*64,'ratings':[row]})
        self.assertEqual(result['accepted'],0)
        self.assertEqual(result['pending'],1)

    def test_boolean_score_and_duplicate_take_are_invalid(self):
        row=self.ratings.blank('a'*64,'A','P01',1)
        row['scores']['pronunciation']=True
        with self.assertRaises(ValueError):self.ratings.validate({'corpusSha256':'a'*64,'ratings':[row]})
        row=self.ratings.blank('a'*64,'A','P01',1)
        with self.assertRaises(ValueError):self.ratings.validate({'corpusSha256':'a'*64,'ratings':[row,row]})

    def test_low_dimension_or_unresolved_error_prevents_acceptance(self):
        row=self.ratings.blank('a'*64,'A','P01',1)
        row.update(evaluator='owner',date='2026-11-25',listened=True,
                   conditions={'device':'headphones','volume':'comfortable'},audioSha256='c'*64)
        row['scores']={k:5 for k in row['scores']}
        data={'corpusSha256':'a'*64,'ratings':[row]}
        self.assertEqual(self.ratings.validate(data)['accepted'],1)
        row['scores']['naturalness']=3
        self.assertEqual(self.ratings.validate(data)['rejected'],1)
        row['scores']['naturalness']=5
        row['errors']=[{'resolved':False,'description':'word omitted','category':'omission',
                        'expected':'École','severity':'major','startUtf16':0,'endUtf16':5}]
        self.assertEqual(self.ratings.validate(data)['rejected'],1)

    def test_full_candidate_requires_main_and_robustness_takes(self):
        self.assertEqual(len(self.ratings.expected('A')),30)
        row=self.ratings.blank('a'*64,'A','P01',1)
        result=self.ratings.validate({'corpusSha256':'a'*64,'ratings':[row]},candidate='A')
        self.assertEqual(result['missing'],29)
        self.assertFalse(result['candidateAccepted'])

    def test_listened_rating_requires_real_audio_identity(self):
        row=self.ratings.blank('a'*64,'A','P01',1)
        row.update(evaluator='owner',date='2026-11-25',listened=True,
                   conditions={'device':'headphones','volume':'comfortable'})
        row['scores']={k:5 for k in row['scores']}
        with self.assertRaises(ValueError):self.ratings.validate({'corpusSha256':'a'*64,'ratings':[row]})

    def test_expected_text_cannot_activate_markdown_resources(self):
        publisher=load('publish-narration-listening')
        source='École 😀\n```\n![tracking](https://example.invalid/image)'
        quoted=publisher.quoted_source(source)
        self.assertTrue(quoted.startswith('``````text\n'))
        self.assertIn(source,quoted)
        self.assertTrue(quoted.endswith('\n``````'))

    def test_error_cannot_be_resolved_without_localization(self):
        row=self.ratings.blank('a'*64,'A','P01',1)
        row['errors']=[{'resolved':True,'description':'fixed'}]
        with self.assertRaises(ValueError):self.ratings.validate({'corpusSha256':'a'*64,'ratings':[row]})

    def test_capture_resume_checks_restore_input_and_audio(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'native').mkdir()
            audio=b'RIFFsynthetic';(root/'native/p-a-1.wav').write_bytes(audio)
            report={'status':'captured_listening_pending','appRestored':True,'inputSha256':'a'*64}
            native={'inputSha256':'a'*64,'cases':[{'id':'p-a-1','wav':'p-a-1.wav','sha256':hashlib.sha256(audio).hexdigest()}]}
            (root/'run-report.json').write_text(json.dumps(report))
            (root/'native-report.json').write_text(json.dumps(native))
            self.assertEqual(len(self.tool.verify_capture(root,'a'*64)['cases']),1)
            with self.assertRaises(ValueError):self.tool.verify_capture(root,'b'*64)
            (root/'native/p-a-1.wav').write_bytes(b'changed')
            with self.assertRaises(ValueError):self.tool.verify_capture(root,'a'*64)


if __name__=='__main__':unittest.main()
