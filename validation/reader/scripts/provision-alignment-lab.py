"""Provision verified copies only to a fresh private debug laboratory, via USB."""
import hashlib, json, os, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[3]
adb=[str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe'),'-s','2291940c08037ece']
probe=root/'validation/reader/private/attention-probe-03'
product=json.loads((root/'assets/models/manifest.json').read_text(encoding='utf-8'))
baseline={e['relativePath']:{'byteSize':e['byteSize'],'sha256':e['sha256']} for e in product['files']}
candidate=json.loads((probe/'bundle-trust.json').read_text(encoding='utf-8'))
assert set(baseline)==set(candidate) and len(baseline)==7
files=[]
for name,directory,trust in [('baseline',root/'validation/private/aligned-bundle-01',baseline),('candidate',probe/'android-bundle',candidate)]:
    for filename,entry in trust.items():
        assert Path(filename).name==filename
        file=directory/filename
        assert file.stat().st_size==entry['byteSize']
        with file.open('rb') as input: assert hashlib.file_digest(input,'sha256').hexdigest()==entry['sha256']
        files.append((name+'/'+filename,file))
base_path='files/ureader-alignment-lab'
subprocess.run(adb+['shell',"run-as com.ureader.prototype sh -c 'test ! -e "+base_path+" && mkdir -p "+base_path+"/baseline "+base_path+"/candidate'"],check=True,timeout=20)
for name,file in files:
    if file.stat().st_size>128*1024*1024: raise ValueError('Transfer file limit')
    target=base_path+'/'+name
    subprocess.run(adb+['exec-in',"run-as com.ureader.prototype sh -c 'test ! -e "+target+" && cat > "+target+"'"],input=file.read_bytes(),check=True,timeout=120)
    actual=subprocess.check_output(adb+['shell','run-as','com.ureader.prototype','sha256sum',target],timeout=30).decode().split()[0]
    expected=(baseline if name.startswith('baseline/') else candidate)[Path(name).name]['sha256']
    if actual!=expected: raise ValueError('USB transfer hash mismatch')
encoded=json.dumps({'baseline':baseline,'candidate':candidate}).encode()
subprocess.run(adb+['exec-in',"run-as com.ureader.prototype sh -c 'cat > "+base_path+"/experiment.json'"],input=encoded,check=True,timeout=20)
actual=subprocess.check_output(adb+['shell','run-as','com.ureader.prototype','sha256sum',base_path+'/experiment.json'],timeout=20).decode().split()[0]
assert actual==hashlib.sha256(encoded).hexdigest()
print(json.dumps({'status':'provisioned_and_verified','files':len(files),'productRootModified':False}))
