import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/app_error.dart';
import '../../domain/storage.dart';

class ModelCatalog {
  ModelCatalog._(
    this.embeddedBytes,
    this.bundle,
    this.totalBytes,
    this.demonstrated,
    this.notices,
  );
  final List<int> embeddedBytes;
  final BundleDescriptor bundle;
  final int totalBytes;
  final bool demonstrated;
  final List<Object?> notices;
  String get language => 'fr';

  /// Only the embedded, digest-pinned manifest can qualify an optional aligner.
  /// Existing manifests have no such entry and keep the feature unavailable.
  bool get alignmentQualified {
    final raw =
        (jsonDecode(utf8.decode(embeddedBytes)) as Map)['wordAlignment'];
    final models = bundle.files.where(
      (f) => f.relativePath == 'flow_lm_main_int8.onnx',
    );
    return raw is Map &&
        raw['version'] == 1 &&
        raw['g1Verdict'] == 'passed' &&
        raw['alignerVersion'] == 'attention-l3h9-v1' &&
        raw['evidenceSha256'] is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['evidenceSha256'] as String) &&
        raw['outputName'] is String &&
        RegExp(r'^[!-~]{1,256}$').hasMatch(raw['outputName'] as String) &&
        models.length == 1 &&
        raw['modelSha256'] == models.single.sha256;
  }

  /// Preview availability is a development capability, never a passed G1 verdict.
  bool get alignmentAvailable {
    if (alignmentQualified) return true;
    const production = bool.fromEnvironment('dart.vm.product');
    const profile = bool.fromEnvironment('dart.vm.profile');
    if (production || profile || !demonstrated) return false;
    final raw =
        (jsonDecode(utf8.decode(embeddedBytes)) as Map)['wordAlignment'];
    final main = bundle.files.where(
      (f) => f.relativePath == 'flow_lm_main_int8.onnx',
    );
    return raw is Map &&
        raw['version'] == 1 &&
        raw['mode'] == 'development_preview' &&
        raw['g1Verdict'] == 'not_evaluated' &&
        raw['alignerVersion'] == 'attention-l3h9-v1' &&
        raw['parityEvidenceSha256'] is String &&
        RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(raw['parityEvidenceSha256'] as String) &&
        raw['outputName'] is String &&
        RegExp(r'^[!-~]{1,256}$').hasMatch(raw['outputName'] as String) &&
        main.length == 1 &&
        raw['modelSha256'] == main.single.sha256;
  }

  factory ModelCatalog.fromBytes(List<int> bytes) {
    try {
      if (bytes.length > 1024 * 1024) throw const FormatException();
      final m = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final limits = m['limits'] as Map;
      if (m['schemaVersion'] != 1 ||
          m['engineProtocolVersion'] != 1 ||
          m['language'] != 'fr' ||
          (m['voice'] as Map)['language'] != 'fr' ||
          m['deliveryMode'] != 'local_g0_derivation' ||
          limits['maxDownloadBytes'] != 0 ||
          (m['localInstallation'] as Map?)?['enabled'] != true) {
        throw const FormatException();
      }
      final files = [
        for (final f in m['files'] as List)
          BundleFile(
            relativePath: f['relativePath'] as String,
            byteSize: f['byteSize'] as int,
            sha256: f['sha256'] as String,
          ),
      ];
      if (files.any((f) => f.byteSize <= 0 || f.relativePath.contains('/')) ||
          files.length > 32) {
        throw const FormatException();
      }
      final size = files.fold<int>(0, (n, f) => n + f.byteSize);
      if (size > limits['maxBundleBytes'] || size > 256 * 1024 * 1024) {
        throw const FormatException();
      }
      return ModelCatalog._(
        List.unmodifiable(bytes),
        BundleDescriptor(
          id: m['bundleId'] as String,
          version: m['bundleVersion'] as String,
          manifestDigest: sha256.convert(bytes).toString(),
          files: files,
        ),
        size,
        (m['activationGate'] as Map)['g0Verdict'] == 'passed',
        List<Object?>.unmodifiable(m['licenseNotices'] as List),
      );
    } catch (_) {
      throw const AppError(ErrorCode.modelIntegrityFailed);
    }
  }
  Future<BundleDescriptor?> resolve(
    String id,
    String version,
    String digest,
  ) async =>
      id == bundle.id &&
          version == bundle.version &&
          digest == bundle.manifestDigest
      ? bundle
      : null;
}
