"""Generate a Dart laboratory fixture from SHA-pinned, synthetic EPUB resources."""
from pathlib import Path
import base64
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / 'validation/epub'
if __name__ == '__main__':
    corpus = json.loads((LAB/'corpus-manifest.json').read_text(encoding='utf-8'))
    fragments = {}
    for index in [1, 3, 4, 6, 7, 8, 10]:
        book = corpus['books'][index-1]
        path = LAB/book['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == book['sha256']
        with zipfile.ZipFile(path) as archive:
            fragments[book['id']] = archive.read('OEBPS/chapter1.xhtml').decode()
            if 'OEBPS/cover.png' in archive.namelist():
                image = archive.read('OEBPS/cover.png')
    text = '// Generated synthetic fixtures only. Regenerate with prepare-projection-gate.py.\n'
    text += 'const gateFragments = <String,String>' + json.dumps(fragments,ensure_ascii=False,indent=2).replace('$',r'\$') + ';\n'
    text += 'const gatePngBase64 = ' + json.dumps(base64.b64encode(image).decode()) + ';\n'
    destination = ROOT/'integration_test/epub_gate_resources.dart'
    if destination.exists() and destination.read_text(encoding='utf-8') != text:
        raise ValueError('Preserve changed generated Dart fixture')
    destination.write_text(text,encoding='utf-8')
    (LAB/'reports/projection-fixture-preparation.json').write_text(json.dumps({'sourceCorpus':'corpus-manifest.json','fragmentIds':list(fragments),'generatedSha256':hashlib.sha256(text.encode()).hexdigest(),'personalContent':False},indent=2)+'\n')
    print(json.dumps({'syntheticResources':len(fragments)}))
