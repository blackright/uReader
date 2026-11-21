"""Private per-channel/reduced-range quantization experiment; never updates the product manifest."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import onnx
import onnxruntime as ort
from onnxruntime.quantization import QuantType, quantize_dynamic


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root=Path(__file__).resolve().parents[2]
    output=root/'validation/private/precision-perchannel-01'
    output.mkdir(exist_ok=False)
    (output/'scratch').mkdir();tempfile.tempdir=str(output/'scratch')
    ort.disable_telemetry_events()
    if ort.__version__!='1.25.0':raise ValueError('Pinned quantizer version required')
    selection=[('main','repro-main-03','flow_lm_main_int8.onnx'),('flow','repro-flow-03','flow_lm_flow_int8.onnx'),('mimi','repro-mimi-04','mimi_decoder_int8.onnx')]
    recipe={'quantizerVersion':ort.__version__,'perChannel':True,'reduceRange':True,'weightType':'QInt8','sources':{},'scope':'Diagnostic only, no product activation'}
    for role,folder,target in selection:
        source_root=root/'validation/private'/folder
        result=json.loads((source_root/'result.json').read_text())
        entry=next(e for e in result['files'] if e['name']==f'{role}-official-fp32.onnx')
        source=source_root/entry['name']
        if sha(source)!=entry['sha256']:raise ValueError('FP32 source integrity mismatch')
        recipe['sources'][role]=entry['sha256']
        quantize_dynamic(str(source),str(output/target),weight_type=QuantType.QInt8,
                         per_channel=True,reduce_range=True,op_types_to_quantize=['MatMul','Gemm'])
        onnx.checker.check_model(str(output/target))
    current=root/'validation/private/repro-bundle-01'
    current_audit=json.loads((current/'audit-lock.json').read_text())
    for name in ['text_embeddings.f16','tokenizer.json','voices/estelle.f16']:
        entry=next(e for e in current_audit['downloadFiles'] if e['relativePath']==name)
        if sha(current/name)!=entry['sha256']:raise ValueError('Shared data integrity mismatch')
        (output/name).parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(current/name,output/name)
    protocol=json.loads((current/'manifest.json').read_text());protocol['precisionProbe']=recipe
    (output/'manifest.json').write_text(json.dumps(protocol,ensure_ascii=True,indent=2),encoding='utf-8')
    names=[target for _,_,target in selection]+['text_embeddings.f16','tokenizer.json','voices/estelle.f16','manifest.json']
    files=[{'relativePath':name,'name':Path(name).name,'byteSize':(output/name).stat().st_size,'sha256':sha(output/name)} for name in names]
    revision='sha256-'+hashlib.sha256(json.dumps(recipe,sort_keys=True).encode()).hexdigest()
    audit={'candidate':{'revision':revision},'downloadFiles':files,'recipe':recipe,'g0':'not_demonstrated'}
    (output/'audit-lock.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
    (output/'reexport-generation-files.json').write_text(json.dumps({'files':files,'scope':'Private precision probe'},indent=2),encoding='utf-8')
    cases=json.loads((root/'validation/private/android-runtime/g0-cases-01.json').read_text())
    case=next(c for c in cases['cases'] if c['id']=='fr-05-p1')
    (output/'generation-fixtures.json').write_text(json.dumps({**case,'noise':cases['noise']},ensure_ascii=True),encoding='utf-8')
    adb=Path(os.environ['LOCALAPPDATA'])/'Android/SDK/platform-tools/adb.exe'
    command=[str(adb),'-d'];remote='files/ureader-precision-probe/'
    subprocess.run(command+['shell','run-as','com.ureader.prototype','mkdir','-p',remote],check=True,timeout=15)
    for source in [*(output/name for name in names),output/'reexport-generation-files.json',output/'generation-fixtures.json']:
        with source.open('rb') as stream:
            subprocess.run(command+['exec-in',"run-as com.ureader.prototype sh -c 'cat > "+remote+source.name+"'"],stdin=stream,check=True,timeout=90)
        actual=subprocess.check_output(command+['shell','run-as','com.ureader.prototype','sha256sum',remote+source.name],timeout=30).decode().split()[0]
        if actual!=sha(source):raise ValueError('Diagnostic transfer integrity failed')
    report={'recipe':recipe,'files':files,'productManifestChanged':False,'g0':'not_demonstrated'}
    with (root/'validation/reports/g0/precision-probe-build-01.json').open('x',encoding='utf-8') as f:json.dump(report,f,indent=2);f.write('\n')
    print('Private per-channel reduced-range candidate built and USB-verified; no product activation.')


if __name__=='__main__':main()
