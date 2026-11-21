"""Offline, exact-checkpoint attention probe. PC evidence only; never a G1 verdict."""
import argparse, copy, hashlib, importlib.metadata, importlib.resources, json, os
from pathlib import Path
import socket, threading, time, wave
os.environ.update(HF_HUB_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1', DO_NOT_TRACK='1', KPOCKET_TTS_ERROR_WITHOUT_EOS='1')
def offline(*args, **kwargs): raise RuntimeError('Network forbidden')
socket.socket.connect = socket.socket.connect_ex = socket.create_connection = socket.getaddrinfo = offline

def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()

def run(destination):
    import numpy as np
    import torch
    import torch.nn.functional as functional
    import yaml
    from pocket_tts import TTSModel
    from pocket_tts.modules.attention import StreamingMultiheadAttention
    from pocket_tts.models.text_chunking import prepare_text_prompt
    root = Path(__file__).resolve().parents[3]
    private = (root / 'validation/reader/private').resolve()
    destination = destination.resolve()
    if not destination.is_relative_to(private) or destination.exists(): raise ValueError('Fresh private output directory required')
    lock = json.loads((root/'validation/reference-3.3-aligned-lock.json').read_text(encoding='utf-8'))
    reference = root/lock['directory']
    for entry in lock['downloadFiles']:
        path=reference/entry['relativePath']
        if path.stat().st_size != entry['byteSize'] or sha(path) != entry['sha256']: raise ValueError('Reference hash mismatch')
    package=importlib.resources.files('pocket_tts')
    config_bytes=package.joinpath('config/french.yaml').read_bytes()
    if hashlib.sha256(config_bytes).hexdigest()!=lock['sourceEvidence']['frenchConfigSha256']: raise ValueError('Config mismatch')
    if importlib.metadata.version('pocket-tts')!='3.3.0': raise ValueError('Pinned official package required')
    tokenizer=root/'validation/private/models/fr-6l/tokenizer.json'
    original=json.loads((root/'validation/model-lock.json').read_text(encoding='utf-8'))
    expected=next(e for e in original['downloadFiles'] if e['relativePath']=='tokenizer.json')
    if sha(tokenizer)!=expected['sha256']: raise ValueError('Tokenizer mismatch')
    destination.mkdir(parents=True)
    config=yaml.safe_load(config_bytes)
    config['weights_path']=str((reference/'model.safetensors').resolve()); config['weights_path_without_voice_cloning']=None
    config['flow_lm']['lookup_table']['tokenizer_path']=str(tokenizer)
    local=destination/'local.yaml'; local.write_text(yaml.safe_dump(config),encoding='utf-8')
    torch.set_num_threads(1); torch.manual_seed(0)
    model=TTSModel.load_model(config=local,temp=.3,sampler_decode_steps=1,eos_threshold=-4)
    voice=model.get_state_for_audio_prompt(reference/'estelle.safetensors')
    text='Chaque matin, Léa ouvre la petite porte du jardin.'
    prepared,_=prepare_text_prompt(text,False,True,replace_characters=config['replace_characters'])
    layers=[(n,m) for n,m in model.flow_lm.named_modules() if isinstance(m,StreamingMultiheadAttention)]
    if len(layers)!=6 or layers[3][1].num_heads<=9: raise ValueError('Unexpected French architecture')
    target=layers[3][1]; active=threading.local(); rows=[]
    original_sdpa=functional.scaled_dot_product_attention
    def capture(q,k,v,attn_mask=None,dropout_p=0.,is_causal=False,**kwargs):
        output=original_sdpa(q,k,v,attn_mask=attn_mask,dropout_p=dropout_p,is_causal=is_causal,**kwargs)
        if getattr(active,'value',False) and q.shape[-2]==1:
            if len(rows)>=512 or k.shape[-2]>2048: raise ValueError('Attention budget exceeded')
            scores=(q[:,9:10,-1:].float() @ k[:,9:10].float().transpose(-1,-2))/(q.shape[-1]**.5)
            if attn_mask is not None:
                scores=scores.masked_fill(~attn_mask,float('-inf')) if attn_mask.dtype==torch.bool else scores+attn_mask
            rows.append(torch.softmax(scores,dim=-1).detach().cpu().numpy().reshape(-1))
        return output
    def begin(*args): active.value=True
    def end(*args): active.value=False
    def generate():
        torch.manual_seed(0); start=time.monotonic()
        with torch.no_grad(): pcm=model.generate_audio(copy.deepcopy(voice),text,max_tokens=50).numpy().reshape(-1)
        if not 0<pcm.size<=480000 or not np.isfinite(pcm).all(): raise ValueError('Invalid PCM')
        return pcm,time.monotonic()-start
    baseline,baseline_seconds=generate()
    handles=[target.register_forward_pre_hook(begin),target.register_forward_hook(end)]
    functional.scaled_dot_product_attention=capture
    try: candidate,candidate_seconds=generate()
    finally:
        functional.scaled_dot_product_attention=original_sdpa
        for handle in handles: handle.remove()
    same_length=baseline.shape==candidate.shape
    error=np.abs(baseline.astype(np.float64)-candidate.astype(np.float64)) if same_length else None
    parity=same_length and float(error.max())<=.0001 and float(np.sqrt(np.mean(error**2)))<=.00001
    for name,pcm in [('baseline',baseline),('attention',candidate)]:
        with wave.open(str(destination/(name+'.wav')),'wb') as output:
            output.setnchannels(1);output.setsampwidth(2);output.setframerate(model.sample_rate)
            output.writeframes((np.clip(pcm,-1,1)*32767).astype('<i2').tobytes())
    widths=[len(row) for row in rows]
    matrix=np.full((len(rows),max(widths,default=0)),np.nan,dtype=np.float32)
    for i,row in enumerate(rows): matrix[i,:len(row)]=row
    np.save(destination/'attention.npy',matrix,allow_pickle=False)
    report={'status':'exploratory_complete','androidExecuted':False,'g1':'not_evaluated',
      'method':'official-SDPA-output-unchanged; parallel QK softmax L3H9', 'attentionLayer':layers[3][0],
      'sourceSha256':hashlib.sha256(text.encode()).hexdigest(),'preparedSha256':hashlib.sha256(prepared.encode()).hexdigest(),
      'weightsSha256':sha(reference/'model.safetensors'),'voiceSha256':sha(reference/'estelle.safetensors'),
      'scriptSha256':sha(Path(__file__)), 'versions':{n:importlib.metadata.version(n) for n in ['pocket-tts','torch','numpy']},
      'seed':0,'sampleRate':model.sample_rate,'sampleCount':int(candidate.size),'attentionRows':len(rows),
      'baselineSeconds':baseline_seconds,'candidateSeconds':candidate_seconds,'parityPassed':bool(parity),
      'maxAbsError':None if error is None else float(error.max()),'rmse':None if error is None else float(np.sqrt(np.mean(error**2))),
      'cueStatus':'not_extracted','audibleTimingScore':'not_evaluated','networkBlocked':True,'productBundleModified':False}
    # Expose an existing Softmax from a private copy of the exact int8 graph.
    # No weight, node or computation is replaced. Only an extra graph output.
    import onnx, onnxruntime as ort, shutil
    ort.disable_telemetry_events()
    bundle=root/'validation/private/aligned-bundle-01'
    product=json.loads((root/'assets/models/manifest.json').read_text(encoding='utf-8'))
    target_bundle=destination/'android-bundle'; target_bundle.mkdir()
    trusted={}
    for entry in product['files']:
        source=bundle/entry['relativePath']
        if sha(source)!=entry['sha256'] or source.stat().st_size!=entry['byteSize']: raise ValueError('Product bundle mismatch')
        shutil.copyfile(source,target_bundle/entry['relativePath'])
    original_graph=bundle/'flow_lm_main_int8.onnx'; candidate_graph=target_bundle/original_graph.name
    graph=onnx.load(str(original_graph))
    node=next(n for n in graph.graph.node if n.name=='/transformer/layers.3/self_attn/Softmax')
    graph.graph.output.append(onnx.helper.make_tensor_value_info(node.output[0],onnx.TensorProto.FLOAT,[1,16,'query_length','total_length']))
    onnx.checker.check_model(graph); onnx.save(graph,str(candidate_graph))
    options=ort.SessionOptions();options.intra_op_num_threads=1;options.inter_op_num_threads=1
    options.graph_optimization_level=ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    original_session=ort.InferenceSession(str(original_graph),options,providers=['CPUExecutionProvider'])
    candidate_session=ort.InferenceSession(str(candidate_graph),options,providers=['CPUExecutionProvider'])
    feed={'sequence':np.full((1,1,32),np.nan,dtype=np.float32),'text_embeddings':np.zeros((1,0,1024),np.float32)}
    for i in range(6):
        feed['cache_'+str(i)]=np.zeros((2,1,168,16,64),np.float32)
        feed['offset_'+str(i)]=np.array([168],np.int64)
    original_values=original_session.run(None,feed); candidate_values=candidate_session.run(None,feed)
    graph_parity=all(np.array_equal(a,b) for a,b in zip(original_values,candidate_values[:-1]))
    if not graph_parity: raise ValueError('Auxiliary output changed baseline graph outputs')
    for entry in product['files']:
        path=target_bundle/entry['relativePath'];trusted[entry['relativePath']]={'byteSize':path.stat().st_size,'sha256':sha(path)}
    (destination/'bundle-trust.json').write_text(json.dumps(trusted,indent=2)+'\n',encoding='utf-8')
    report['int8AuxiliaryGraphParityPassed']=graph_parity
    report['int8AttentionShape']=list(candidate_values[-1].shape)
    report['experimentalMainSha256']=sha(candidate_graph)
    report['originalMainSha256']=sha(original_graph)
    (destination/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    run(parser.parse_args().output)
