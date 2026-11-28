"""Assemble twenty verified minimal-profile takes without any new synthesis."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import wave

ROOT=Path(__file__).resolve().parents[3]


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def digest(text):return hashlib.sha256(text.encode('utf-8')).hexdigest()


def select_inputs(plan,baseline,corrected,patch):
    if any(x.get('status')!='generated_listening_pending' for x in (baseline,corrected)):raise ValueError('Complete input reports required')
    if any(x['corpusSha256']!=plan['corpusSha256'] for x in (baseline,corrected)):raise ValueError('Corpus identity')
    if any(baseline[k]!=corrected[k] for k in ('parameters','versions')):raise ValueError('Configuration changed')
    ids=[f'P{i:02d}' for i in range(1,21)]
    if [p['corpusId'] for p in plan['paragraphs']]!=ids or [p['paragraphId'] for p in baseline['paragraphs']]!=ids:raise ValueError('Twenty ordered paragraphs required')
    old={s['id']:s for s in baseline['segments']};new={s['id']:s for s in corrected['segments']}
    if len(old)!=len(baseline['segments']) or len(new)!=len(corrected['segments']):raise ValueError('Duplicate segment')
    if [s['id'] for p in plan['paragraphs'] for s in p['segments']]!=[s['id'] for s in baseline['segments']]:raise ValueError('Segment sequence')
    result=[]
    for p in plan['paragraphs']:
        if ''.join(s['sourceText'] for s in p['segments'])!=p['source']:raise ValueError('Source coverage')
        rows=[];offset=0
        for s in p['segments']:
            b=old[s['id']];end=offset+len(s['sourceText'].encode('utf-16-le'))//2
            if (s['sourceStart'],s['sourceEnd'])!=(offset,end):raise ValueError('Source range')
            offset=end
            if b['status']!='generated' or b['paragraphId']!=p['corpusId']:raise ValueError('Baseline state')
            if digest(s['sourceText'])!=b['sourceTextSha256'] or digest(s['synthesisText'])!=b['synthesisTextSha256']:raise ValueError('Changed source or prompt')
            expected=patch(s['synthesisText'],b['phonemes'])
            if expected['changes']:
                n=new.get(s['id'])
                if n is None:raise ValueError('Required lexical correction absent; no silent baseline fallback')
                if (n['status']!='generated' or n['phonemes']!=expected['phonemes']
                        or n['seed']!=b['seed'] or n['baselineStyleIndex']!=len(b['phonemes'])-1
                        or any(n[k]!=b[k] for k in ('sourceTextSha256','synthesisTextSha256'))
                        or (n['sourceStart'],n['sourceEnd'])!=(s['sourceStart'],s['sourceEnd'])):
                    raise ValueError('Corrected input differs from authorized minimal profile')
                rows.append({'origin':'corrected','input':s,'record':n})
            else:rows.append({'origin':'baseline','input':s,'record':b})
        result.append({'paragraphId':p['corpusId'],'segments':rows})
    return result


def checked_wav(root,record,maximum_seconds):
    name=record['wav']
    if not re.fullmatch(r'[A-Za-z0-9-]+\.wav',name):raise ValueError('Unsafe WAV name')
    path=(root/name).resolve()
    if path.parent!=root.resolve():raise ValueError('WAV outside source directory')
    if path.stat().st_size>maximum_seconds*48000+4096:raise ValueError('WAV byte bound')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=record['sha256']:raise ValueError('WAV hash mismatch')
    with wave.open(str(path),'rb') as wav:
        if (wav.getnchannels(),wav.getsampwidth(),wav.getframerate())!=(1,2,24000):raise ValueError('WAV format')
        if not 0<wav.getnframes()<=maximum_seconds*24000:raise ValueError('WAV duration')
        pcm=wav.readframes(wav.getnframes())
    return path,pcm


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    private=(ROOT/'validation/reader/private').resolve()
    if any(not p.resolve().is_relative_to(private) for p in (args.campaign,args.output)):raise ValueError('Private paths')
    baseline_root=args.campaign/'kokoro-siwis-T01';corrected_root=args.campaign/'kokoro-minimal-lexical-01'
    plan=json.loads((args.campaign/'plan.json').read_text(encoding='utf-8'))
    baseline=json.loads((baseline_root/'index.json').read_text(encoding='utf-8'))
    corrected=json.loads((corrected_root/'index.json').read_text(encoding='utf-8'))
    patches=load('patches',Path(__file__).with_name('kokoro-minimal-patches.py'))
    helper=load('journal',Path(__file__).with_name('render-narration-reference.py'))
    rating=load('rating',Path(__file__).with_name('validate-narration-results.py'))
    publisher=load('publisher',Path(__file__).with_name('publish-narration-listening.py'))
    if corrected['patchSourceSha256']!=helper.sha(Path(__file__).with_name('kokoro-minimal-patches.py')):raise ValueError('Lexical profile changed')
    if corrected['baselineIndexSha256']!=helper.sha(baseline_root/'index.json'):raise ValueError('Baseline report changed')
    selected=select_inputs(plan,baseline,corrected,patches.patch)
    # Validate every source before creating any output or claiming readiness.
    ready=[]
    for p in selected:
        frames=[];records=[]
        for row in p['segments']:
            root=corrected_root if row['origin']=='corrected' else baseline_root
            path,pcm=checked_wav(root,row['record'],20);frames.append(pcm)
            records.append({'id':row['record']['id'],'origin':row['origin'],'sha256':row['record']['sha256'],
                            'sourceWav':path.relative_to(ROOT).as_posix()})
        changed=any(row['origin']=='corrected' for row in p['segments'])
        report=corrected if changed else baseline
        root=corrected_root if changed else baseline_root
        paragraph=next(x for x in report['paragraphs'] if x['paragraphId']==p['paragraphId'])
        path,pcm=checked_wav(root,paragraph,300)
        if pcm!=b''.join(frames):raise ValueError('Paragraph does not match the verified raw clip sequence')
        ready.append({'paragraphId':p['paragraphId'],'path':path,'sha256':paragraph['sha256'],
                      'changed':changed,'records':records})
    reference=json.loads((args.campaign/'owner-feedback/P05-quality-reference-01.json').read_text(encoding='utf-8'))
    if ready[4]['sha256']!=reference['audioSha256']:raise ValueError('P05 reference changed')
    args.output.mkdir(exist_ok=False)
    index={'corpusSha256':plan['corpusSha256'],'candidate':'kokoro-siwis-minimal-lexical',
           'preparationVersion':patches.VERSION,'status':'assembled_listening_pending',
           'scriptSha256':helper.sha(__file__),'baselineIndexSha256':helper.sha(baseline_root/'index.json'),
           'correctedIndexSha256':helper.sha(corrected_root/'index.json'),'newSynthesisPerformed':False,
           'P05ReferenceByteIdentical':True,'listening':'not_evaluated','paragraphs':[],'segments':[]}
    rows=[]
    for p in ready:
        target=args.output/(p['paragraphId']+'-T01.wav');shutil.copyfile(p['path'],target)
        if helper.sha(target)!=p['sha256']:raise ValueError('Copied WAV changed')
        index['paragraphs'].append({'paragraphId':p['paragraphId'],'takeNumber':1,'wav':target.name,
                                    'sha256':p['sha256'],'changedFromBaseline':p['changed'],
                                    'sourceWav':p['path'].relative_to(ROOT).as_posix()})
        index['segments'].extend(p['records'])
        row=rating.blank(plan['corpusSha256'],'F',p['paragraphId'],1)
        row.update(audioSha256=p['sha256'],audioPath=target.resolve().as_posix());rows.append(row)
    (args.output/'index.json').write_text(json.dumps(index,indent=2)+'\n',encoding='utf-8')
    ratings={'corpusSha256':plan['corpusSha256'],'ownerAcceptedCandidate':None,
             'candidateMap':{'F':patches.VERSION},'ratings':rows}
    with (args.output/'ratings.json').open('x',encoding='utf-8') as f:json.dump(ratings,f,ensure_ascii=False,indent=2);f.write('\n')
    landing=['# Kokoro — corpus complet minimal P01–P20','','Profil lexical minimal, premières prises conservées. Aucun nouveau son synthétisé pour assembler ce dossier.',
             'P05 est identique à la référence choisie ; seuls P11/P16/P20 diffèrent de la première campagne.',
             'Le retour positif sur les extraits corrigés est conservé séparément ; aucune note par dimension n’est inventée.',
             'Les pauses initiales et le passage « miss Nelly » restent à traiter séparément.','']
    for start in range(0,20,5):
        name=f'lot-{start//5+1:02d}.md';landing.append(f'- [P{start+1:02d}–P{start+5:02d}]({name})')
        lines=[f'# P{start+1:02d}–P{start+5:02d}','','Même casque et mêmes réglages de lecture pour comparer.','']
        for p in index['paragraphs'][start:start+5]:
            original=next(x for x in plan['paragraphs'] if x['corpusId']==p['paragraphId'])
            state='correction lexicale déjà présentée' if p['changedFromBaseline'] else 'identique au rendu initial'
            lines.extend(['## '+p['paragraphId'],'',state,'',f"[{(args.output/p['wav']).resolve().as_posix()}]({(args.output/p['wav']).resolve().as_posix()})",'',publisher.quoted_source(original['source']),''])
        (args.output/name).write_text('\n'.join(lines)+'\n',encoding='utf-8')
    (args.output/'listening.md').write_text('\n'.join(landing)+'\n',encoding='utf-8')
    print(json.dumps({'status':'assembled_listening_pending','paragraphs':20,
                      'unchangedParagraphs':sum(not p['changed'] for p in ready),
                      'correctedSegmentsReused':sum(s['origin']=='corrected' for p in ready for s in p['records']),
                      'P05ReferenceByteIdentical':True,'newSynthesisPerformed':False}))


if __name__=='__main__':main()
