import importlib.util,hashlib,json,tempfile,unittest,wave
from pathlib import Path
spec=importlib.util.spec_from_file_location('scorer',Path(__file__).with_name('score-corpus-word-timing.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class AudioManifestTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1]/"private");self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
  self.relative='a'*64+'/generation-1234.wav';p=self.root/self.relative;p.parent.mkdir()
  with wave.open(str(p),'wb') as w:w.setparams((1,2,24000,0,'NONE','not compressed'));w.writeframes(b'\x00\x00'*24)
  self.item={'caseId':'p0-s0','wav':self.relative,'wavSha256':hashlib.sha256(p.read_bytes()).hexdigest(),'samples':24}
 def test_repeated_audio_keeps_separate_occurrences(self):
  other=dict(self.item,caseId='p1-s0');r=m.verify_audio_set({'occurrences':[self.item,other]},self.root)
  self.assertEqual(r,{'playbackOccurrences':2,'uniqueWavsVerified':1})
 def test_duplicate_and_unsafe_paths_rejected(self):
  for entries in [[self.item,self.item],[dict(self.item,wav='../outside.wav')]]:
   with self.assertRaises(ValueError):m.verify_audio_set({'occurrences':entries},self.root)
 def test_hash_and_sample_mismatch_rejected(self):
  for item in [dict(self.item,wavSha256='b'*64),dict(self.item,samples=25)]:
   with self.assertRaises(ValueError):m.verify_audio_set({'occurrences':[item]},self.root)
if __name__=='__main__':unittest.main()
