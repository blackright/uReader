import '../../../lib/features/listening/french_text_normalizer.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../lib/features/listening/speech_segmenter.dart';
import '../../../lib/features/listening/prepared_text_map.dart';
import '../../../lib/domain/word_selection.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1)
    throw ArgumentError('Fresh private output directory required');
  final root = Directory.current.absolute.path;
  final destination = Directory(args.single).absolute;
  if (!destination.path
          .replaceAll('\\', '/')
          .startsWith(
            '$root/validation/reader/private/'.replaceAll('\\', '/'),
          ) ||
      await destination.exists())
    throw ArgumentError('Fresh private output directory required');
  final manifest = jsonDecode(
    await File('validation/reader/corpus.json').readAsString(),
  ) as Map;
  final sourceFile = File(manifest['timingCorpus']['path'] as String);
  final bytes = await sourceFile.readAsBytes();
  if (sha256.convert(bytes).toString() != manifest['timingCorpus']['sha256'])
    throw StateError('Frozen source mismatch');
  final process = await Process.start(
    'validation/private/reference-venv/Scripts/python.exe',
    ['validation/reader/scripts/count-alignment-tokens.py'],
  );
  final responses = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  final segmenter = SpeechSegmenter((text) async {
    process.stdin.writeln(jsonEncode(text));
    await process.stdin.flush();
    if (!await responses.moveNext()) throw StateError('Tokenizer unavailable');
    return (jsonDecode(responses.current) as Map)['count'] as int;
  });
  final paragraphs = utf8
      .decode(bytes)
      .split(RegExp(r'\r?\n\s*\r?\n'))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  final cases = <Map<String, Object?>>[],
      units = <String, Map<String, Object?>>{},
      words = <Map<String, Object?>>[];
  try {
    for (var i = 0; i < paragraphs.length; i++) {
      final id = 'p$i';
      var n = 0;
      await for (final segment in segmenter.streamPassage(
        textId: 'alignment-corpus',
        version: 1,
        passageId: id,
        source: paragraphs[i],
      )) {
        final map = segment.preparedMap!;
        final caseId = '$id-s${n++}';
        final unitIds = <String>[];
        for (final match in WordSelection.words.allMatches(map.prepared)) {
          final span = map.sourceRange(match.start, match.end);
          if (span == null) continue;
          final unitId = '$id-${span.start}-${span.end}';
          units.putIfAbsent(
            unitId,
            () => {
              'id': unitId,
              'passageId': id,
              'sourceStart': span.start,
              'sourceEnd': span.end,
            },
          );
          unitIds.add(unitId);
          words.add({
            'id': 'w${words.length}',
            'unitId': unitId,
            'caseId': caseId,
            'preparedStart': match.start,
            'preparedEnd': match.end,
          });
        }
        cases.add({
          'id': caseId,
          'passageId': id,
          'source': segment.source,
          'sourceOffset': segment.start.offsetUtf16,
          'prepared': segment.synthesis,
          'sourceSha256': sha256
              .convert(utf8.encode(segment.source))
              .toString(),
          'preparedSha256': sha256
              .convert(utf8.encode(segment.synthesis))
              .toString(),
          'unitIds': unitIds,
          'mapping': [
            for (final s in map.spans)
              {
                'start': s.preparedStart,
                'end': s.preparedEnd,
                'sourceStart': s.source?.start,
                'sourceEnd': s.source?.end,
                'inserted': s.inserted,
              },
          ],
        });
      }
    }
  } finally {
    await process.stdin.close();
    await responses.cancel();
    await process.exitCode;
  }
  await destination.create(recursive: true);
  final document = {
    'schemaVersion': 1,
    'sourceSha256': sha256.convert(bytes).toString(),
    'preparedMapVersion': PreparedTextMap.version,
    'normalizerVersion': FrenchTextNormalizer.version,
    'normalizerSourceSha256': sha256
        .convert(
          await File('lib/features/listening/french_text_normalizer.dart')
              .readAsBytes(),
        )
        .toString(),
    'preparationSourceSha256': sha256
        .convert(
          await File('lib/features/listening/prepared_text_map.dart')
              .readAsBytes(),
        )
        .toString(),
    'segmenterSourceSha256': sha256
        .convert(
          await File('lib/features/listening/speech_segmenter.dart')
              .readAsBytes(),
        )
        .toString(),
    'dartVersion': Platform.version,
    'annotationsFrozen': false,
    'spokenWordCountVerified': false,
    'g1': 'not_evaluated',
    'preparedLexicalUnits': words.length,
    'note': 'Prepared lexical units are not a verified count of pronounced words. Review and freeze audiovisual annotations before scoring.',
    'cases': cases,
    'units': units.values.toList(),
    'spokenWords': words,
  };
  final encoded = utf8.encode(jsonEncode(document));
  await File('${destination.path}/corpus.json').writeAsBytes(encoded);
  print(
    jsonEncode({
      'cases': cases.length,
      'sourceUnits': units.length,
      'preparedLexicalUnits': words.length,
      'sha256': sha256.convert(encoded).toString(),
      'g1': 'not_evaluated',
    }),
  );
}
