import importlib.util,copy,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('prepare',Path(__file__).with_name('prepare-alignment-corpus.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class CorpusTests(unittest.TestCase):
 def corpus(self):
  text='Bonjour.';digest=m.text_sha(text)
  return {'cases':[{'id':'p0-s0','passageId':'p0','source':text,'sourceOffset':0,'prepared':text,'sourceSha256':digest,'preparedSha256':digest,'unitIds':['p0-0-7'],'mapping':[]},{'id':'p1-s0','passageId':'p1','source':text,'sourceOffset':0,'prepared':text,'sourceSha256':digest,'preparedSha256':digest,'unitIds':['p1-0-7'],'mapping':[]}],'units':[{'id':'p0-0-7'},{'id':'p1-0-7'}],'spokenWords':[]}
 def test_dedup_keeps_every_occurrence_and_source_identity(self):
  result=m.build(self.corpus(),lambda text:([1],[(0,len(text))]))
  self.assertEqual(len(result['uniqueCases']),1);self.assertEqual(len(result['occurrences']),2)
  self.assertNotEqual(result['occurrences'][0]['passageId'],result['occurrences'][1]['passageId'])
  self.assertFalse(result['annotationsFrozen']);self.assertEqual(result['g1'],'not_evaluated')
 def test_foreign_hash_and_path_ids_are_rejected(self):
  corpus=self.corpus();corpus['cases'][0]['preparedSha256']='a'*64
  with self.assertRaises(ValueError):m.build(corpus,lambda text:([1],[(0,1)]))
  corpus=self.corpus();corpus['cases'][0]['id']='../escape'
  with self.assertRaises(ValueError):m.build(corpus,lambda text:([1],[(0,1)]))
 def test_token_bounds_and_duplicates_rejected(self):
  with self.assertRaises(ValueError):m.build(self.corpus(),lambda text:([1]*51,[(0,1)]*51))
  corpus=self.corpus();corpus['cases'][1]['id']='p0-s0'
  with self.assertRaises(ValueError):m.build(corpus,lambda text:([1],[(0,1)]))
if __name__=='__main__':unittest.main()
