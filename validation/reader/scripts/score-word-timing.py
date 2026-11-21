"""Score frozen source units against independent audiovisual annotations, never cue predictions."""
import argparse, hashlib, json, math
from pathlib import Path

def score(expected, observations):
    units=expected['units'];words=expected['spokenWords']
    if not 0<len(units)<=10000 or not 0<len(words)<=50000: raise ValueError('Unbounded corpus')
    ids={u['id'] for u in units}; word_ids={w['id'] for w in words}
    if len(ids)!=len(units) or len(word_ids)!=len(words): raise ValueError('Duplicate corpus IDs')
    if any(w['unitId'] not in ids for w in words): raise ValueError('Foreign word')
    observed={o['unitId']:o for o in observations}
    if len(observed)!=len(observations) or not set(observed)<=ids: raise ValueError('Duplicate or foreign observation')
    errors=[];correct=0;expansions=0;expansions_ok=0;missing=0;wrong=0
    def finite(value): return isinstance(value,(float,int)) and not isinstance(value,bool) and math.isfinite(value) and 0<=value<=86400000
    for unit in units:
        linked=[w['id'] for w in words if w['unitId']==unit['id']]
        if not linked: raise ValueError('Source unit has no spoken words')
        start,end=unit['sourceStart'],unit['sourceEnd']
        if not isinstance(unit.get('passageId'),str) or not unit['passageId']: raise ValueError('Missing canonical passage')
        if not isinstance(start,int) or not isinstance(end,int) or start<0 or end<=start: raise ValueError('Invalid source')
        observation=observed.get(unit['id'])
        times={} if observation is None else {w['wordId']:w for w in observation.get('wordStarts',[])}
        if observation is not None and len(times)!=len(observation.get('wordStarts',[])): raise ValueError('Duplicate word observation')
        if not set(times)<=set(linked): raise ValueError('Foreign observed word')
        first=times.get(linked[0]); highlight=None if observation is None else observation.get('highlightStartMs')
        valid=first is not None and finite(first.get('audibleStartMs')) and finite(highlight)
        source_ok=observation is not None and observation.get('sourceStart')==start and observation.get('sourceEnd')==end and observation.get('passageId')==unit['passageId']
        if valid and not source_ok: wrong+=1
        if valid and source_ok:
            error=abs(highlight-first['audibleStartMs']);errors.append(error)
            if source_ok and error<=200: correct+=1
        elif not valid: missing+=1
        if len(linked)>1:
            expansions+=1
            complete=all(w in times and finite(times[w].get('audibleStartMs')) and times[w].get('activeSourceStart')==start and times[w].get('activeSourceEnd')==end and times[w].get('activePassageId')==unit['passageId'] for w in linked)
            if complete and source_ok: expansions_ok+=1
    errors.sort()
    return {'N':len(units),'K':correct,'spokenWords':len(words),'missingTimings':missing,'wrongSourceRanges':wrong,
      'coverage':len(errors)/len(units),'ratio':correct/len(units),
      'p95MeasuredAbsErrorMs':None if not errors else errors[math.ceil(.95*len(errors))-1],
      'expansions':expansions,'expansionsPassed':expansions_ok,
      'timingPassed':correct/len(units)>=.95,'allExpansionsPassed':expansions==expansions_ok}

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['expected','observed','wav','capture','output']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():parser.error('Fresh report required')
    if args.expected.stat().st_size>10485760 or args.observed.stat().st_size>10485760:parser.error('Annotation size limit')
    expected=json.loads(args.expected.read_text(encoding='utf-8'));observed=json.loads(args.observed.read_text(encoding='utf-8'))
    metrics=score(expected,observed['units'])
    evidence=(expected.get('annotationsFrozen') is True and expected.get('spokenWordCountVerified') is True and expected.get('platform')=='android' and expected.get('inferenceOnDevice') is True
      and expected.get('audioSha256')==digest(args.wav)==observed.get('audioSha256')
      and observed.get('captureSha256')==digest(args.capture)
      and observed.get('annotationMethod')=='manual_audiovisual'
      and isinstance(observed.get('uncertaintyMs'),(int,float)) and 0<=observed['uncertaintyMs']<=50
      and bool(observed.get('annotator')) and bool(observed.get('calibration')))
    status='not_evaluated' if not evidence else ('passed' if metrics['spokenWords']>=500 and metrics['timingPassed'] and metrics['allExpansionsPassed'] else 'failed')
    report={'sc003':status,'g1':'not_evaluated','evidenceComplete':evidence,'metrics':metrics,'expectedSha256':digest(args.expected),
      'observationsSha256':digest(args.observed),'limitations':'Numeric scoring does not independently authenticate human annotations or qualify parity, cost and cancellation.'}
    args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':main()
