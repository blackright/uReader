"""Pinned local Pocket TTS campaign adapter. No network or production changes."""
import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import time
import wave
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]


def sha(path):
    with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def dump(path,value):
    # Preserve previous checkpoints while replacing the current index atomically.
    temp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.pending')
    with temp.open('x',encoding='utf-8') as f:json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n')
    for attempt in range(30):
        try:
            temp.replace(path)
            return
        except PermissionError:
            # Windows readers/scanners may briefly deny replacement. Never
            # delete the previous checkpoint or retry synthesis to hide this.
            if attempt==29:raise
            time.sleep(.1)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan',required=True,type=Path)
    parser.add_argument('--candidate',choices=('official-reference','pocket24-estelle'),required=True)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--take',type=int,choices=(1,2,3),default=1)
    parser.add_argument('--confirmed-finalist',action='store_true',help='Required for the preregistered robustness takes')
    args=parser.parse_args()
    if args.take!=1 and not args.confirmed_finalist:raise ValueError('Select finalists before robustness generation')
    private=(ROOT/'validation/reader/private').resolve()
    if any(not p.resolve().is_relative_to(private) for p in (args.plan,args.output)):raise ValueError('Private paths')
    plan=json.loads(args.plan.read_text(encoding='utf-8'))
    if len(plan['paragraphs'])!=20:raise ValueError('Twenty paragraphs required')
    # Existing aligned reference blocks sockets and HF resolution before imports.
    spec=importlib.util.spec_from_file_location('aligned_reference',ROOT/'validation/scripts/aligned-reference.py')
    ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
    if importlib.metadata.version('pocket-tts')!='3.3.0':raise ValueError('Pinned runtime required')
    vspec=importlib.util.spec_from_file_location('model_verifier',ROOT/'validation/scripts/verify-model-files.py')
    verifier=importlib.util.module_from_spec(vspec);vspec.loader.exec_module(verifier)
    package=ROOT/'validation/private/reference-venv/Lib/site-packages/pocket_tts'
    if args.candidate=='official-reference':
        lock=json.loads((ROOT/'validation/reference-3.3-aligned-lock.json').read_text())
        directory=ROOT/lock['directory'];entries=lock['downloadFiles']
        tokenizer=ROOT/'validation/private/aligned-bundle-01/tokenizer.json'
        config_path=package/'config/french.yaml'
        if sha(config_path)!=lock['sourceEvidence']['frenchConfigSha256']:raise ValueError('Config changed')
    else:
        manifest=json.loads((ROOT/'specs/004-french-narration-quality/candidate-files.json').read_text())
        candidate=next(c for c in manifest['candidates'] if c['candidateId']==args.candidate)
        directory=ROOT/candidate['directory'];entries=candidate['downloadFiles']
        tokenizer=directory/'tokenizer.json';config_path=package/'config/french_24l.yaml'
    if verifier.verify(directory,entries):raise ValueError('Model integrity')
    expected_tokenizer=next(f for f in json.loads((ROOT/'assets/models/manifest.json').read_text())['files'] if f['relativePath']=='tokenizer.json')
    if sha(tokenizer)!=expected_tokenizer['sha256']:raise ValueError('Tokenizer integrity')
    config=ref.yaml.safe_load(config_path.read_text(encoding='utf-8'))
    config['weights_path']=str((directory/'model.safetensors').resolve())
    config['weights_path_without_voice_cloning']=None
    config['flow_lm']['lookup_table']['tokenizer_path']=str(tokenizer.resolve())
    args.output.mkdir(exist_ok=False)
    local=args.output/'local-config.yaml';local.write_text(ref.yaml.safe_dump(config),encoding='utf-8')
    report={'candidate':args.candidate,'corpusSha256':plan['corpusSha256'],
            'status':'initializing','takeNumber':args.take,'inputSha256':sha(args.plan),
            'scriptSha256':sha(__file__),'officialConfigSha256':sha(config_path),
            'files':{e['relativePath']:e['sha256'] for e in entries},
            'versions':{name:importlib.metadata.version(name) for name in ('pocket-tts','torch','numpy','tokenizers')},
            'parameters':{'temperature':0.3,'samplerDecodeSteps':1,'eosThreshold':-4,'maxTokens':50,'threads':1},
            'networkBlocked':True,'sameNoiseAsAndroid':False,'postprocessing':'raw clips concatenated; no terminal padding',
            'listening':'not_evaluated','segments':[],'paragraphs':[]}
    index=args.output/'index.json';dump(index,report)
    try:
        ref.torch.set_num_threads(1)
        model=ref.TTSModel.load_model(config=local,temp=.3,sampler_decode_steps=1,eos_threshold=-4)
        voice=model.get_state_for_audio_prompt(directory/'estelle.safetensors')
        report['status']='generating';dump(index,report)
        for number,p in enumerate(plan['paragraphs'],1):
            if args.take!=1 and number not in (1,5,10,15,20):continue
            frames=[]
            for s in p['segments']:
                text=s['synthesisText']
                prepared,_=ref.prepare_text_prompt(text,False,True,replace_characters=config['replace_characters'])
                if prepared!=text:raise ValueError('Official preparation differs')
                tokens=model.flow_lm.conditioner.prepare(prepared).reshape(-1).tolist()
                if not 1<=len(tokens)<=50:raise ValueError('Token budget')
                target=args.output/(s['id']+'.wav')
                if target.exists():raise ValueError('Existing take must not be overwritten')
                seed=7100+100*number+args.take
                attempt={'id':s['id'],'paragraphId':p['corpusId'],'seed':seed,'status':'generating',
                         'sourceTextSha256':hashlib.sha256(s['sourceText'].encode()).hexdigest(),
                         'synthesisTextSha256':hashlib.sha256(text.encode()).hexdigest(),'tokens':len(tokens)}
                report['segments'].append(attempt);dump(index,report)
                ref.torch.manual_seed(seed);start=time.monotonic()
                with ref.torch.no_grad():audio=model.generate_audio(voice,text,max_tokens=50).numpy().reshape(-1)
                if model.sample_rate!=24000 or not 0<audio.size<=480000 or not ref.np.isfinite(audio).all() or not ref.np.any(audio):raise ValueError('PCM bounds')
                pcm=(ref.np.clip(audio,-1,1)*32767).astype('<i2').tobytes()
                with target.open('xb') as f:
                    with wave.open(f,'wb') as wav:
                        wav.setparams((1,2,24000,0,'NONE','not compressed'));wav.writeframes(pcm)
                frames.append(pcm)
                attempt.update(status='generated',wav=target.name,sha256=sha(target),generationSeconds=time.monotonic()-start,samples=int(audio.size))
                dump(index,report)
            output=args.output/(p['corpusId']+f'-T{args.take:02d}.wav')
            if sum(map(len,frames))>24000*2*300:raise ValueError('Paragraph duration bound')
            with output.open('xb') as f:
                with wave.open(f,'wb') as wav:
                    wav.setparams((1,2,24000,0,'NONE','not compressed'));wav.writeframes(b''.join(frames))
            report['paragraphs'].append({'paragraphId':p['corpusId'],'takeNumber':args.take,'wav':output.name,'sha256':sha(output),'samples':sum(map(len,frames))//2})
            dump(index,report);print('Generated '+p['corpusId'],flush=True)
        report['status']='generated_listening_pending'
    except BaseException as error:
        report['status']='failed';report['failureType']=type(error).__name__
        raise
    finally:dump(index,report)


if __name__=='__main__':main()
