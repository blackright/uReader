import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:prototype/features/listening/french_text_normalizer.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

/// Freeze real production preparation with the pinned tokenizer, never save a repère.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Provide private source JSON and fresh private output directory',
    );
  }
  final private = p.normalize(p.absolute('validation/reader/private'));
  final sourceFile = File(p.normalize(p.absolute(args[0])));
  final destination = Directory(p.normalize(p.absolute(args[1])));
  for (final path in [sourceFile.path, destination.path]) {
    if (!p.isWithin(private, path)) {
      throw ArgumentError('Private paths required');
    }
  }
  if (destination.existsSync()) throw StateError('Fresh output required');
  final input = jsonDecode(await sourceFile.readAsString()) as Map;
  final sources = input['cases'] as List;
  if (sources.isEmpty || sources.length > 8) throw StateError('Corpus bounds');
  final process = await Process.start(
    'validation/private/reference-venv/Scripts/python.exe',
    ['-X', 'utf8', 'validation/reader/scripts/count-alignment-tokens.py'],
  );
  final errors = process.stderr.transform(utf8.decoder).join();
  final responses = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  Future<int> count(String text) async {
    process.stdin.writeln(jsonEncode(text));
    await process.stdin.flush();
    if (!await responses.moveNext()) throw StateError('Tokenizer stopped');
    return (jsonDecode(responses.current) as Map)['count'] as int;
  }

  final results = <Map<String, Object?>>[];
  final flat = <Map<String, Object?>>[];
  try {
    final segmenter = SpeechSegmenter(count);
    for (final raw in sources.cast<Map>()) {
      final id = raw['id'] as String;
      final source = raw['source'] as String;
      if (!RegExp(r'^[a-z-]{1,40}$').hasMatch(id) || source.length > 8192) {
        throw StateError('Invalid case');
      }
      final segments = await segmenter
          .streamPassage(
            textId: 'quality-corpus',
            version: 1,
            passageId: id,
            source: source,
          )
          .toList();
      if (segments.map((s) => s.source).join() != source) {
        throw StateError('Source coverage changed');
      }
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final tokens = await count(segment.synthesis);
        if (tokens > 50) throw StateError('Model token budget exceeded');
        final row = <String, Object?>{
          'id': '$id-${i + 1}',
          'parentId': id,
          'sourceText': segment.source,
          'synthesisText': segment.synthesis,
          'sourceStart': segment.start.offsetUtf16,
          'sourceEnd': segment.end.offsetUtf16,
          'tokens': tokens,
          'forcedTerminalPeriod':
              segment.preparedMap!.spans.last.inserted &&
              segment.synthesis.endsWith('.'),
          'spans': [
            for (final span in segment.preparedMap!.spans)
              {
                'preparedStart': span.preparedStart,
                'preparedEnd': span.preparedEnd,
                'sourceStart': span.source?.start,
                'sourceEnd': span.source?.end,
              },
          ],
        };
        rows.add(row);
        flat.add(row);
      }
      results.add({
        ...raw.cast<String, Object?>(),
        'normalizedText': const FrenchTextNormalizer()
            .normalize(source, maxSourceUnits: 8192)
            .speech,
        'segments': rows,
      });
    }
    await process.stdin.close();
    if (await process.exitCode != 0 || (await errors).isNotEmpty) {
      throw StateError('Tokenizer failed');
    }
    await destination.create();
    await File('${destination.path}/cases.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'normalizerVersion': FrenchTextNormalizer.version, 'sourceProvenance': input['provenance'], 'cases': flat, 'paragraphs': results, 'listening': 'not_evaluated'})}\n',
    );
    stdout.writeln(
      'Frozen ${results.length} paragraphs / ${flat.length} segments.',
    );
  } finally {
    await responses.cancel();
    process.kill();
  }
}
