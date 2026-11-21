"""Score independent video annotations for a verified Android WAV set, never cue predictions."""
import argparse,hashlib,importlib.util,json,math,re,wave
from pathlib import Path
spec=importlib.util.spec_from_file_location('word_score',Path(__file__).with_name('score-word-timing.py'))
word_score=importlib.util.module_from_spec(spec);spec.loader.exec_module(word_score)
def digest(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def verify_audio_set(manifest,directory):
 root=directory.resolve();seen=set();ids=set();entries=manifest['occurrences']
 if not 0<len(entries)<=256:raise ValueError('Occurrence budget')
 for item in entries:
  if item['caseId'] in ids:raise ValueError('Duplicate occurrence')
  ids.add(item['caseId']);relative=item['wav']
  if not re.fullmatch(r'[a-f0-9]{64}/generation-[a-f0-9-]+\.wav',relative):raise ValueError('Unsafe WAV path')
  path=(root/relative).resolve()
  if not path.is_relative_to(root) or path.stat().st_size>960044:raise ValueError('WAV bounds')
  if digest(path)!=item['wavSha256']:raise ValueError('WAV mismatch')
  with wave.open(str(path),'rb') as wav:
   if (wav.getnchannels(),wav.getsampwidth(),wav.getframerate(),wav.getnframes())!=(1,2,24000,item['samples']):raise ValueError('WAV protocol')
  seen.add(relative)
 return {'playbackOccurrences':len(entries),'uniqueWavsVerified':len(seen)}
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['expected','observed','audio-manifest','audio-directory','capture','output']:p.add_argument('--'+name,type=Path,required=True)
 args=p.parse_args()
 if args.output.exists():p.error('Fresh report required')
 for f in [args.expected,args.observed,args.audio_manifest]:
  if f.stat().st_size>10485760:p.error('Metadata limit')
 expected=json.loads(args.expected.read_text(encoding='utf-8'));observed=json.loads(args.observed.read_text(encoding='utf-8'))
 manifest=json.loads(args.audio_manifest.read_text(encoding='utf-8'))
 audio=verify_audio_set(manifest,args.audio_directory);metrics=word_score.score(expected,observed['units'])
 uncertainty=observed.get('uncertaintyMs')
 evidence=(expected.get('annotationsFrozen') is True and expected.get('spokenWordCountVerified') is True
  and expected.get('platform')=='android' and expected.get('inferenceOnDevice') is True
  and expected.get('audioManifestSha256')==digest(args.audio_manifest)==observed.get('audioManifestSha256')
  and observed.get('captureSha256')==digest(args.capture) and observed.get('annotationMethod')=='manual_audiovisual'
  and isinstance(uncertainty,(int,float)) and not isinstance(uncertainty,bool) and math.isfinite(uncertainty) and 0<=uncertainty<=50
  and bool(observed.get('annotator')) and bool(observed.get('calibration')))
 verdict='not_evaluated' if not evidence else ('passed' if metrics['spokenWords']>=500 and metrics['timingPassed'] and metrics['allExpansionsPassed'] else 'failed')
 report={'sc003':verdict,'g1':'not_evaluated','audioSet':audio,'metrics':metrics,'evidenceComplete':evidence,
  'notice':'Numeric timing score only. G1 also requires reviewed parity, cost and cancellation.'}
 args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':main()
