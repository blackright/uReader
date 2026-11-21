"""Check the real product manifest against local derivation and current Kotlin sources."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def aligned_metadata(manifest, audit, bundle, root):
    if audit.get('sourceSelection') != 'official_3.3_default_aligned':
        return
    aligned = json.loads((root / 'validation/reference-3.3-aligned-lock.json').read_text(encoding='utf-8'))
    weights, voice = aligned['downloadFiles']
    revisions = manifest['sourceRevisions']
    if revisions['weightsSha256'] != weights['sha256'] or revisions['voiceSha256'] != voice['sha256']:
        raise ValueError('Aligned source fingerprint mismatch')
    if revisions['sourceUris']['weights'] != weights['url'] or revisions['sourceUris']['voice'] != voice['url']:
        raise ValueError('Aligned source URI mismatch')
    if manifest['voice']['provenance'] != voice['url'] or manifest['voice']['language'] != 'fr':
        raise ValueError('Aligned voice provenance mismatch')
    protocol = json.loads((bundle / 'manifest.json').read_text(encoding='utf-8'))
    offsets = protocol['voices']['estelle']['offsets']
    if offsets != [168] * 6 or manifest['tensorProtocol']['voiceOffsets'] != offsets:
        raise ValueError('Aligned voice protocol mismatch')
    if manifest['runtimeCompatibility']['expectedVoiceOffset'] != 168:
        raise ValueError('Aligned host configuration mismatch')
    if manifest['limits']['maxBundleBytes'] != sum(e['byteSize'] for e in audit['files']):
        raise ValueError('Aligned bundle size limit mismatch')
    preparation = manifest['textPreparation']
    source = root / 'lib/features/listening/french_text_normalizer.dart'
    version = re.search(r"static const version = '([^']+)'", source.read_text(encoding='utf-8')).group(1)
    if preparation['version'] != version or preparation['sourcePath'] != source.relative_to(root).as_posix() or preparation['sourceSha256'] != digest(source):
        raise ValueError('Text preparation fingerprint mismatch')
    if version == 'fr-numbers-v3':
        policy = preparation['punctuationAudio']
        if policy['version'] != 'punctuation-tail-v1' or policy['sourceSha256'] != digest(root / 'lib/infrastructure/audio/punctuation_audio.dart'):
            raise ValueError('Punctuation audio fingerprint mismatch')
        if preparation['segmenterSourceSha256'] != digest(root / 'lib/features/listening/speech_segmenter.dart'):
            raise ValueError('Segmenter source fingerprint mismatch')
    if not preparation['segmentAfterNormalization'] or preparation['sourceOffsets'] != 'UTF-16':
        raise ValueError('Text preparation mapping policy mismatch')
    if revisions['exportRecipe'] != audit['recipe']:
        raise ValueError('Aligned export recipe mismatch')
    for role, filename in [('main', 'export-official-stateful.py'), ('flow', 'export-official-flow.py'), ('mimi', 'export-official-stateful.py')]:
        if digest(root / 'validation/scripts' / filename) != audit['recipe']['exportScriptDigests'][role]:
            raise ValueError('Aligned export script fingerprint mismatch')
    if digest(root / 'validation/scripts/assemble-aligned-bundle.py') != audit['recipe']['assemblyScriptSha256']:
        raise ValueError('Aligned assembly script fingerprint mismatch')
    notices = manifest['licenseNotices']
    for entry in [weights, voice]:
        revision = entry['url'].split('/resolve/')[1].split('/')[0]
        source_uri = 'https://huggingface.co/kyutai/pocket-tts-without-voice-cloning/tree/' + revision
        if not any(n.get('license') == 'CC-BY-4.0' and n.get('source') == source_uri and n.get('attribution') for n in notices):
            raise ValueError('Aligned pinned attribution missing')


def verify(bundle, manifest_path=None):
    root = Path(__file__).resolve().parents[2]
    path = manifest_path or root / 'assets/models/manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8'))
    required = {'schemaVersion', 'bundleId', 'bundleVersion', 'language', 'engineProtocolVersion',
                'sourceRevisions', 'voice', 'files', 'tensorProtocol', 'licenseNotices',
                'runtimeCompatibility', 'limits'}
    if not required <= manifest.keys() or manifest['language'] != 'fr' or manifest['schemaVersion'] != 1 or manifest['engineProtocolVersion'] != 1:
        raise ValueError('Missing or incompatible manifest fields')
    if manifest['deliveryMode'] != 'local_g0_derivation' or manifest['limits']['maxDownloadBytes'] != 0:
        raise ValueError('Unexpected delivery policy')
    if not manifest['activationGate']['requiresPositiveG0']:
        raise ValueError('Missing activation gate')
    audit = json.loads((bundle / 'audit-lock.json').read_text(encoding='utf-8'))
    recipe_revision = (audit.get('candidate') or {}).get('revision')
    if audit.get('sourceSelection') == 'official_3.3_default_aligned':
        recipe_revision = 'sha256-' + hashlib.sha256(json.dumps(audit['recipe'], sort_keys=True).encode()).hexdigest()
    expected = {Path(e['relativePath']).name: e for e in audit['downloadFiles']}
    allowed = {'flow_lm_main_int8.onnx', 'flow_lm_flow_int8.onnx', 'mimi_decoder_int8.onnx',
               'text_embeddings.f16', 'tokenizer.json', 'estelle.f16', 'manifest.json'}
    if set(expected) != allowed or {e['relativePath'] for e in manifest['files']} != allowed or len(manifest['files']) != 7:
        raise ValueError('Unexpected bundle files')
    for entry in manifest['files']:
        actual = expected[entry['relativePath']]
        relative = actual['relativePath']
        if relative not in allowed | {'voices/estelle.f16'}:
            raise ValueError('Unsafe derivation path')
        source = bundle / relative
        if source.resolve().parent not in [bundle.resolve(), (bundle / 'voices').resolve()]:
            raise ValueError('Unsafe bundle root')
        if source.stat().st_size != entry['byteSize'] or digest(source) != entry['sha256']:
            raise ValueError('Bundle integrity mismatch')
        if entry['delivery']['recipeRevision'] != recipe_revision:
            raise ValueError('Recipe mismatch')
    aligned_metadata(manifest, audit, bundle, root)
    source_root = root / 'android/app/src/main/kotlin/com/ureader/prototype'
    paths = [source_root / 'MainActivity.kt', *sorted((source_root / 'speech').glob('*.kt')), *sorted((source_root / 'reports').glob('*.kt')), *sorted((source_root / 'models').glob('*.kt')), *sorted((source_root / 'epub').glob('*.kt'))]
    records = [{'path': p.relative_to(root).as_posix(), 'sha256': digest(p)} for p in paths]
    source_digest = hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()
    if records != manifest['sourceRevisions']['prototypeSources'] or source_digest != manifest['runtimeCompatibility']['prototypeSourceDigest'] or source_digest != manifest['sourceRevisions']['prototypeSourceDigest']:
        raise ValueError('Prototype source revision mismatch; refresh the reviewed manifest before build')
    return {'status': 'passed', 'bundleId': manifest['bundleId'], 'bundleVersion': manifest['bundleVersion'],
            'manifestSha256': digest(path), 'filesVerified': 7, 'sourceRevisionVerified': True,
            'g0': manifest['activationGate']['g0Verdict'], 'productActivated': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle-directory', required=True, type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.bundle_directory)
    if args.report:
        with args.report.open('x', encoding='utf-8') as handle:
            json.dump(result, handle, indent=2); handle.write('\n')
    print(json.dumps(result))
