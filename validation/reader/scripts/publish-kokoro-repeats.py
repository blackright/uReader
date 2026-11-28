"""Verify ten fresh consistency takes and publish a private thirty-take rating packet."""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]


def load(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    return m


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign',required=True,type=Path)
    args=parser.parse_args()
    if not args.campaign.resolve().is_relative_to((ROOT/'validation/reader/private').resolve()):raise ValueError('Private campaign required')
    root=args.campaign;repeat=root/'kokoro-minimal-robustness-01'
    registration=json.loads((repeat/'registration.json').read_text(encoding='utf-8'))
    baseline=json.loads((root/'kokoro-siwis-T01/index.json').read_text(encoding='utf-8'))
    plan=json.loads((root/'plan.json').read_text(encoding='utf-8'))
    main=json.loads((root/'kokoro-minimal-full-01/index.json').read_text(encoding='utf-8'))
    ratings=json.loads((root/'kokoro-minimal-full-01/ratings.json').read_text(encoding='utf-8'))
    patches=load('kokoro-minimal-patches');wav_tool=load('assemble-kokoro-corpus')
    validator=load('validate-narration-results');publisher=load('publish-narration-listening')
    original={s['id']:s for s in baseline['segments']};records=[];audio={};fresh_clips=0
    for take in (2,3):
        folder=repeat/f'T{take:02d}';report=json.loads((folder/'index.json').read_text(encoding='utf-8'))
        if (report['status']!='generated_listening_pending' or report['takeNumber']!=take
                or report['corpusSha256']!=main['corpusSha256'] or report['preparationVersion']!=main['preparationVersion']
                or report['registrationSha256']!=sha(repeat/'registration.json')
                or report['patchSourceSha256']!=registration['patchSourceSha256']
                or report['parameters']!=baseline['parameters'] or report['versions']!=baseline['versions']):
            raise ValueError('Incomplete or incompatible repeat configuration')
        schedule=[r for r in registration['takes'] if r['takeNumber']==take]
        if [p['paragraphId'] for p in report['paragraphs']]!=[p['paragraphId'] for p in schedule]:raise ValueError('Repeat paragraph sequence')
        for scheduled in schedule:
            pid=scheduled['paragraphId'];source=next(p for p in plan['paragraphs'] if p['corpusId']==pid)
            segments=[s for s in report['segments'] if s['paragraphId']==pid]
            if [s['id'] for s in segments]!=[s['id'] for s in source['segments']]:raise ValueError('Repeat segment sequence')
            frames=[]
            for s,text in zip(segments,source['segments']):
                old=original[s['id']];expected=patches.patch(text['synthesisText'],old['phonemes'])
                if (s.get('reused') is not False or s.get('synthesisExecuted') is not True
                        or s['seed']!=scheduled['seed'] or s['phonemes']!=expected['phonemes']
                        or s['baselineStyleIndex']!=len(old['phonemes'])-1
                        or any(s[k]!=old[k] for k in ('sourceTextSha256','synthesisTextSha256'))
                        or (s['sourceStart'],s['sourceEnd'])!=(text['sourceStart'],text['sourceEnd'])):
                    raise ValueError('Repeat reused audio or changed the profile')
                _,pcm=wav_tool.checked_wav(folder,s,20);frames.append(pcm);fresh_clips+=1
            p=next(p for p in report['paragraphs'] if p['paragraphId']==pid)
            path,pcm=wav_tool.checked_wav(folder,p,300)
            if pcm!=b''.join(frames):raise ValueError('Repeat assembly differs from new raw clips')
            first=next(p for p in main['paragraphs'] if p['paragraphId']==pid)
            _,first_pcm=wav_tool.checked_wav(root/'kokoro-minimal-full-01',first,300)
            record={'paragraphId':pid,'takeNumber':take,'audioPath':path.as_posix(),'sha256':p['sha256'],
                    'pcmSha256':hashlib.sha256(pcm).hexdigest(),'durationSeconds':len(pcm)/48000,
                    'samePcmAsMain':pcm==first_pcm,'freshClips':len(segments)}
            records.append(record);audio[(pid,take)]=record
    if fresh_clips!=32 or len(records)!=10:raise ValueError('Ten takes and 32 new inferences required')
    out=repeat/'listening';out.mkdir(exist_ok=False)
    for record in records:
        row=validator.blank(main['corpusSha256'],'F',record['paragraphId'],record['takeNumber'])
        row.update(audioSha256=record['sha256'],audioPath=record['audioPath']);ratings['ratings'].append(row)
    summary=validator.validate(ratings,'F')
    if len(ratings['ratings'])!=30 or summary['missing']!=0:raise ValueError('Thirty take identities required')
    (out/'ratings.json').write_text(json.dumps(ratings,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with (out/'ratings.csv').open('x',encoding='utf-8-sig',newline='') as f:
        w=csv.writer(f);w.writerow(['take','pronunciation','punctuation','intonation','naturalness','notes','audio'])
        for row in ratings['ratings']:
            w.writerow([row['takeId'],*(row['scores'][k] for k in validator.DIMENSIONS),'',row['audioPath']])
    lines=['# Kokoro — dix reprises de régularité','','Deux nouvelles générations de cinq paragraphes, sans copie du cache. Aucun rendu défavorable n’a été remplacé.',
           'Comparer mots complets, prononciation, pauses, rythme et naturel. Conserver les mêmes conditions d’écoute.',
           'Les notes manquantes restent vides. Les observations antérieures ne sont pas déclarées résolues.',
           'Une nouvelle inférence peut produire le même PCM ; les mesures ci-dessous ne remplacent pas l’écoute.','',
           '| Paragraphe | Première prise | Reprise T02 | Reprise T03 |','| --- | --- | --- | --- |']
    expected=['# Textes attendus — reprises','']
    for pid in ('P01','P05','P10','P15','P20'):
        first=(root/'kokoro-minimal-full-01'/f'{pid}-T01.wav').resolve().as_posix()
        a,b=audio[(pid,2)],audio[(pid,3)]
        lines.append(f"| {pid} | [{pid}-T01.wav]({first}) | [{pid}-T02.wav]({a['audioPath']}) | [{pid}-T03.wav]({b['audioPath']}) |")
        text=next(p for p in plan['paragraphs'] if p['corpusId']==pid)['source']
        expected.extend(['## '+pid,'',publisher.quoted_source(text),''])
    lines.extend(['','[Textes attendus](expected-text.md) — [Grille CSV](ratings.csv)',''])
    (out/'index.md').write_text('\n'.join(lines),encoding='utf-8')
    (out/'expected-text.md').write_text('\n'.join(expected),encoding='utf-8')
    verification={'status':'verified_listening_pending','paragraphTakes':10,'freshInferences':fresh_clips,
                  'registrationSha256':sha(repeat/'registration.json'),'audio':records,
                  'samePcmAcrossRepeats':{pid:audio[(pid,2)]['pcmSha256']==audio[(pid,3)]['pcmSha256'] for pid in ('P01','P05','P10','P15','P20')},
                  'ratingsValidation':summary,'ownerAcceptedCandidate':False,'productionChanged':False,
                  'samplingLimit':'One preferred profile, five paragraphs, two repeats; not exhaustive model reliability or Android performance.'}
    (out/'verification.json').write_text(json.dumps(verification,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'verified_listening_pending','repeats':10,'freshInferences':32,'missingTakeFiles':0,'ratings':summary}))


if __name__=='__main__':main()
