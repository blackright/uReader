"""Prepare private P05 inference probes and all 54 frozen frontend parity cases."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    private = (ROOT / 'validation/reader/private').resolve()
    if any(not p.resolve().is_relative_to(private) for p in (args.export, args.output)):
        raise ValueError('Private paths required')
    report = json.loads((args.export / 'export-report.json').read_text(encoding='utf-8'))
    if report['status'] != 'exported_pc_probes_passed':
        raise ValueError('Verified export required')
    campaign = private / 'french-narration-20261125-phase3'
    plan = json.loads((campaign / 'plan.json').read_text(encoding='utf-8'))
    baseline = json.loads((campaign / 'kokoro-siwis-T01/index.json').read_text(encoding='utf-8'))
    module = importlib.util.spec_from_file_location('patches', Path(__file__).with_name('kokoro-minimal-patches.py'))
    patches = importlib.util.module_from_spec(module)
    module.loader.exec_module(patches)
    originals = {row['id']: row for row in baseline['segments']}
    frontend = []
    for paragraph in plan['paragraphs']:
        for segment in paragraph['segments']:
            old = originals[segment['id']]
            text = segment['synthesisText']
            if hashlib.sha256(text.encode()).hexdigest() != old['synthesisTextSha256']:
                raise ValueError('Changed frozen input')
            change = patches.patch(text, old['phonemes'])
            frontend.append({'id': segment['id'], 'paragraphId': paragraph['corpusId'],
                             'synthesisText': text, 'originalPhonemes': old['phonemes'],
                             'phonemes': change['phonemes']})
    files = []
    for name in ('kokoro.onnx', 'siwis.f32', 'vocab.json'):
        path = args.export / name
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        files.append({'relativePath': name, 'byteSize': path.stat().st_size, 'sha256': digest})
    if files[0]['sha256'] != report['modelSha256']:
        raise ValueError('Export model changed')
    data = {'corpusSha256': plan['corpusSha256'], 'files': files, 'threads': 4,
            'cases': [row for row in frontend if row['paragraphId'] == 'P05'],
            'frontendCases': frontend}
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(data, stream, ensure_ascii=True, indent=2)
        stream.write('\n')
    print(f"Prepared {len(data['cases'])} inference probes and {len(frontend)} frontend parity cases; private text omitted")


if __name__ == '__main__':
    main()
