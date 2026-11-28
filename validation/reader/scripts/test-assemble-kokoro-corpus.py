"""Full-corpus assembly must never select stale or unapproved phoneme inputs."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest


def load(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


class AssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tool=load('assemble-kokoro-corpus');cls.patches=load('kokoro-minimal-patches')

    def fixture(self):
        plan={'corpusSha256':'a'*64,'paragraphs':[]}
        baseline={'corpusSha256':'a'*64,'status':'generated_listening_pending','parameters':{'speed':1},'versions':{'kokoro':'0.9.4'},'segments':[],'paragraphs':[]}
        for n in range(1,21):
            pid=f'P{n:02d}';sid=f'p-{chr(96+n)}-1';text='authentiques.' if n==11 else 'École.'
            digest=hashlib.sha256(text.encode()).hexdigest()
            plan['paragraphs'].append({'corpusId':pid,'source':text,'segments':[{'id':sid,'sourceText':text,'synthesisText':text,'sourceStart':0,'sourceEnd':len(text)}]})
            baseline['segments'].append({'id':sid,'paragraphId':pid,'sourceTextSha256':digest,'synthesisTextSha256':digest,'phonemes':'ɔːθəntˈiːks.' if n==11 else 'ekɔl.','seed':7100+100*n+1,'status':'generated','sha256':'b'*64})
            baseline['paragraphs'].append({'paragraphId':pid})
        old=baseline['segments'][10]
        corrected={k:copy.deepcopy(baseline[k]) for k in ('corpusSha256','status','parameters','versions')}
        corrected['segments']=[{**old,'phonemes':'otɑ̃tˈik.','baselineStyleIndex':len(old['phonemes'])-1,'sha256':'c'*64,'sourceStart':0,'sourceEnd':len('authentiques.')}]
        corrected['paragraphs']=[{'paragraphId':'P11'}]
        return plan,baseline,corrected

    def test_twenty_paragraphs_select_only_targeted_correction(self):
        p,b,c=self.fixture();rows=self.tool.select_inputs(p,b,c,self.patches.patch)
        self.assertEqual(len(rows),20)
        self.assertEqual(sum(s['origin']=='corrected' for row in rows for s in row['segments']),1)
        self.assertEqual(rows[4]['segments'][0]['origin'],'baseline')

    def test_missing_correction_refuses_to_fall_back(self):
        p,b,c=self.fixture();c['segments']=[]
        with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)

    def test_style_seed_phonemes_or_runtime_change_is_rejected(self):
        for key,value in [('seed',0),('baselineStyleIndex',0),('phonemes','wrong')]:
            p,b,c=self.fixture();c['segments'][0][key]=value
            with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)
        p,b,c=self.fixture();c['versions']['kokoro']='other'
        with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)

    def test_changed_prompt_source_or_source_range_is_rejected(self):
        for key,value in [('sourceText','other'),('synthesisText','other'),('sourceStart',1)]:
            p,b,c=self.fixture();p['paragraphs'][0]['segments'][0][key]=value
            with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)

    def test_reordered_missing_or_duplicate_items_are_rejected(self):
        p,b,c=self.fixture();p['paragraphs'].reverse()
        with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)
        p,b,c=self.fixture();b['segments'].append(b['segments'][0])
        with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)

    def test_incomplete_correction_report_is_rejected(self):
        p,b,c=self.fixture();c['status']='generating'
        with self.assertRaises(ValueError):self.tool.select_inputs(p,b,c,self.patches.patch)


if __name__=='__main__':unittest.main()
