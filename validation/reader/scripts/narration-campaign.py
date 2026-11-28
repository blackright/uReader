"""Plan bounded, immutable private narration batches; no synthesis or network."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT/'validation/reader/private'


def private_path(path):
    path = Path(path).resolve()
    if not path.is_relative_to(PRIVATE.resolve()):
        raise ValueError('Private path required')
    return path


def transfer(value):
    payload = (json.dumps(value,ensure_ascii=True,indent=2)+'\n').encode('utf-8')
    return payload,hashlib.sha256(payload).hexdigest()


def verify_capture(directory, expected_input):
    """Resume only a complete capture with matching transferred input and WAVs."""
    directory=Path(directory)
    report=json.loads((directory/'run-report.json').read_text(encoding='utf-8'))
    native=json.loads((directory/'native-report.json').read_text(encoding='utf-8'))
    if (report.get('status')!='captured_listening_pending' or report.get('appRestored') is not True
            or report.get('inputSha256')!=expected_input or native.get('inputSha256')!=expected_input):
        raise ValueError('Incomplete or incompatible capture; preserve and use an explicit new attempt')
    for row in native['cases']:
        if not re.fullmatch('[a-z-]+-[0-9]{1,2}',row['id']) or row['wav']!=row['id']+'.wav':raise ValueError('WAV path')
        path=directory/'native'/row['wav']
        if path.stat().st_size>960044:raise ValueError('WAV bounds')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:raise ValueError('Changed captured WAV')
    return native


def plan_batches(corpus, prepared, take=1):
    if type(take) is not int or take not in (1,2,3):raise ValueError('Take bounds')
    if not re.fullmatch('[a-f0-9]{64}',corpus['corpusSha256']):raise ValueError('Corpus hash')
    if len(corpus['paragraphs'])!=20 or len(prepared)!=20:raise ValueError('Twenty paragraphs required')
    cases=[];seen=set()
    units=lambda s:len(s.encode('utf-16-le'))//2
    for n,(source,paragraph) in enumerate(zip(corpus['paragraphs'],prepared),1):
        pid=f'P{n:02d}'
        if source['id']!=pid or paragraph['corpusId']!=pid:raise ValueError('Paragraph order')
        text=source['sourceText']
        if paragraph['source']!=text or hashlib.sha256(text.encode()).hexdigest()!=source['sourceSha256']:
            raise ValueError('Source hash')
        segments=paragraph['segments']
        if not segments or ''.join(s['sourceText'] for s in segments)!=text:raise ValueError('Source coverage')
        offset=0
        for s in segments:
            sid=s['id']
            if not re.fullmatch('[a-z-]+-[0-9]{1,2}',sid) or sid in seen:raise ValueError('Segment ID')
            seen.add(sid)
            end=offset+units(s['sourceText'])
            if s['sourceStart']!=offset or s['sourceEnd']!=end:raise ValueError('Source range')
            if type(s['tokens']) is not int or not 1<=s['tokens']<=50:raise ValueError('Token budget')
            if not 1<=units(s['synthesisText'])<=4096:raise ValueError('Text budget')
            cases.append({**s,'paragraphId':pid,'takeNumber':take,
                          'seed':7100+100*n+take})
            offset=end
    # Eight segments leave conservative headroom below the native 32-case limit.
    return [{'schemaVersion':1,'normalizerVersion':'fr-numbers-v3',
             'corpusSha256':corpus['corpusSha256'],'takeNumber':take,
             'cases':cases[i:i+8]} for i in range(0,len(cases),8)]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus',required=True)
    parser.add_argument('--prepared-root',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    corpus=json.loads(private_path(args.corpus).read_text(encoding='utf-8'))
    prepared=[]
    for i in range(1,5):
        p=private_path(Path(args.prepared_root)/f'batch-{i:02d}-prepared/cases.json')
        prepared.extend(json.loads(p.read_text(encoding='utf-8'))['paragraphs'])
    batches=plan_batches(corpus,prepared)
    output=private_path(args.output)
    output.mkdir(exist_ok=False)
    records=[]
    for i,batch in enumerate(batches,1):
        payload,digest=transfer(batch)
        if len(payload)>1048576:raise ValueError('Transfer budget')
        name=f'batch-{i:02d}.json'
        (output/name).write_bytes(payload)
        records.append({'file':name,'sha256':digest,'segments':len(batch['cases'])})
    plan={'corpusSha256':corpus['corpusSha256'],'takeNumber':1,
          'seedPolicy':'7100 + 100 * paragraphNumber + takeNumber; reset for each segment',
          'batches':records,'paragraphs':prepared,'status':'planned'}
    (output/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'planned','batches':len(batches),'paragraphs':20}))


if __name__=='__main__':main()
