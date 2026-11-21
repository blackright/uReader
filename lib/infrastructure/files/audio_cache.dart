import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../domain/ports.dart';
import '../../domain/books.dart';
import 'private_file_store.dart';

class AudioCache {
  AudioCache(this.files, {this.onRemoved});
  final PrivateFileStore files;
  final Future<void> Function(String)? onRemoved;

  static String key({
    required String bundleDigest,
    required String voice,
    required String text,
    required String normalizerVersion,
    ContentKey? owner,
  }) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pcm16-cache-v1',
            if (owner != null) [owner.kind.name, owner.id, owner.version],
            bundleDigest,
            voice,
            normalizerVersion,
            text,
          ]),
        ),
      )
      .toString();

  static void validate(Uint8List wav, SpeechOutput output) {
    if (wav.length < 46 ||
        wav.length > 960044 ||
        wav.length != output.byteSize ||
        output.sampleRate != 24000 ||
        output.channels != 1 ||
        output.encoding != AudioEncoding.pcm16) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final data = ByteData.sublistView(wav);
    String tag(int offset) =>
        ascii.decode(wav.sublist(offset, offset + 4), allowInvalid: true);
    final samples = (wav.length - 44) ~/ 2;
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WAVE' ||
        tag(12) != 'fmt ' ||
        tag(36) != 'data' ||
        data.getUint32(4, Endian.little) != wav.length - 8 ||
        data.getUint32(16, Endian.little) != 16 ||
        data.getUint16(20, Endian.little) != 1 ||
        data.getUint16(22, Endian.little) != 1 ||
        data.getUint32(24, Endian.little) != 24000 ||
        data.getUint32(28, Endian.little) != 48000 ||
        data.getUint16(32, Endian.little) != 2 ||
        data.getUint16(34, Endian.little) != 16 ||
        data.getUint32(40, Endian.little) != wav.length - 44 ||
        (wav.length - 44).isOdd ||
        output.durationMs != samples * 1000 ~/ 24000) {
      throw const AppError(ErrorCode.invalidContent);
    }
  }

  Future<void> publish(String key, Uint8List wav, SpeechOutput output) async {
    validate(wav, output);
    await files.writeAudioCache(key, wav);
  }

  Future<SpeechOutput?> lookup(String key, Locator start, Locator end) async {
    ResourceLease? lease;
    try {
      lease = await files.acquire('cache/audio/$key.wav');
      final file = await files.audioCacheFile(key);
      final length = await file.length();
      if (length < 46 || length > 960044) return null;
      final bytes = await file.readAsBytes();
      final expected = await files.audioCacheDigest(key);
      if (expected == null || sha256.convert(bytes).toString() != expected) {
        return null;
      }
      final output = SpeechOutput(
        audioHandle: key,
        sampleRate: 24000,
        channels: 1,
        encoding: AudioEncoding.pcm16,
        durationMs: (bytes.length - 44) ~/ 2 * 1000 ~/ 24000,
        byteSize: bytes.length,
        start: start,
        end: end,
      );
      validate(bytes, output);
      await files.touchAudioCache(key);
      return output;
    } on Exception {
      return null;
    } finally {
      lease?.release();
    }
  }

  /// Retain recent chunks for replay; all on-disk objects participate across restarts.
  Future<void> retainForReplay(String key) async {
    if (await files.exists('cache/audio/$key.wav')) {
      await files.touchAudioCache(key);
    }
    await trimReplay();
  }

  Future<void> trimReplay() async {
    for (final removed in await files.trimAudioCache()) {
      await onRemoved?.call(removed);
    }
  }

  Future<void> remove(String key) async {
    await files.deleteAudioObject(key);
    await onRemoved?.call(key);
  }
}
