"""Render the reference-boundary clips with the pinned local official PC implementation."""
import argparse,hashlib,importlib.util,json,wave
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    private=(ROOT/'validation/reader/private').resolve()
    if not args.cases.resolve().is_relative_to(private) or not args.output.resolve().is_relative_to(private):raise ValueError('Private paths required')
    data=json.loads(args.cases.read_text(encoding='utf-8'))
    selected=[r for r in data['cases'] if r.get('variant')=='official-reference-chunking']
    if not 1<=len(selected)<=8:raise ValueError('Reference case budget')
    args.output.mkdir(exist_ok=False)
    pc_input=args.output/'input.json'
    # Reference runner records mappings, but these diagnostic chunks have no
    # production source map and must never be used as G1 annotation evidence.
    pc_input.write_text(json.dumps({'normalizerVersion':data['normalizerVersion'],
        'cases':[{**r,'spans':[]} for r in selected]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    spec=importlib.util.spec_from_file_location('aligned_reference',ROOT/'validation/scripts/aligned-reference.py')
    reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)
    reports=[];pcm=[]
    for row in selected:
        output=args.output/(row['id']+'.wav')
        result=reference.run('fr-01-p1',output,50,normalized_cases=pc_input,case_id=row['id'])
        if result['preparedTextSha256']!=hashlib.sha256(row['synthesisText'].encode('utf-8')).hexdigest():raise ValueError('Reference prepared input differs')
        reports.append(result)
        with wave.open(str(output),'rb') as wav:
            if (wav.getnchannels(),wav.getsampwidth(),wav.getframerate())!=(1,2,24000):raise ValueError('WAV format')
            pcm.append(wav.readframes(wav.getnframes()))
        print('Rendered '+row['id'],flush=True)
    joined=args.output/'first-paragraph-official-pc.wav'
    with wave.open(str(joined),'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(24000);wav.writeframes(b''.join(pcm))
    report={'status':'generated_listening_pending','cases':reports,'samePreparedTextAsAndroidReferenceVariant':True,
        'sameNoiseAsAndroid':False,'comparison':'qualitative only; numerical parity and causal model-quality conclusions not established',
        'productionMappingValidated':False,'g1':'not_evaluated','joinedWav':joined.name}
    (args.output/'reference-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
