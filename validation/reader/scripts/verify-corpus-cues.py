"""Verify corpus cue export identities and report gaps without asserting audible alignment."""
import argparse,hashlib,json
from pathlib import Path

def verify(data,source,result):
 expected={c['id']:c for c in source['occurrences']}
 audio={item['id']:next(r for r in item['runs'] if r['kind']=='candidate') for item in result['results']}
 if data['corpusSha256']!=source['corpusSha256'] or data['audioPlaybackRequested'] is not False:raise ValueError('Corpus identity or silence mismatch')
 cases=data['cases']
 if data['occurrencesExpected']!=len(expected) or data['occurrencesDecoded']!=len(cases) or len(cases)!=len(expected):raise ValueError('Incomplete occurrence export')
 seen=set();missing=0;unavailable=0;cue_count=0
 for item in cases:
  if item['id'] in seen or item['id'] not in expected:raise ValueError('Duplicate or unknown case')
  seen.add(item['id']);case=expected[item['id']]
  for key in ['sourceSha256','preparedSha256','passageId']:
   if item[key]!=case[key]:raise ValueError('Source identity mismatch')
  run=audio[case['uniqueId']]
  if item['audioSha256']!=run['wavSha256']:raise ValueError('Audio identity mismatch')
  start=case['sourceOffset'];end=start+len(case['source'].encode('utf-16-le'))//2;last=0
  for cue in item['cues']:
   if not start<=cue['sourceStart']<cue['sourceEnd']<=end or not last<=cue['startSample']<cue['endSample']:raise ValueError('Invalid canonical cue')
   if cue['endSample']>run['samples']:raise ValueError('Cue outside PCM')
   last=cue['endSample'];cue_count+=1
  missing+=len(item['missingSourceUnits']);unavailable+=item['alignmentAvailable'] is not True
 return {'status':'passed','occurrencesVerified':len(seen),'cues':cue_count,'missingSourceUnits':missing,'unavailableOccurrences':unavailable,'audioPlaybackRequested':False,'g1':'not_evaluated','notice':'Computational structure and identities only; no audiovisual accuracy claim.'}

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['input','cues','result','output']:p.add_argument('--'+name,type=Path,required=True)
 args=p.parse_args()
 if args.output.exists():p.error('Fresh report required')
 source=json.loads(args.input.read_text(encoding='utf-8'));data=json.loads(args.cues.read_text(encoding='utf-8'))
 if data['inputSha256']!=hashlib.sha256(args.input.read_bytes()).hexdigest():raise ValueError('Input identity mismatch')
 result=json.loads(args.result.read_text(encoding='utf-8'))
 report=verify(data,source,result);args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':main()
