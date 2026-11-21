"""Freeze text/token coordinates for the existing one-excerpt Android pre-bench. No timings."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
from tokenizers import Tokenizer
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',type=Path,required=True);parser.add_argument('--provision',action='store_true')
args=parser.parse_args();directory=args.directory.resolve()
if not directory.is_relative_to((root/'validation/reader/private').resolve()):raise ValueError('Private laboratory directory required')
report=json.loads((directory/'result.json').read_text(encoding='utf-8'))
attention=json.loads((directory/'attention.json').read_text(encoding='utf-8'))
assert report['androidExecuted'] and report['pcmBytesIdentical']
candidate=next(r for r in report['runs'] if r['kind']=='candidate')
assert hashlib.sha256((directory/'candidate.wav').read_bytes()).hexdigest()==candidate['wavSha256']
text='Chaque matin, Léa ouvre la petite porte du jardin.'
manifest=json.loads((root/'assets/models/manifest.json').read_text(encoding='utf-8'))
tokenizer=root/'validation/private/aligned-bundle-01/tokenizer.json'
assert hashlib.sha256(tokenizer.read_bytes()).hexdigest()==next(e['sha256'] for e in manifest['files'] if e['relativePath']=='tokenizer.json')
encoded=Tokenizer.from_file(str(tokenizer)).encode(text,add_special_tokens=False)
assert encoded.ids==attention['tokenIds']
utf16=lambda value:len(value.encode('utf-16-le'))//2
metadata={'source':text,'prepared':text,'sourceSha256':hashlib.sha256(text.encode()).hexdigest(),'preparedSha256':hashlib.sha256(text.encode()).hexdigest(),'tokenIds':encoded.ids,'tokenOffsets':[[utf16(text[:a]),utf16(text[:b])] for a,b in encoded.offsets],'status':'experimental_unqualified'}
raw=json.dumps(metadata,ensure_ascii=False).encode('utf-8');output=directory/'fixture.json'
if output.exists():assert output.read_bytes()==raw
else:output.write_bytes(raw)
if args.provision:
 adb=[str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe'),'-s','2291940c08037ece']
 target='files/ureader-alignment-lab/fixture.json'
 previous=subprocess.run(adb+['exec-out','run-as','com.ureader.prototype','cat',target],capture_output=True)
 if previous.returncode==0:assert previous.stdout==raw
 else:subprocess.run(adb+['exec-in',"run-as com.ureader.prototype sh -c 'test ! -e "+target+" && cat > "+target+"'"],input=raw,check=True)
print(json.dumps({'status':'coordinates_verified','timingsImported':False,'g1':'not_evaluated','sha256':hashlib.sha256(raw).hexdigest()}))
