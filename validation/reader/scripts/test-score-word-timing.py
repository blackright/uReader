import importlib.util, unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('scorer',Path(__file__).with_name('score-word-timing.py'))
scorer=importlib.util.module_from_spec(spec);spec.loader.exec_module(scorer)
class ScoreTests(unittest.TestCase):
 def fixture(self):
  return {'units':[{'id':str(i),'passageId':'p','sourceStart':i*3,'sourceEnd':i*3+2} for i in range(20)],'spokenWords':[{'id':str(i),'unitId':str(i)} for i in range(20)]}
 def observations(self):
  return [{'unitId':str(i),'passageId':'p','sourceStart':i*3,'sourceEnd':i*3+2,'highlightStartMs':i*1000+100,'wordStarts':[{'wordId':str(i),'audibleStartMs':i*1000}]} for i in range(20)]
 def test_missing_stays_in_denominator(self):
  result=scorer.score(self.fixture(),self.observations()[:-2]);self.assertEqual((result['N'],result['K'],result['missingTimings']),(20,18,2));self.assertFalse(result['timingPassed'])
 def test_wrong_source_does_not_count(self):
  observed=self.observations();observed[0]['sourceEnd']=100
  result=scorer.score(self.fixture(),observed);self.assertEqual(result['K'],19)
 def test_expansion_requires_each_audible_word_active(self):
  expected=self.fixture();expected['spokenWords'].append({'id':'expanded','unitId':'0'})
  observed=self.observations();observed[0]['wordStarts'].append({'wordId':'expanded','audibleStartMs':500,'activeSourceStart':3,'activeSourceEnd':5})
  result=scorer.score(expected,observed);self.assertEqual(result['K'],20);self.assertFalse(result['allExpansionsPassed'])
 def test_nan_is_missing_not_success(self):
  observed=self.observations();observed[0]['highlightStartMs']=float('nan')
  self.assertEqual(scorer.score(self.fixture(),observed)['missingTimings'],1)
if __name__=='__main__':unittest.main()
