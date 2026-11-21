// Phase-1 API smoke check only; this is not the hostile-input or rendering gate.
import 'dart:convert';
import 'dart:io';

import 'package:csslib/parser.dart' as css;
import 'package:xml/xml_events.dart';

Future<void> main() async {
  final batches =
      await Stream<String>.fromIterable(['<root><p>Bon', 'jour</p></root>'])
          .transform(
            XmlEventDecoder(
              validateDocument: true,
              validateNamespace: true,
              validateNesting: true,
            ),
          )
          .toList();
  final text = batches
      .expand((batch) => batch)
      .whereType<XmlTextEvent>()
      .map((event) => event.value)
      .join();
  if (text != 'Bonjour') {
    throw StateError('XML event API smoke check failed');
  }
  final errors = <css.Message>[];
  css.parse('p { color: red; }', errors: errors);
  if (errors.isNotEmpty) {
    throw StateError('CSS API smoke check failed');
  }
  final report = {
    'status': 'passed',
    'xml': '7.1.0',
    'csslib': '1.0.2',
    'chunkedXmlApi': true,
    'cssParseApi': true,
    'boundedParsingGate': 'not_evaluated',
    'androidRenderingAndTalkBack': 'not_evaluated',
  };
  File('validation/epub/reports/parser-smoke.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
}
