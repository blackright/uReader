import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import '../../../integration_test/epub_gate_resources.dart' show gatePngBase64;

import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/epub_projection_worker.dart';
import 'package:prototype/infrastructure/epub/image_policy.dart';

void main() {
  final key = ContentKey(ContentKind.book, 'book1', 1);
  Future<ProjectionResult> project(String body) =>
      EpubProjectionWorker.projectString(
        key: key,
        chapterOrdinal: 0,
        xhtml: '<html><head><title>T</title></head><body>$body</body></html>',
      );
  test(
    'canonical v1 preserves inline, br, Unicode and preformatted text',
    () async {
      for (final vector in {
        '<p>Bonjour<br/>Léa</p>': 'Bonjour\nLéa',
        '<p>Bon<em>jour</em> Léa</p>': 'Bonjour Léa',
        '<p> A  B&#9;C </p>': 'A B C',
        '<p>A&#160; B &amp; C</p>': 'A\u00a0 B & C',
        '<pre> A  B&#13;&#10;C </pre>': ' A  B\nC ',
        '<p>&#xE9; e&#x301;</p>': '\u00e9 e\u0301',
      }.entries) {
        expect((await project(vector.key)).blocks.single.text, vector.value);
      }
    },
  );
  test(
    'split preserves surrogate pairs, anchors and deterministic IDs',
    () async {
      final body = '<p>${'a' * 8191}<span id="edge">😀</span> fin</p>';
      final first = await project(body);
      final second = await project(body);
      expect(first.blocks.map((b) => b.text).join(), '${'a' * 8191}😀 fin');
      expect(first.blocks.map((b) => b.id), ['c0-b0-s0', 'c0-b0-s1']);
      expect(first.blocks.map((b) => b.id), second.blocks.map((b) => b.id));
      expect(first.anchors['edge']!.blockId, 'c0-b0-s1');
      expect(first.anchors['edge']!.offsetUtf16, 0);
    },
  );
  test('refuses DTD, deep XML, excessive attributes and incomplete markup', () async {
    for (final xml in [
      '<!DOCTYPE html [<!ENTITY x SYSTEM "https://example.invalid/">]><html>&x;</html>',
      '<html>${'<div>' * 129}x${'</div>' * 129}</html>',
      '<html><p ${List.generate(65, (i) => 'a$i="v"').join(' ')}>x</p></html>',
      '<html><p title="${'a' * 16385}">x</p></html>',
      '<html><p title="${'a' * 70000}',
    ]) {
      await expectLater(
        EpubProjectionWorker.projectString(
          key: key,
          chapterOrdinal: 0,
          xhtml: xml,
        ),
        throwsA(isA<BookFailure>()),
      );
    }
  });
  test(
    'unknown, invalid numeric entities and malformed XML fail the whole job',
    () async {
      for (final body in [
        '<p>&unknown;</p>',
        '<p>&#x110000;</p>',
        '<p>before</p><p>broken',
      ]) {
        await expectLater(project(body), throwsA(isA<BookFailure>()));
      }
    },
  );
  test('images reject dimensions before pixel allocation', () {
    expect(ImagePolicy.dimensionsAllowed(8193, 1), isFalse);
    expect(ImagePolicy.dimensionsAllowed(5000, 4000), isFalse);
    expect(ImagePolicy.dimensionsAllowed(2048, 2048), isTrue);
    expect(ImagePolicy.inspect([1, 2, 3]).usable, isFalse);
    final png = base64Decode(gatePngBase64);
    expect(ImagePolicy.inspect(png).usable, true);
    png[29] ^= 1;
    expect(ImagePolicy.inspect(png).usable, false);
  });
  test('JPEG cannot supply two conflicting frame dimensions', () {
    List<int> frame(int width, int height) => [
      255,
      192,
      0,
      11,
      8,
      height >> 8,
      height & 255,
      width >> 8,
      width & 255,
      1,
      1,
      17,
      0,
    ];
    final scan = [255, 218, 0, 8, 1, 1, 0, 0, 63, 0];
    expect(
      ImagePolicy.inspect([255, 216, ...frame(32, 32), ...scan]).usable,
      true,
    );
    expect(
      ImagePolicy.inspect([
        255,
        216,
        ...frame(32, 32),
        ...frame(5000, 4000),
        ...scan,
      ]).usable,
      false,
    );
    expect(ImagePolicy.inspect([255, 216, ...frame(32, 32)]).usable, false);
  });
  test(
    'known XHTML doctypes use local entities without external DTD resolution',
    () async {
      for (final doctype in [
        '<!DOCTYPE html>',
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">',
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
      ]) {
        final result = await EpubProjectionWorker.projectString(
          key: key,
          chapterOrdinal: 0,
          xhtml: '$doctype<html><body><p>A&nbsp;B</p></body></html>',
        );
        expect(result.blocks.single.text, 'A\u00a0B');
      }
    },
  );
  test(
    'invalid XML scalars cannot become replacement characters or controls',
    () async {
      for (final value in [
        '&#xD800;',
        '&#0;',
        '\u0000',
        String.fromCharCode(0xd800),
      ]) {
        await expectLater(
          project('<p>$value</p>'),
          throwsA(isA<BookFailure>()),
        );
      }
    },
  );
  test('large chapters stay splittable into bounded content windows', () async {
    final result = await project(
      List.generate(130, (i) => '<p>Passage $i</p>').join(),
    );
    expect(result.blocks.length, 130);
    final window = BookWindow(
      key: key,
      generation: 1,
      blocks: result.blocks.take(64).toList(),
      next: BookCursor(key: key, generation: 1, nextOrdinal: 64),
    );
    expect(window.done, false);
    expect(window.blocks.last.ordinal, 63);
  });
  test(
    'long CDATA streams as literal text without an oversized token buffer',
    () async {
      final content = '${'é' * 70000}😀 &unknown; <literal>';
      final result = await project('<pre><![CDATA[$content]]></pre>');
      expect(result.blocks.map((block) => block.text).join(), content);
      expect(result.blocks.every((block) => block.text.length <= 8192), true);
    },
  );
  test(
    'cancel terminates only its worker and suppresses late success',
    () async {
      final job = EpubProjectionWorker.start(
        key: key,
        chapterOrdinal: 0,
        xhtml: '<html><body><p>${'a' * 1000000}</p></body></html>',
      );
      final expectation = expectLater(
        job.result,
        throwsA(
          isA<BookFailure>().having((e) => e.code, 'code', BookError.cancelled),
        ),
      );
      await job.cancel();
      await job.cancel();
      await expectation;
      expect((await project('<p>Next job</p>')).blocks.single.text, 'Next job');
    },
  );
}
