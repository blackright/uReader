import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';

void main() {
  final source = File('assets/corpus/fr_demo.json').readAsStringSync();
  test(
    'Dix textes, répartition 3/3/3/1 et références UTF-16 valides',
    () async {
      final entries = await CorpusRepository(read: () async => source).load();
      expect(entries.length, 10);
      expect(entries.where((e) => e.category == 'multi_paragraph').length, 3);
      expect(
        entries
            .singleWhere((e) => e.category == 'long_paragraph')
            .text
            .passages
            .single
            .text
            .length,
        greaterThanOrEqualTo(2000),
      );
      expect(() => entries.clear(), throwsUnsupportedError);
    },
  );
  test(
    'Refuse versions, références, transcription et catégories invalides',
    () async {
      final corruptions = <void Function(Map<String, dynamic>)>[
        (r) => r['schemaVersion'] = 2,
        (r) => r['corpusVersion'] = 2,
        (r) => r['texts'].removeLast(),
        (r) => r['texts'][1]['id'] = r['texts'][0]['id'],
        (r) => r['texts'][0]['passages'][0]['textId'] = 'another',
        (r) => r['texts'][0]['passages'][0]['ordinal'] = 3,
        (r) => r['texts'][0]['referenceTranscript'] = 'wrong',
        (r) => r['texts'][0]['attribution'] = '',
        (r) => r['texts'][0]['category'] = 'long_paragraph',
        (r) => r['texts'][0]['language'] = 'en',
      ];
      for (final corrupt in corruptions) {
        final root = jsonDecode(source) as Map<String, dynamic>;
        corrupt(root);
        await expectLater(
          CorpusRepository(read: () async => jsonEncode(root)).load(),
          throwsA(isA<AppError>()),
        );
      }
    },
  );
  test('Erreurs expurgées et lecture mise en cache', () async {
    var reads = 0;
    final corpus = CorpusRepository(
      read: () async {
        reads++;
        return source;
      },
    );
    await corpus.load();
    await corpus.load();
    expect(reads, 1);
    await expectLater(
      CorpusRepository(read: () async => 'x' * 131073).load(),
      throwsA(isA<AppError>()),
    );
    await expectLater(
      CorpusRepository(read: () async => throw Exception('private')).load(),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          isNot(contains('private')),
        ),
      ),
    );
  });
}
