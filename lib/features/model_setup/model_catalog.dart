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
  String get voiceId =>
      ((jsonDecode(utf8.decode(embeddedBytes)) as Map)['voice'] as Map)['id']
          as String;
  bool get developmentPreview =>
      (jsonDecode(utf8.decode(embeddedBytes)) as Map)['deliveryMode'] ==
      'local_native_preview';
  // Kokoro adds up to 64 MiB of expanded frontend data. Reserve the bounded
  // audio cache as well, so copying the model cannot consume its playback space.
  int get requiredInstallationBytes =>
      totalBytes + (developmentPreview ? 144 : 8) * 1024 * 1024;
  String get voiceDisplayName =>
      (((jsonDecode(utf8.decode(embeddedBytes)) as Map)['voice']
              as Map)['displayName']
          as String?) ??
      (voiceId == 'estelle' ? 'Estelle' : voiceId);
  String get licenseSummary => developmentPreview
      ? 'Kokoro : Apache-2.0 ; eSpeak NG : GPLv3. Attribution SIWIS conservée.'
      : 'Kyutai : CC-BY-4.0 ; moteur et runtime : MIT.';

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
      requireIdentifier((m['voice'] as Map)['id'] as String);
      final limits = m['limits'] as Map;
      final preview = m['deliveryMode'] == 'local_native_preview';
      if (preview &&
          (m['engine'] != 'kokoro' ||
              m['bundleId'] != 'fr-kokoro-siwis' ||
              (m['voice'] as Map)['id'] != 'ff_siwis')) {
        throw const FormatException();
      }
      if (m['schemaVersion'] != 1 ||
          m['engineProtocolVersion'] != 1 ||
          m['language'] != 'fr' ||
          (m['voice'] as Map)['language'] != 'fr' ||
          (!preview && m['deliveryMode'] != 'local_g0_derivation') ||
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
      if (preview &&
          (files.length != 5 ||
              !files.map((f) => f.relativePath).toSet().containsAll({
                'kokoro.onnx',
                'siwis.f32',
                'vocab.json',
                'tokenizer.json',
                'espeak-data.zip',
              }))) {
        throw const FormatException();
      }
      final size = files.fold<int>(0, (n, f) => n + f.byteSize);
      if (size > limits['maxBundleBytes'] ||
          size > (preview ? 512 : 256) * 1024 * 1024) {
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
        preview
            ? !const bool.fromEnvironment('dart.vm.product') &&
                  !const bool.fromEnvironment('dart.vm.profile') &&
                  (m['activationGate'] as Map)['mode'] ==
                      'development_preview' &&
                  (m['activationGate'] as Map)['requiresNativeProbe'] == true &&
                  (m['activationGate'] as Map)['nativeProbeVerdict'] ==
                      'passed' &&
                  RegExp(r'^[a-f0-9]{64}$').hasMatch(
                    (m['activationGate'] as Map)['evidenceSha256'] as String? ??
                        '',
                  )
            : (m['activationGate'] as Map)['g0Verdict'] == 'passed',
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
