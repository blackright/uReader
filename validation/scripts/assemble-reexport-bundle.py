"""Assemble an explicit local G0 candidate; never creates an activatable product manifest."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output, precision='int8'):
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / 'validation/model-lock.json').read_text(encoding='utf-8'))
    old = root / 'validation/private/models/fr-6l'
    spec = importlib.util.spec_from_file_location('verifier', Path(__file__).with_name('verify-model-files.py'))
    verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
    errors = verifier.verify(old, lock['downloadFiles'])
    if errors:
        raise ValueError('; '.join(errors))
    comparison = json.loads((root / 'validation/reports/g0/official-reference-01.json').read_text())
    if not all(comparison[key] for key in ['fp16EmbeddingTableMatchesOfficial', 'fp16VoiceMatchesOfficial', 'tokenIdsMatchOnnx']):
        raise ValueError('Official source comparison missing')
    selection = [('main', 'repro-main-03', f'flow_lm_main_{precision}.onnx'),
                 ('flow', 'repro-flow-03', f'flow_lm_flow_{precision}.onnx'),
                 ('mimi', 'repro-mimi-04', f'mimi_decoder_{precision}.onnx')]
    exports = {}
    for role, folder, _ in selection:
        report = json.loads((root / 'validation/private' / folder / 'result.json').read_text())
        if report['g0'] != 'not_demonstrated' or 'passed' not in report['status']:
            raise ValueError('Unvalidated export')
        exports[role] = report
        entry = next(e for e in report['files'] if e['name'] == f'{role}-official-{precision}.onnx')
        source = root / 'validation/private' / folder / entry['name']
        if source.stat().st_size != entry['byteSize'] or sha(source) != entry['sha256']:
            raise ValueError('Reexport integrity failure')
    output.mkdir(parents=True, exist_ok=False)
    for role, folder, target in selection:
        shutil.copyfile(root / 'validation/private' / folder / f'{role}-official-{precision}.onnx', output / target)
    for name in ['text_embeddings.f16', 'tokenizer.json', 'voices/estelle.f16']:
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(old / name, target)
    recipe = {'officialCodeRevision': lock['officialReference']['codeRevision'],
              'exportScriptDigests': {role: report['scriptSha256'] for role, report in exports.items()},
              'exportedGraphDigests': {role: next(e['sha256'] for e in report['files'] if f'-{precision}.' in e['name'])
                                      for role, report in exports.items()},
              'precision': precision,
              'scope': 'Local G0 derivation only; not a product trust root'}
    revision = 'sha256-' + hashlib.sha256(json.dumps(recipe, sort_keys=True).encode()).hexdigest()
    protocol = json.loads((old / 'manifest.json').read_text(encoding='utf-8'))
    protocol['models'] = {role: target for role, (_, _, target) in zip(['flow_lm_main', 'flow_lm_flow', 'mimi_decoder'], selection)}
    protocol['localExport'] = recipe
    (output / 'manifest.json').write_text(json.dumps(protocol, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
    files = []
    for name in [target for _, _, target in selection] + ['text_embeddings.f16', 'tokenizer.json', 'voices/estelle.f16', 'manifest.json']:
        path = output / name
        files.append({'relativePath': name, 'byteSize': path.stat().st_size, 'sha256': sha(path)})
    audit = {'candidate': {'revision': revision}, 'downloadFiles': files,
             'delivery': 'explicit_local_validation_only_no_download_urls', 'recipe': recipe,
             'productTrustManifest': False, 'g0': 'not_demonstrated'}
    (output / 'audit-lock.json').write_text(json.dumps(audit, indent=2) + '\n', encoding='utf-8')
    if verifier.verify(output, files):
        raise ValueError('Assembled bundle integrity failure')
    print(json.dumps({'files': len(files), 'totalBytes': sum(e['byteSize'] for e in files),
                      'revision': revision, 'productActivated': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-directory', required=True, type=Path)
    parser.add_argument('--precision', choices=['int8', 'fp32'], default='int8')
    args = parser.parse_args()
    main(args.output_directory, args.precision)
