import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';

void main() {
  test('current embedded bundle is unqualified; explicit model-bound G1 metadata is required', () {
    final raw = jsonDecode(
      File('assets/models/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    ModelCatalog catalog(Map<String, dynamic> value) =>
        ModelCatalog.fromBytes(utf8.encode(jsonEncode(value)));
    expect(catalog(raw).alignmentQualified, isFalse);
    expect(catalog(raw).alignmentAvailable, isTrue);
    final files = raw['files'] as List;
    final main = files.singleWhere(
      (f) => f['relativePath'] == 'flow_lm_main_int8.onnx',
    ) as Map;
    final policy = {
      'version': 1,
      'g1Verdict': 'passed',
      'alignerVersion': 'attention-l3h9-v1',
      'evidenceSha256': 'a' * 64,
      'outputName': 'audited/attention',
      'modelSha256': main['sha256'],
    };
    expect(
      catalog({...raw, 'wordAlignment': policy}).alignmentQualified,
      isTrue,
    );
    for (final bad in [
      {...policy, 'g1Verdict': 'not_evaluated'},
      {...policy, 'modelSha256': 'f' * 64},
      {...policy, 'version': 2},
      {...policy, 'evidenceSha256': ''},
      {...policy, 'outputName': ''},
    ]) {
      expect(
        catalog({...raw, 'wordAlignment': bad}).alignmentQualified,
        isFalse,
      );
    }
  });
}
