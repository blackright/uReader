import 'dart:convert';
import 'dart:io';

import 'package:prototype/features/listening/french_text_normalizer.dart';

void main(List<String> args) {
  final protocol = args.length == 2 && args.first == '--protocol';
  if ((!protocol && args.length != 1) || File(args.last).existsSync()) {
    throw ArgumentError('Provide [--protocol] and one new output JSON path');
  }
  final cases = <String, String>{
    'numbers':
        'Le 12 avril 2026, à 9 h 30, nous achetons 3 pommes, '
        '2 poires et 250 grammes de fromage.',
    'agreements':
        'Le 1 janvier 2026, à 1 h 05, nous achetons 21 pommes et 80 poires.',
    'leap-year':
        'Le 29 février 2024, à 23 h 45, nous pesons 200 grammes de farine.',
  };
  if (protocol) {
    cases.clear();
    final corpus = jsonDecode(
      File('assets/corpus/fr_demo.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final id in ['fr-01-p1', 'fr-04-p1']) {
      final passage = (corpus['texts'] as List)
          .expand((text) => (text as Map)['passages'] as List)
          .cast<Map>()
          .singleWhere((passage) => passage['id'] == id);
      cases[id] = '${(passage['text'] as String).split('.').first}.';
    }
  }
  final output = {
    'normalizerVersion': FrenchTextNormalizer.version,
    'normalizerSource': 'lib/features/listening/french_text_normalizer.dart',
    'scope': protocol
        ? 'exact_protocol_corpus_extracts'
        : 'synthetic_pc_validation_only',
    'cases': [
      for (final entry in cases.entries)
        (() {
          final result = const FrenchTextNormalizer().normalize(entry.value);
          return {
            'id': entry.key,
            'sourceText': result.source,
            'synthesisText': result.speech,
            'spans': [
              for (final s in result.spans)
                {
                  'sourceStart': s.sourceStart,
                  'sourceEnd': s.sourceEnd,
                  'speechStart': s.speechStart,
                  'speechEnd': s.speechEnd,
                  'replaced': s.replaced,
                },
            ],
          };
        })(),
    ],
  };
  File(args.last).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln('Prepared ${cases.length} cases with source ranges.');
}
