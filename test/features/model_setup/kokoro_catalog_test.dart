import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';

Map<String, Object?> manifest({int modelBytes = 300 * 1024 * 1024}) => {
  'schemaVersion': 1,
  'engineProtocolVersion': 1,
  'engine': 'kokoro',
  'bundleId': 'fr-kokoro-siwis',
  'bundleVersion': 'fixture',
  'language': 'fr',
  'voice': {
    'id': 'ff_siwis',
    'language': 'fr',
    'displayName': 'SIWIS — Kokoro',
  },
  'deliveryMode': 'local_native_preview',
  'localInstallation': {'enabled': true},
  'limits': {'maxBundleBytes': 512 * 1024 * 1024, 'maxDownloadBytes': 0},
  'activationGate': {
    'mode': 'development_preview',
    'requiresNativeProbe': true,
    'nativeProbeVerdict': 'not_evaluated',
    'g0Verdict': 'not_evaluated',
  },
  'licenseNotices': ['Test fixture; no actual model qualification'],
  'files': [
    for (final name in [
      'kokoro.onnx',
      'siwis.f32',
      'vocab.json',
      'tokenizer.json',
      'espeak-data.zip',
    ])
      {
        'relativePath': name,
        'byteSize': name == 'kokoro.onnx' ? modelBytes : 1,
        'sha256': 'a' * 64,
      },
  ],
};

ModelCatalog parse(Map<String, Object?> m) =>
    ModelCatalog.fromBytes(utf8.encode(jsonEncode(m)));

void main() {
  test('permits the bounded larger model without declaring an untested voice ready', () {
    final catalog = parse(manifest());
    expect(catalog.voiceId, 'ff_siwis');
    expect(catalog.voiceDisplayName, 'SIWIS — Kokoro');
    expect(catalog.developmentPreview, isTrue);
    expect(
      catalog.requiredInstallationBytes - catalog.totalBytes,
      greaterThanOrEqualTo(128 * 1024 * 1024),
    );
    expect(catalog.demonstrated, isFalse);
    expect(catalog.alignmentAvailable, isFalse);
  });

  test('a G0 label alone cannot enable the native development profile', () {
    final data = manifest();
    (data['activationGate'] as Map)['g0Verdict'] = 'passed';
    expect(parse(data).demonstrated, isFalse);
  });

  test('requires the native evidence digest in addition to its verdict', () {
    final data = manifest();
    (data['activationGate'] as Map)['nativeProbeVerdict'] = 'passed';
    expect(parse(data).demonstrated, isFalse);
    (data['activationGate'] as Map)['evidenceSha256'] = 'e' * 64;
    expect(parse(data).demonstrated, isTrue); // Debug test fixture only.
  });

  test(
    'refuses a model exceeding the hard cap even when the manifest raises it',
    () {
      final data = manifest(modelBytes: 513 * 1024 * 1024);
      (data['limits'] as Map)['maxBundleBytes'] = 1024 * 1024 * 1024;
      expect(() => parse(data), throwsA(isA<AppError>()));
    },
  );

  test('does not extend the larger limit to another engine', () {
    final data = manifest();
    data['engine'] = 'unknown';
    expect(() => parse(data), throwsA(isA<AppError>()));
  });

  test('rejects missing files and a substituted voice identity', () {
    final missing = manifest();
    (missing['files'] as List).removeLast();
    expect(() => parse(missing), throwsA(isA<AppError>()));
    final changed = manifest();
    (changed['voice'] as Map)['id'] = 'estelle';
    expect(() => parse(changed), throwsA(isA<AppError>()));
  });
}
