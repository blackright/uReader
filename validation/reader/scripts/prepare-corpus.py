"""Build deterministic owned reader fixtures; never extract or use personal books."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import zipfile
import io
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / 'validation/reader'
EPUB = ROOT / 'validation/epub'

def sha(data): return hashlib.sha256(data).hexdigest()

def keep(path, data, verify):
    if path.exists():
        if path.read_bytes() != data: raise ValueError('Existing generated artifact differs: ' + path.name)
    elif verify:
        raise ValueError('Missing generated artifact: ' + path.name)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

def generate(verify=False):
    definition = importlib.util.spec_from_file_location('epub_fixtures', EPUB / 'scripts/generate-fixtures.py')
    generator = importlib.util.module_from_spec(definition)
    definition.loader.exec_module(generator)
    original = json.loads((EPUB / 'corpus-manifest.json').read_text(encoding='utf-8'))
    books = []
    for book in original['books']:
        path = (EPUB / book['path']).resolve()
        if not path.is_relative_to((EPUB / 'private').resolve()): raise ValueError('Unexpected corpus path')
        data = path.read_bytes()
        if sha(data) != book['sha256']: raise ValueError('Original corpus mismatch')
        books.append({k:book[k] for k in ('id','epubVersion','language','sha256','bytes','referenceSha256')})
        books[-1]['path'] = path.relative_to(ROOT).as_posix()
    paragraph = ('Léa regarde le jardin, puis suit le chemin éclairé. Émilie dit : « Bonjour ! » '+
                 'Une ligature : œ ; un accent décomposé : e\u0301 ; un sourire : 😀. ') * 140
    units = len(paragraph.encode('utf-16-le')) // 2
    assert units > 8192
    base, _ = generator.make_book(1)
    entries = [(name, data.encode('utf-8') if isinstance(data, str) else data) for name, data in base]
    changed = []
    for name, data in entries:
        if name == 'OEBPS/chapter1.xhtml':
            text = data.decode('utf-8').replace('</body>', '<p id="reader-long-paragraph">'+escape(paragraph)+'</p></body>')
            data = text.encode('utf-8')
        changed.append((name,data))
    long_epub = generator.archive(changed)
    long_path = LAB / 'private/corpus/reader-long-paragraph.epub'
    keep(long_path, long_epub, verify)
    reference = LAB / 'private/corpus/reader-long-paragraph.txt'
    keep(reference, paragraph.encode('utf-8'), verify)
    # 60 short, authored paragraphs: >500 source words, with expansions for future audio recipe.
    samples = [
      'Chaque matin, Léa ouvre la petite porte du jardin et écoute les oiseaux.',
      'À Noël, Émilie prépare une crème brûlée, puis elle appelle ses amis.',
      'Le 12 avril 2026, à 9 h 30, nous achetons 3 pommes et 250 grammes de fromage.',
      'Le 29 février 2024, à 23 h 45, la promenade se termine près du village.',
      'Voici 21 pommes et 80 poires ; demain, nous partagerons ces fruits avec les voisins.',
      '« Bonjour ! » demande Léa. Pourquoi partir maintenant ? Elle attend, puis elle sourit.'
    ]
    paragraphs = [samples[i % len(samples)] for i in range(60)]
    timing = '\n\n'.join(paragraphs) + '\n'
    count = len(re.findall(r"[^\W_]+(?:[’'-][^\W_]+)*", timing, re.UNICODE))
    assert count >= 500
    timing_path = LAB / 'private/corpus/word-timing-source.txt'
    keep(timing_path, timing.encode('utf-8'), verify)
    annotations = LAB / 'private/corpus/word-timing-annotations.json'
    # No invented alignments/annotations: preparation defines references, not G1 results.
    metadata = {'schemaVersion':1,'rights':'CC0-1.0, authored synthetic uReader content',
      'sourceSha256':sha(timing.encode('utf-8')),'paragraphs':len(paragraphs),
      'sourceLexicalTokens':count,'spokenWordCount':None,'timingAnnotationsStatus':'not_evaluated',
      'units':[],'note':'Freeze source/prepared map and human annotations before scoring; empty units are not valid G1 evidence.'}
    keep(annotations,(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),verify)
    manifest = {'schemaVersion':1,'date':'2026-11-18','rights':'CC0-1.0; synthetic owned fixtures only',
      'rightsReference':'validation/epub/corpus-manifest.json','books':books,
      'additionalFixtures':[{'id':'reader-long-paragraph','path':long_path.relative_to(ROOT).as_posix(),
        'sha256':sha(long_epub),'referencePath':reference.relative_to(ROOT).as_posix(),
        'referenceSha256':sha(paragraph.encode('utf-8')),'paragraphUtf16Units':units}],
      'timingCorpus':{'path':timing_path.relative_to(ROOT).as_posix(),'sha256':sha(timing.encode('utf-8')),
        'sourceLexicalTokens':count,'paragraphs':60,'spokenWordCount':None,
        'annotationsPath':annotations.relative_to(ROOT).as_posix(),'annotationsStatus':'not_evaluated'},
      'runtimeReaderResult':'not_evaluated','runtimeTimingResult':'not_evaluated'}
    keep(LAB / 'corpus.json',(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),verify)
    return {'booksVerified':len(books),'longParagraphUtf16Units':units,'sourceLexicalTokens':count,
            'exactGenerationVerified':verify,'g1':'not_evaluated'}

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify',action='store_true')
    print(json.dumps(generate(parser.parse_args().verify)))
