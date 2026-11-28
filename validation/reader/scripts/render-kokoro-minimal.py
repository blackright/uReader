"""Keep baseline prompts, cuts, seeds and style; synthesize only four lexical edits."""
import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import time
import wave

ROOT=Path(__file__).resolve().parents[3]


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def take_schedule(plan,take):
    if type(take) is not int or take not in (1,2,3):raise ValueError('Take bounds')
    if [p['corpusId'] for p in plan['paragraphs']]!=[f'P{i:02d}' for i in range(1,21)]:raise ValueError('Twenty ordered paragraphs required')
    selected=('P05','P11','P16','P20') if take==1 else ('P01','P05','P10','P15','P20')
    return [{'paragraphId':pid,'takeNumber':take,'seed':7100+100*int(pid[1:])+take} for pid in selected]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--take',type=int,choices=(1,2,3),default=1)
    parser.add_argument('--registration',type=Path,help='Required preregistration for robustness takes')
    args=parser.parse_args()
    private=(ROOT/'validation/reader/private').resolve()
    if any(not p.resolve().is_relative_to(private) for p in (args.campaign,args.output)):raise ValueError('Private paths')
    if args.take!=1 and (args.registration is None or not args.registration.resolve().is_relative_to(private)):raise ValueError('Register robustness takes before generation')
    os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',DO_NOT_TRACK='1',TRANSFORMERS_OFFLINE='1')
    def blocked(*a,**k):raise RuntimeError('Network forbidden')
    socket.socket.connect=socket.socket.connect_ex=socket.create_connection=socket.getaddrinfo=blocked
    helper=load('journal',Path(__file__).with_name('render-narration-reference.py'))
    patches=load('patches',Path(__file__).with_name('kokoro-minimal-patches.py'))
    verifier=load('verifier',ROOT/'validation/scripts/verify-model-files.py')
    baseline_root=args.campaign/'kokoro-siwis-T01'
    baseline=json.loads((baseline_root/'index.json').read_text(encoding='utf-8'))
    plan=json.loads((args.campaign/'plan.json').read_text(encoding='utf-8'))
    if baseline['corpusSha256']!=plan['corpusSha256'] or baseline['status']!='generated_listening_pending':raise ValueError('Baseline identity')
    if any(importlib.metadata.version(k)!=v for k,v in baseline['versions'].items()):raise ValueError('Runtime changed from baseline')
    manifest=json.loads((ROOT/'specs/004-french-narration-quality/candidate-files.json').read_text(encoding='utf-8'))
    candidate=next(c for c in manifest['candidates'] if c['candidateId']=='kokoro-siwis')
    directory=ROOT/candidate['directory']
    if verifier.verify(directory,candidate['downloadFiles']):raise ValueError('Model integrity')
    schedule=take_schedule(plan,args.take)
    if args.take!=1:
        registration=json.loads(args.registration.read_text(encoding='utf-8'))
        if (registration['corpusSha256']!=plan['corpusSha256']
                or registration['baselineIndexSha256']!=helper.sha(baseline_root/'index.json')
                or registration['patchSourceSha256']!=helper.sha(Path(__file__).with_name('kokoro-minimal-patches.py'))
                or [r for r in registration['takes'] if r['takeNumber']==args.take]!=schedule):
            raise ValueError('Registered configuration or take schedule differs')
    seeds={row['paragraphId']:row['seed'] for row in schedule}
    selected=[p for p in plan['paragraphs'] if p['corpusId'] in seeds]
    planned=[]
    for p in selected:
        rows=[]
        for s in p['segments']:
            old=next(x for x in baseline['segments'] if x['id']==s['id'])
            if old['synthesisTextSha256']!=hashlib.sha256(s['synthesisText'].encode()).hexdigest():raise ValueError('Changed prompt')
            if helper.sha(baseline_root/old['wav'])!=old['sha256']:raise ValueError('Changed baseline clip')
            rows.append({'input':s,'baseline':old,'patch':patches.patch(s['synthesisText'],old['phonemes'])})
        planned.append((p,rows))
    args.output.mkdir(exist_ok=False)
    report={'candidate':'kokoro-siwis-minimal-lexical','preparationVersion':patches.VERSION,
            'corpusSha256':plan['corpusSha256'],'status':'initializing','takeNumber':args.take,
            'scriptSha256':helper.sha(__file__),'patchSourceSha256':helper.sha(Path(__file__).with_name('kokoro-minimal-patches.py')),
            'baselineIndexSha256':helper.sha(baseline_root/'index.json'),'versions':baseline['versions'],
            'parameters':baseline['parameters'],'sourceCutsPreserved':True,'preparedTextPreserved':True,
            'baselineStyleIndexPreserved':True,'unaffectedAudioReusedByteForByte':args.take==1,
            'allAudioFresh':args.take!=1,'takeSchedule':schedule,
            'pythonNetworkBlocked':True,'listening':'not_evaluated','segments':[],'paragraphs':[]}
    if args.take!=1:report['registrationSha256']=helper.sha(args.registration)
    index=args.output/'index.json';helper.dump(index,report)
    try:
        import numpy as np
        import torch
        from kokoro import KModel
        torch.set_num_threads(1)
        model=KModel(repo_id='hexgrad/Kokoro-82M',config=str(directory/'config.json'),model=str(directory/'kokoro-v1_0.pth')).to('cpu').eval()
        pack=torch.load(directory/'ff_siwis.pt',map_location='cpu',weights_only=True)
        report['status']='generating';helper.dump(index,report)
        for p,rows in planned:
            frames=[]
            for row in rows:
                s,old,change=row['input'],row['baseline'],row['patch']
                phones=change['phonemes'];style_index=len(old['phonemes'])-1
                if not 0<len(phones)<=510 or any(c not in model.vocab for c in phones) or not 0<=style_index<pack.shape[0]:raise ValueError('Phoneme/style bounds')
                target=args.output/(old['wav'] if args.take==1 else s['id']+f'-T{args.take:02d}.wav')
                entry={'id':s['id'],'paragraphId':p['corpusId'],'seed':seeds[p['corpusId']],
                       'sourceTextSha256':old['sourceTextSha256'],'synthesisTextSha256':old['synthesisTextSha256'],
                       'sourceStart':s['sourceStart'],'sourceEnd':s['sourceEnd'],'baselineSha256':old['sha256'],
                       'baselineStyleIndex':style_index,'phonemes':phones,'changes':change['changes'],
                       'status':'generating','reused':args.take==1 and not bool(change['changes']),
                       'synthesisExecuted':False}
                report['segments'].append(entry);helper.dump(index,report)
                if change['changes'] or args.take!=1:
                    torch.manual_seed(seeds[p['corpusId']]);start=time.monotonic()
                    with torch.no_grad():audio=model(phones,pack[style_index],speed=1).numpy().reshape(-1)
                    if not 0<audio.size<=480000 or not np.isfinite(audio).all() or not np.any(audio):raise ValueError('PCM bounds')
                    pcm=(np.clip(audio,-1,1)*32767).astype('<i2').tobytes()
                    with target.open('xb') as f:
                        with wave.open(f,'wb') as w:w.setparams((1,2,24000,0,'NONE','not compressed'));w.writeframes(pcm)
                    entry['generationSeconds']=time.monotonic()-start
                    entry['synthesisExecuted']=True
                else:shutil.copyfile(baseline_root/old['wav'],target)
                with wave.open(str(target),'rb') as w:
                    if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(1,2,24000):raise ValueError('WAV format')
                    frames.append(w.readframes(w.getnframes()))
                entry.update(status='generated',wav=target.name,sha256=helper.sha(target))
                if entry['reused'] and entry['sha256']!=old['sha256']:raise ValueError('Reused PCM changed')
                helper.dump(index,report)
            target=args.output/(p['corpusId']+f'-T{args.take:02d}.wav')
            old_paragraph=next(x for x in baseline['paragraphs'] if x['paragraphId']==p['corpusId'])
            if args.take==1 and all(row['patch']['changes']==[] for row in rows):
                shutil.copyfile(baseline_root/old_paragraph['wav'],target)
                if helper.sha(target)!=old_paragraph['sha256']:raise ValueError('Reference paragraph changed')
            else:
                with target.open('xb') as f:
                    with wave.open(f,'wb') as w:w.setparams((1,2,24000,0,'NONE','not compressed'));w.writeframes(b''.join(frames))
            report['paragraphs'].append({'paragraphId':p['corpusId'],'takeNumber':args.take,'wav':target.name,'sha256':helper.sha(target),
                'referenceUnchanged':helper.sha(target)==old_paragraph['sha256']})
            helper.dump(index,report);print('Prepared '+p['corpusId'],flush=True)
        report['status']='generated_listening_pending'
    except BaseException as error:
        report['status']='failed';report['failureType']=type(error).__name__;raise
    finally:helper.dump(index,report)


if __name__=='__main__':main()
