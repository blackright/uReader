"""Protect the exact preregistered paragraph/seed schedule for independent takes."""
import importlib.util
from pathlib import Path
import unittest


class ScheduleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('renderer',Path(__file__).with_name('render-kokoro-minimal.py'))
        cls.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.m)

    def plan(self):return {'paragraphs':[{'corpusId':f'P{i:02d}'} for i in range(1,21)]}

    def test_two_takes_cover_exactly_the_five_prescribed_paragraphs(self):
        rows=[r for take in (2,3) for r in self.m.take_schedule(self.plan(),take)]
        self.assertEqual(len(rows),10)
        self.assertEqual([r['paragraphId'] for r in rows[:5]],['P01','P05','P10','P15','P20'])
        self.assertEqual(len({(r['paragraphId'],r['takeNumber']) for r in rows}),10)

    def test_seeds_follow_protocol_and_differ_from_main_take(self):
        for take in (2,3):
            for row in self.m.take_schedule(self.plan(),take):
                n=int(row['paragraphId'][1:])
                self.assertEqual(row['seed'],7100+100*n+take)
                self.assertNotEqual(row['seed'],7100+100*n+1)

    def test_existing_minimal_diagnostic_selection_is_preserved(self):
        self.assertEqual([r['paragraphId'] for r in self.m.take_schedule(self.plan(),1)],['P05','P11','P16','P20'])

    def test_reordered_incomplete_duplicate_or_invalid_take_is_refused(self):
        for take in (0,4,True):
            with self.assertRaises(ValueError):self.m.take_schedule(self.plan(),take)
        for rows in (self.plan()['paragraphs'][:-1],self.plan()['paragraphs'][::-1],[{'corpusId':'P01'}]*20):
            with self.assertRaises(ValueError):self.m.take_schedule({'paragraphs':rows},2)


if __name__=='__main__':unittest.main()
