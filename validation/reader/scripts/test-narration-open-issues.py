"""Known unresolved listening defects must survive an otherwise complete grid."""
import importlib.util
from pathlib import Path
import unittest


class OpenIssueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('ratings',Path(__file__).with_name('validate-narration-results.py'))
        cls.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.m)

    def complete(self):
        rows=[]
        for candidate,pid,take in sorted(self.m.expected('F')):
            row=self.m.blank('a'*64,candidate,pid,take)
            row.update(listened=True,evaluator='owner',date='2026-11-25',
                       audioSha256='b'*64,conditions={'device':'headphones','volume':'unchanged'})
            row['scores']={k:5 for k in row['scores']};rows.append(row)
        return {'corpusSha256':'a'*64,'ownerAcceptedCandidate':'F','ratings':rows,
                'openIssues':[{'candidateId':'F','status':'open','description':'Reported punctuation defect'}]}

    def test_complete_grid_cannot_hide_a_known_open_defect(self):
        result=self.m.validate(self.complete(),'F')
        self.assertEqual(result['accepted'],30)
        self.assertFalse(result['candidateAccepted'])

    def test_resolution_requires_recorded_evidence(self):
        data=self.complete();data['openIssues'][0]['status']='resolved'
        with self.assertRaises(ValueError):self.m.validate(data,'F')
        data['openIssues'][0]['resolution']='Owner explicitly confirmed the referenced corrected audio.'
        self.assertTrue(self.m.validate(data,'F')['candidateAccepted'])


if __name__=='__main__':unittest.main()
