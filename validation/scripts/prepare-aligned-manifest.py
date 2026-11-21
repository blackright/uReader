"""Promote reviewed aligned fingerprints to the embedded manifest, keeping G0 locked."""
import hashlib
import importlib.util
import json
from pathlib import Path

import onnx


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parents[2]
    path = root / 'assets/models/manifest.json'
    snapshot = root / 'validation/reports/g0/product-manifest-before-aligned-bundle-01.json'
    if snapshot.exists():
        raise ValueError('Manifest promotion already recorded; preserve the existing snapshot')
    manifest = json.loads(path.read_text(encoding='utf-8'))
    aligned = json.loads((root / 'validation/reference-3.3-aligned-lock.json').read_text(encoding='utf-8'))
    bundle = root / 'validation/private/aligned-bundle-01'
    audit = json.loads((bundle / 'audit-lock.json').read_text(encoding='utf-8'))
    protocol = json.loads((bundle / 'manifest.json').read_text(encoding='utf-8'))
    spec = importlib.util.spec_from_file_location('inspection', Path(__file__).with_name('inspect-onnx.py'))
    inspection = importlib.util.module_from_spec(spec); spec.loader.exec_module(inspection)
    verifier_spec = importlib.util.spec_from_file_location('files', Path(__file__).with_name('verify-model-files.py'))
    verifier = importlib.util.module_from_spec(verifier_spec); verifier_spec.loader.exec_module(verifier)
    if verifier.verify(bundle, audit['files']):
        raise ValueError('Aligned bundle integrity failed')
    if audit['sourceSelection'] != 'official_3.3_default_aligned' or audit['expectedVoiceOffset'] != 168:
        raise ValueError('Wrong candidate')
    if not (root / 'validation/reports/g0/aligned-license-metadata-01.json').exists():
        raise ValueError('Pinned licence metadata evidence required')
    revision = 'sha256-' + hashlib.sha256(json.dumps(audit['recipe'], sort_keys=True).encode()).hexdigest()
    manifest['bundleId'] = 'fr-official-aligned'
    manifest['bundleVersion'] = '1.0.0-g0'
    manifest['activationGate'] = {'requiresPositiveG0': True, 'g0Verdict': 'not_demonstrated'}
    source = manifest['sourceRevisions']
    source['weightsSha256'] = aligned['downloadFiles'][0]['sha256']
    source['voiceSha256'] = aligned['downloadFiles'][1]['sha256']
    source['sourceUris']['weights'] = aligned['downloadFiles'][0]['url']
    source['sourceUris']['voice'] = aligned['downloadFiles'][1]['url']
    source['exportRecipe'] = audit['recipe']
    source['alignedAuditSha256'] = sha(bundle / 'audit-lock.json')
    manifest['voice']['provenance'] = aligned['downloadFiles'][1]['url']
    role_names = {e['relativePath']: e['role'] for e in manifest['files']}
    manifest['files'] = [{'role': role_names[e['name']], 'relativePath': e['name'],
        'byteSize': e['byteSize'], 'sha256': e['sha256'],
        'delivery': {'kind': 'local_g0_derivation', 'recipeRevision': revision}} for e in audit['files']]
    for role, name in [('main', 'flow_lm_main_int8.onnx'), ('flow', 'flow_lm_flow_int8.onnx'), ('decoder', 'mimi_decoder_int8.onnx')]:
        graph = onnx.load(str(bundle / name), load_external_data=False)
        if any(t.data_location == onnx.TensorProto.EXTERNAL for t in graph.graph.initializer):
            raise ValueError('External weights refused')
        onnx.checker.check_model(graph)
        manifest['tensorProtocol']['graphs'][role] = {
            'opsets': [{'domain': o.domain, 'version': o.version} for o in graph.opset_import],
            'inputs': [inspection.describe(v) for v in graph.graph.input],
            'outputs': [inspection.describe(v) for v in graph.graph.output]}
    manifest['tensorProtocol']['voiceOffsets'] = protocol['voices']['estelle']['offsets']
    normalizer = root / 'lib/features/listening/french_text_normalizer.dart'
    manifest['textPreparation'] = {'version': 'fr-numbers-v2',
        'sourcePath': normalizer.relative_to(root).as_posix(), 'sourceSha256': sha(normalizer),
        'sourceOffsets': 'UTF-16', 'segmentAfterNormalization': True,
        'status': 'isolated_tested_not_wired', 'knownLimitations': ['feminine_noun_agreement_not_implemented']}
    manifest['runtimeCompatibility']['expectedVoiceOffset'] = 168
    manifest['limits']['maxBundleBytes'] = sum(e['byteSize'] for e in audit['files'])
    manifest['limits']['inputScope'] = 'Each native request after normalization and segmentation'
    notices = [n for n in manifest['licenseNotices'] if n['component'] in ['Official Pocket TTS code', 'ONNX Runtime Android 1.25.0']]
    for index, component in [(0, 'French weights, tokenizer, locally derived ONNX and FP16 embeddings'),
                             (1, 'Fixed Estelle state and locally derived FP16 voice cache')]:
        revision_id = aligned['downloadFiles'][index]['url'].split('/resolve/')[1].split('/')[0]
        notices.append({'component': component, 'license': 'CC-BY-4.0',
            'attribution': 'Kyutai; local ONNX export, INT8 quantization and FP16 conversion for uReader',
            'source': 'https://huggingface.co/kyutai/pocket-tts-without-voice-cloning/tree/' + revision_id})
    manifest['licenseNotices'] = notices
    manifest['evidence'] = {'repeatedExports': 'aligned-export-reproducibility-01.json',
        'nativeGeneration': 'aligned-android-01-cases.json', 'cancellation': 'aligned-android-01-cancellation.json',
        'memoryCycles': 'aligned-cycles-01-memory.json', 'licenceMetadata': 'aligned-license-metadata-01.json'}
    # Validate the candidate document before replacing the embedded file.
    candidate = root / 'validation/private/aligned-bundle-01/product-manifest-reviewed.json'
    with candidate.open('x', encoding='utf-8') as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2); handle.write('\n')
    product_spec = importlib.util.spec_from_file_location('product', Path(__file__).with_name('verify-product-manifest.py'))
    product = importlib.util.module_from_spec(product_spec); product_spec.loader.exec_module(product)
    product.verify(bundle, candidate)
    snapshot.write_bytes(path.read_bytes())
    path.write_bytes(candidate.read_bytes())
    print(json.dumps(product.verify(bundle)))


if __name__ == '__main__':
    main()
