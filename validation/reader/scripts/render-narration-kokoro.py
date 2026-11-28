"""French-only Kokoro laboratory adapter; verified local weights and blocked sockets."""
import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import socket
import time
import wave

ROOT=Path(__file__).resolve().parents[3]


def offline(*args,**kwargs):raise RuntimeError('Network forbidden during private rendering')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--take',type=int,choices=(1,2,3),default=1)
    parser.add_argument('--confirmed-finalist',action='store_true')
    parser.add_argument('--preparation',choices=('pocket-baseline','french-v2'),default='pocket-baseline')
    parser.add_argument('--paragraphs',nargs='+',choices=tuple(f'P{i:02d}' for i in range(1,21)))
    args=parser.parse_args()
    if args.take!=1 and not args.confirmed_finalist:raise ValueError('Select finalists first')
    if args.paragraphs and (len(set(args.paragraphs))!=len(args.paragraphs) or args.take!=1):raise ValueError('Diagnostic selection')
    private=(ROOT/'validation/reader/private').resolve()
    if any(not p.resolve().is_relative_to(private) for p in (args.plan,args.output)):raise ValueError('Private paths')
    os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',DO_NOT_TRACK='1',TRANSFORMERS_OFFLINE='1')
    socket.socket.connect=socket.socket.connect_ex=socket.create_connection=socket.getaddrinfo=offline
    manifest=json.loads((ROOT/'specs/004-french-narration-quality/candidate-files.json').read_text())
    candidate=next(c for c in manifest['candidates'] if c['candidateId']=='kokoro-siwis')
    vspec=importlib.util.spec_from_file_location('verifier',ROOT/'validation/scripts/verify-model-files.py')
    verifier=importlib.util.module_from_spec(vspec);vspec.loader.exec_module(verifier)
    directory=ROOT/candidate['directory']
    if verifier.verify(directory,candidate['downloadFiles']):raise ValueError('Model integrity')
    spec=importlib.util.spec_from_file_location('reference',Path(__file__).with_name('render-narration-reference.py'))
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    plan=json.loads(args.plan.read_text(encoding='utf-8'))
    if len(plan['paragraphs'])!=20:raise ValueError('Twenty paragraphs required')
    args.output.mkdir(exist_ok=False)
    report={'candidate':'kokoro-siwis','corpusSha256':plan['corpusSha256'],'takeNumber':args.take,
            'status':'initializing','scriptSha256':helper.sha(__file__),'planSha256':helper.sha(args.plan),
            'files':{f['relativePath']:f['sha256'] for f in candidate['downloadFiles']},
            'parameters':{'language':'fr-fr','voice':'ff_siwis','speed':1,'threads':1},
            'networkBlocked':True,'postprocessing':'raw clips concatenated; no terminal padding',
            'samePreparedTextAsPocket':True,'g2p':'Misaki EspeakG2P fr-fr; no truncation permitted',
            'listening':'not_evaluated','segments':[],'paragraphs':[]}
    frontend=None
    if args.preparation=='french-v2':
        fspec=importlib.util.spec_from_file_location('french_preparation',Path(__file__).with_name('kokoro-french-preparation.py'))
        frontend=importlib.util.module_from_spec(fspec);fspec.loader.exec_module(frontend)
        report.update(candidate='kokoro-siwis-french-v2',preparationVersion=frontend.VERSION,
                      preparationSourceSha256=helper.sha(Path(__file__).with_name('kokoro-french-preparation.py')),
                      samePreparedTextAsPocket=False,g2p='French explicit lexicon; unexpected switches rejected; proposed readings',
                      contextLimit=510,maxClipSeconds=60,selectedParagraphs=args.paragraphs,
                      postprocessing='Source punctuation preserved; raw clips concatenated, no artificial terminal period or padding')
    index=args.output/'index.json';helper.dump(index,report)
    try:
        import numpy as np
        import torch
        from kokoro import KModel
        from misaki.espeak import EspeakG2P
        if importlib.metadata.version('kokoro')!='0.9.4':raise ValueError('Pinned Kokoro required')
        report['versions']={name:importlib.metadata.version(name) for name in ('kokoro','misaki','espeakng-loader','phonemizer-fork','torch','numpy','transformers')}
        torch.set_num_threads(1)
        model=KModel(repo_id='hexgrad/Kokoro-82M',config=str(directory/'config.json'),model=str(directory/'kokoro-v1_0.pth')).to('cpu').eval()
        pack=torch.load(directory/'ff_siwis.pt',map_location='cpu',weights_only=True)
        g2p=EspeakG2P(language='fr-fr')
        if frontend:
            from phonemizer.backend import EspeakBackend
            g2p.backend=EspeakBackend(language='fr-fr',preserve_punctuation=True,with_stress=True,
                                     tie='^',language_switch='keep-flags')
        report['status']='generating';helper.dump(index,report)
        for number,p in enumerate(plan['paragraphs'],1):
            if args.take!=1 and number not in (1,5,10,15,20):continue
            if args.paragraphs and p['corpusId'] not in args.paragraphs:continue
            frames=[]
            if frontend:
                if p['source']!=p['normalizedText']:raise ValueError('Diagnostic requires unchanged normalization; source map extension needed otherwise')
                prepared=frontend.chunks(p['source'],lambda text:frontend.phonemize(text,lambda t:g2p(t)[0]),
                                         limit=min(510,model.context_length-2,pack.shape[0]))
                segments=[{'id':f'p{number:02d}-s{i:02d}','sourceText':row['source'],
                           'synthesisText':row['source'],'sourceStart':row['startUtf16'],'sourceEnd':row['endUtf16'],
                           'preparedPhonemes':row['phonemes'],'overrides':row['overrides']} for i,row in enumerate(prepared,1)]
            else:segments=p['segments']
            for s in segments:
                text=s['synthesisText'];seed=7100+100*number+args.take
                entry={'id':s['id'],'paragraphId':p['corpusId'],'seed':seed,'status':'generating',
                       'sourceTextSha256':hashlib.sha256(s['sourceText'].encode()).hexdigest(),
                       'synthesisTextSha256':hashlib.sha256(text.encode()).hexdigest()}
                report['segments'].append(entry);helper.dump(index,report)
                if frontend:
                    phonemes=s['preparedPhonemes']
                    entry.update(sourceStart=s['sourceStart'],sourceEnd=s['sourceEnd'],
                                 lexicalOverrides=s['overrides'],overrideRangeBasis='relative to segment source')
                else:phonemes,_=g2p(text)
                unknown=sorted(set(c for c in phonemes if c not in model.vocab))
                if not phonemes or len(phonemes)+2>model.context_length or len(phonemes)>pack.shape[0] or unknown:
                    entry.update(phonemeCount=len(phonemes),unknownPhonemes=unknown)
                    raise ValueError('G2P vocabulary or context would omit phonemes')
                entry.update(phonemes=phonemes,phonemeCount=len(phonemes),truncated=False)
                torch.manual_seed(seed);start=time.monotonic()
                with torch.no_grad():audio=model(phonemes,pack[len(phonemes)-1],speed=1).numpy().reshape(-1)
                max_samples=24000*(60 if frontend else 20)
                if not 0<audio.size<=max_samples or not np.isfinite(audio).all() or not np.any(audio):raise ValueError('PCM bounds')
                pcm=(np.clip(audio,-1,1)*32767).astype('<i2').tobytes()
                wav=args.output/(s['id']+'.wav')
                with wav.open('xb') as f:
                    with wave.open(f,'wb') as out:
                        out.setparams((1,2,24000,0,'NONE','not compressed'));out.writeframes(pcm)
                frames.append(pcm);entry.update(status='generated',wav=wav.name,sha256=helper.sha(wav),samples=int(audio.size),generationSeconds=time.monotonic()-start)
                helper.dump(index,report)
            wav=args.output/(p['corpusId']+f'-T{args.take:02d}.wav')
            if sum(map(len,frames))>24000*2*300:raise ValueError('Paragraph duration')
            with wav.open('xb') as f:
                with wave.open(f,'wb') as out:
                    out.setparams((1,2,24000,0,'NONE','not compressed'));out.writeframes(b''.join(frames))
            report['paragraphs'].append({'paragraphId':p['corpusId'],'takeNumber':args.take,'wav':wav.name,'sha256':helper.sha(wav),'samples':sum(map(len,frames))//2})
            helper.dump(index,report);print('Generated '+p['corpusId'],flush=True)
        report['status']='generated_listening_pending'
    except BaseException as error:
        report['status']='failed';report['failureType']=type(error).__name__
        raise
    finally:helper.dump(index,report)


if __name__=='__main__':main()
