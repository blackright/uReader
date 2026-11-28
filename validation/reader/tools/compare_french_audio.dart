import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/infrastructure/audio/punctuation_audio.dart';

/// Apply the real playback padding to captured native PCM without synthesizing again.
Future<void> main(List<String> args) async {
  if (args.length != 3) {
    throw ArgumentError(
      'cases.json, native WAV directory, fresh private output',
    );
  }
  final private = p.normalize(p.absolute('validation/reader/private'));
  final paths = args.map((v) => p.normalize(p.absolute(v))).toList();
  if (paths.any((v) => !p.isWithin(private, v))) {
    throw ArgumentError('Private paths required');
  }
  final output = Directory(paths[2]);
  if (output.existsSync()) throw StateError('Fresh output required');
  final corpus = jsonDecode(await File(paths[0]).readAsString()) as Map;
  final rows = (corpus['cases'] as List).cast<Map>();
  if (rows.isEmpty || rows.length > 32) throw StateError('Case bounds');
  await output.create();
  final native = <String, Uint8List>{}, played = <String, Uint8List>{};
  final reports = <Map<String, Object?>>[];
  Locator at(String id, int offset) => Locator(
    textId: 'quality-corpus',
    corpusVersion: 1,
    passageId: id,
    offsetUtf16: offset,
  );
  for (final row in rows) {
    final id = row['id'] as String;
    if (!RegExp(r'^[a-z-]+-[0-9]{1,2}$').hasMatch(id)) {
      throw StateError('Unsafe ID');
    }
    final bytes = await File(p.join(paths[1], '$id.wav')).readAsBytes();
    final data = ByteData.sublistView(bytes);
    if (bytes.length > 960044 ||
        bytes.length < 46 ||
        data.getUint32(24, Endian.little) != 24000) {
      throw StateError('WAV bounds');
    }
    final text = row['sourceText'] as String;
    final result = PunctuationAudio.apply(
      bytes,
      SpeechOutput(
        audioHandle: id,
        sampleRate: 24000,
        channels: 1,
        encoding: AudioEncoding.pcm16,
        durationMs: (bytes.length - 44) ~/ 48,
        byteSize: bytes.length,
        start: at(id, 0),
        end: at(id, text.length),
      ),
      text,
    );
    for (var i = 44; i < bytes.length; i++) {
      if (bytes[i] != result.bytes[i]) throw StateError('Speech PCM altered');
    }
    native[id] = bytes;
    played[id] = result.bytes;
    await File(p.join(output.path, '$id-played.wav'))
        .writeAsBytes(result.bytes);
    reports.add({
      'id': id,
      'nativeSha256': sha256.convert(bytes).toString(),
      'playedSha256': sha256.convert(result.bytes).toString(),
      'originalSpeechPcmUnchanged': true,
      'addedQuietSamples': result.addedSamples,
    });
  }
  Uint8List join(List<String> ids, Map<String, Uint8List> clips) {
    final size = ids.fold(44, (int n, id) => n + clips[id]!.length - 44);
    if (size > 24000 * 2 * 300) throw StateError('Joined audio bound');
    final bytes = Uint8List(size)..setRange(0, 44, clips[ids.first]!.take(44));
    var cursor = 44;
    for (final id in ids) {
      final wav = clips[id]!;
      bytes.setRange(cursor, cursor + wav.length - 44, wav, 44);
      cursor += wav.length - 44;
    }
    final header = ByteData.sublistView(bytes);
    header.setUint32(4, size - 8, Endian.little);
    header.setUint32(40, size - 44, Endian.little);
    return bytes;
  }

  for (final paragraph in (corpus['paragraphs'] as List).cast<Map>()) {
    final id = paragraph['id'] as String;
    if (!RegExp(r'^[a-z-]{1,40}$').hasMatch(id)) {
      throw StateError('Unsafe paragraph ID');
    }
    final ids = (paragraph['segments'] as List)
        .map((s) => (s as Map)['id'] as String)
        .toList();
    for (final entry in {'native': native, 'played': played}.entries) {
      await File(p.join(output.path, '$id-${entry.key}.wav'))
          .writeAsBytes(join(ids, entry.value));
    }
  }
  for (final variant
      in (corpus['referenceVariants'] as List? ?? []).cast<Map>()) {
    if (!RegExp(r'^[a-z-]{1,40}$').hasMatch(variant['id'] as String)) {
      throw StateError('Unsafe variant ID');
    }
    final ids = (variant['caseIds'] as List).cast<String>();
    await File(p.join(output.path, '${variant['id']}-reference-boundaries.wav'))
        .writeAsBytes(join(ids, played));
  }
  await File(p.join(output.path, 'comparison.json')).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'status': 'captured_listening_pending', 'cases': reports, 'postprocessingSpeechPcmUnchanged': true, 'referenceBoundariesUseAndroidModel': true, 'officialPcReferenceGenerated': false, 'g1': 'not_evaluated'})}\n',
  );
  stdout.writeln(
    'Compared ${reports.length} WAVs; original speech PCM unchanged. Listening pending.',
  );
}
