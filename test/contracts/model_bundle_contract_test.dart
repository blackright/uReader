import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../features/model_setup/model_installer_test.dart' show fixtureCatalog;

import 'package:prototype/features/model_setup/model_catalog.dart';

void main() {
  test('catalog uses trusted embedded bytes, never a manifest from selected directory', () {
    final catalog = fixtureCatalog([1, 2, 3]);
    expect(catalog.language, 'fr');
    expect(catalog.totalBytes, 3);
    expect(catalog.bundle.manifestDigest.length, 64);
  });
  test(
    'foreign language, unsafe paths and download permissions are refused',
    () {
      for (final change in [
        {'language': 'en'},
        {
          'limits': {'maxBundleBytes': 3, 'maxDownloadBytes': 1},
        },
        {
          'files': [
            {'relativePath': '../escape', 'byteSize': 3, 'sha256': '0' * 64},
          ],
        },
      ]) {
        final base = jsonDecode(
          utf8.decode(fixtureCatalog([1, 2, 3]).embeddedBytes),
        ) as Map<String, dynamic>;
        base.addAll(change);
        expect(
          () => ModelCatalog.fromBytes(utf8.encode(jsonEncode(base))),
          throwsA(anything),
        );
      }
    },
  );
}
