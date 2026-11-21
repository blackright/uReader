"""Local bounded tokenizer RPC for freezing the lab corpus; no model download."""
import hashlib,json,sys
from pathlib import Path
from tokenizers import Tokenizer
root=Path(__file__).resolve().parents[3]
path=root/'validation/private/aligned-bundle-01/tokenizer.json'
manifest=json.loads((root/'assets/models/manifest.json').read_text(encoding='utf-8'))
expected=next(f['sha256'] for f in manifest['files'] if f['relativePath']=='tokenizer.json')
assert hashlib.sha256(path.read_bytes()).hexdigest()==expected
tokenizer=Tokenizer.from_file(str(path))
for line in sys.stdin:
 text=json.loads(line)
 if not isinstance(text,str) or len(text)>65536: raise ValueError('Text bounds')
 print(json.dumps({'count':len(tokenizer.encode(text,add_special_tokens=False).ids)}),flush=True)
