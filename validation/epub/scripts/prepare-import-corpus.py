"""Export only hash-verified owned synthetic fixtures for injected importer tests.
No personal books. No Android SAF or native ZIP success inferred from this export.
"""
from pathlib import Path
import base64, hashlib, json, zipfile

root=Path(__file__).resolve().parents[3]
lab=root/'validation/epub'
manifest=json.loads((lab/'corpus-manifest.json').read_text(encoding='utf-8'))
books=[]
for row in manifest['books']:
    source=(lab/row['path']).read_bytes()
    if hashlib.sha256(source).hexdigest()!=row['sha256']:
        raise ValueError('Synthetic fixture hash mismatch')
    with zipfile.ZipFile(lab/row['path']) as archive:
        books.append({'id':row['id'],'sourceSha':row['sha256'],
          'entries':{name:base64.b64encode(archive.read(name)).decode() for name in archive.namelist()},
          'reference':row,'source':base64.b64encode(source).decode()})
data=(json.dumps({'rights':manifest['rights'],'books':books},ensure_ascii=False,indent=2)+'\n').encode()
output=root/'test/fixtures/epub_packages.json'
output.parent.mkdir(parents=True,exist_ok=True)
if output.exists() and output.read_text(encoding='utf-8')!=data.decode('utf-8'):
    raise ValueError('Refusing to replace a different corpus export')
output.write_bytes(data)
print(json.dumps({'books':len(books),'sha256':hashlib.sha256(data).hexdigest()}))
