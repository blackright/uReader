"""Assemble a private local Kokoro bundle; no download, activation or G0 verdict."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[3]

IMPLEMENTATION_SOURCES = (
    'android/app/src/main/kotlin/com/ureader/prototype/speech/FrenchPhonemizer.kt',
    'android/app/src/main/kotlin/com/ureader/prototype/speech/KokoroInputs.kt',
    'android/app/src/main/kotlin/com/ureader/prototype/speech/OnnxKokoroSynthesizer.kt',
    'android/app/src/main/cpp/french_frontend.cpp',
    'android/app/src/main/cpp/CMakeLists.txt',
    'lib/features/listening/french_text_normalizer.dart',
    'lib/features/listening/prepared_text_map.dart',
    'lib/features/listening/speech_segmenter.dart',
    'lib/infrastructure/audio/punctuation_audio.dart',
    'lib/infrastructure/speech/platform_speech_engine.dart',
)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    private = (ROOT / 'validation/reader/private').resolve()
    if any(not p.resolve().is_relative_to(private) for p in (args.export, args.output)):
        raise ValueError('Private export and output required')
    report = json.loads((args.export / 'export-report.json').read_text(encoding='utf-8'))
    if report['status'] != 'exported_pc_probes_passed' or sha(args.export / 'kokoro.onnx') != report['modelSha256']:
        raise ValueError('Verified local export required')
    pocket = json.loads((ROOT / 'assets/models/manifest.json').read_text(encoding='utf-8'))
    tokenizer_pin = next(f for f in pocket['files'] if f['relativePath'] == 'tokenizer.json')
    tokenizer = private / 'voice-preview-20261120-01/bundle/tokenizer.json'
    if tokenizer.stat().st_size != tokenizer_pin['byteSize'] or sha(tokenizer) != tokenizer_pin['sha256']:
        raise ValueError('Tokenizer for reference segmentation differs')
    frontend = ROOT / 'validation/private/kokoro-venv/Lib/site-packages/espeakng_loader/espeak-ng-data'
    source_inventory = json.loads((private / 'french-quality-kokoro-native-20261126-02/frontend-inventory.json').read_text(encoding='utf-8'))
    if {f.relative_to(frontend).as_posix() for f in frontend.rglob('*') if f.is_file()} != {r['path'] for r in source_inventory}:
        raise ValueError('Frontend inventory changed')
    args.output.mkdir(parents=True, exist_ok=False)
    bundle = args.output / 'bundle'
    bundle.mkdir()
    for name in ('kokoro.onnx', 'siwis.f32', 'vocab.json'):
        shutil.copyfile(args.export / name, bundle / name)
    shutil.copyfile(tokenizer, bundle / 'tokenizer.json')
    with zipfile.ZipFile(bundle / 'espeak-data.zip', 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in source_inventory:
            source = frontend / entry['path']
            if source.is_symlink() or source.stat().st_size != entry['byteSize'] or sha(source) != entry['sha256']:
                raise ValueError('Frontend data integrity')
            info = zipfile.ZipInfo('espeak-ng-data/' + entry['path'], date_time=(2026, 11, 26, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())
    files = [{'relativePath': f.name, 'byteSize': f.stat().st_size, 'sha256': sha(f)} for f in sorted(bundle.iterdir())]
    total = sum(f['byteSize'] for f in files)
    if total > 512 * 1024 * 1024:
        raise ValueError('Bundle exceeds bounded storage budget')
    manifest = {
        'schemaVersion': 1, 'bundleId': 'fr-kokoro-siwis', 'bundleVersion': '1.0.0-development',
        'engine': 'kokoro', 'engineProtocolVersion': 1, 'language': 'fr',
        'deliveryMode': 'local_native_preview',
        'activationGate': {'mode': 'development_preview', 'requiresNativeProbe': True,
                           'nativeProbeVerdict': 'not_evaluated', 'g0Verdict': 'not_evaluated'},
        'voice': {'id': 'ff_siwis', 'language': 'fr', 'displayName': 'SIWIS — Kokoro',
                  'provenance': 'https://huggingface.co/hexgrad/Kokoro-82M/tree/f3ff3571791e39611d31c381e3a41a3af07b4987'},
        'preparationVersion': 'kokoro-baseline-lexical-v1',
        'implementationSources': [{'path': path, 'sha256': sha(ROOT / path)} for path in IMPLEMENTATION_SOURCES],
        'runtimeCompatibility': {'onnxRuntime': '1.25.0', 'sampleRate': 24000, 'channels': 1,
                                 'espeakSourceRevision': '4870adfa25b1a32b4361592f1be8a40337c58d6c',
                                 'espeakLoaderVersion': '0.2.4', 'modelSha256': report['modelSha256']},
        'limits': {'maxBundleBytes': 512 * 1024 * 1024, 'maxDownloadBytes': 0},
        'localInstallation': {'enabled': True, 'network': False, 'sourceFilesModified': False},
        'licenseNotices': ['Kokoro model and code: Apache-2.0; SIWIS attribution required.',
                           'eSpeak NG and phonetic data: GPL-3.0-or-later. Distribution review pending.',
                           'ONNX Runtime: MIT. No book content transmitted.'],
        'files': files,
    }
    (args.output / 'manifest-draft.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (args.output / 'assembly-report.json').write_text(json.dumps({'status': 'assembled_not_activated',
        'files': files, 'totalBytes': total, 'frontendFiles': len(source_inventory),
        'distributionReviewed': False}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'assembled_not_activated', 'files': len(files), 'totalBytes': total,
                      'frontendFiles': len(source_inventory)}))


if __name__ == '__main__':
    main()
