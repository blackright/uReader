"""Collect verified native clips; reuse production Dart padding and preserve raw PCM."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[3]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign',type=Path,required=True)
    parser.add_argument('--prepared-root',type=Path,required=True)
    parser.add_argument('--dart',type=Path,required=True)
    args=parser.parse_args()
    spec=importlib.util.spec_from_file_location('campaign',Path(__file__).with_name('narration-campaign.py'))
    tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
    campaign=tool.private_path(args.campaign)
    plan=json.loads((campaign/'plan.json').read_text(encoding='utf-8'))
    capture=json.loads((campaign/'android-captures.json').read_text(encoding='utf-8'))
    if capture['corpusSha256']!=plan['corpusSha256']:raise ValueError('Corpus mismatch')
    flat=campaign/'android-native';flat.mkdir(exist_ok=False)
    seen=set()
    for i,entry in enumerate(capture['captures']):
        root=tool.private_path(ROOT/entry['directory'])
        native=tool.verify_capture(root,plan['batches'][i]['sha256'])
        for row in native['cases']:
            if row['id'] in seen:raise ValueError('Duplicate native ID')
            seen.add(row['id'])
            shutil.copyfile(root/'native'/row['wav'],flat/row['wav'])
    if len(seen)!=sum(b['segments'] for b in plan['batches']):raise ValueError('Missing native case')
    out=campaign/'android-listening';out.mkdir(exist_ok=False)
    report={'corpusSha256':plan['corpusSha256'],'candidate':'Android current',
            'postprocessing':'production PunctuationAudio; raw speech PCM verified unchanged',
            'status':'generating','takeNumber':1,'listening':'not_evaluated','paragraphs':[]}
    for i in range(1,5):
        source=tool.private_path(args.prepared_root/f'batch-{i:02d}-prepared/cases.json')
        target=campaign/f'android-postprocess-{i:02d}'
        subprocess.run([str(args.dart),'--packages=.dart_tool/package_config.json',
                        'validation/reader/tools/compare_french_audio.dart',str(source),str(flat),str(target)],check=True,cwd=ROOT)
        compared=json.loads((target/'comparison.json').read_text(encoding='utf-8'))
        if compared['postprocessingSpeechPcmUnchanged'] is not True:raise ValueError('PCM changed')
        paragraphs=json.loads(source.read_text(encoding='utf-8'))['paragraphs']
        for p in paragraphs:
            pid=p['corpusId'];wav=out/(pid+'-T01.wav')
            shutil.copyfile(target/(p['id']+'-played.wav'),wav)
            report['paragraphs'].append({'paragraphId':pid,'takeNumber':1,'wav':wav.name,'sha256':sha(wav)})
    if [p['paragraphId'] for p in report['paragraphs']]!=[f'P{i:02d}' for i in range(1,21)]:raise ValueError('Paragraph order')
    report['status']='generated_listening_pending'
    (out/'index.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('Twenty Android listening WAVs assembled; source PCM unchanged. Listening pending.')


if __name__=='__main__':main()
