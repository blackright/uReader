import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/epub_projection_worker.dart';

void main() {
  final key = ContentKey(ContentKind.book, 'book1', 1);
  Future<ProjectionResult> project(
    String body, [
    String css = '',
  ]) => EpubProjectionWorker.projectString(
    key: key,
    chapterOrdinal: 0,
    xhtml:
        '<html><head><title>T</title><style>$css</style></head><body>$body</body></html>',
  );
  test(
    'display and hidden suppress descendants for display and narration',
    () async {
      final result = await project(
        '<p>Visible</p><div class="off"><p>Secret</p></div><p hidden="hidden">Secret</p>',
        '.off { display:none; }',
      );
      expect(result.blocks.map((b) => b.text).toList(), ['Visible']);
      expect(result.blocks.every((b) => b.speechEligible), isTrue);
    },
  );
  test(
    'visibility inherited but visible child can override, display cannot',
    () async {
      final result = await project(
        '<div class="hidden"><p>Secret</p><p class="shown">Visible</p></div>',
        '.hidden { visibility:hidden; } .shown { visibility:visible; }',
      );
      expect(result.blocks.map((b) => b.text), ['Visible']);
    },
  );
  test(
    'cascade respects specificity, order, child selectors and important',
    () async {
      final result = await project(
        '<section><p id="yes" class="off">Visible</p><p class="off">Secret</p></section>',
        'p.off {display:none} #yes {display:block} section > p {visibility:visible}',
      );
      expect(result.blocks.map((b) => b.text), ['Visible']);
      expect(
        (await project(
          '<p id="yes" style="display:block">Secret</p>',
          '#yes {display:none!important}',
        )).blocks,
        isEmpty,
      );
    },
  );
  test(
    'identified notes consultable but never narrated, active content excluded',
    () async {
      final result = await project(
        '<p>Visible</p><aside epub:type="footnote" xmlns:epub="http://www.idpf.org/2007/ops"><p>Note</p></aside><script>Secret</script>',
      );
      expect(result.blocks.map((b) => b.text), ['Visible', 'Note']);
      expect(result.blocks.last.speechEligible, isFalse);
    },
  );
  test(
    'remote CSS is ignored without loading and selector budgets enforced',
    () async {
      final result = await project(
        '<p>Visible</p>',
        '@import "https://example.invalid/"; p {background:url(https://example.invalid/)}',
      );
      expect(result.blocks.single.text, 'Visible');
      await expectLater(
        project(
          '<p>Visible</p>',
          '${List.generate(5001, (i) => '.x$i').join(',')}{display:none}',
        ),
        throwsA(isA<BookFailure>()),
      );
    },
  );
  test(
    'note semantics follow namespace URI rather than a hardcoded prefix',
    () async {
      final alternate = await project(
        '<aside xmlns:ops="http://www.idpf.org/2007/ops" ops:type="footnote"><p>Note</p></aside>',
      );
      expect(alternate.blocks.single.speechEligible, false);
      final unrelated = await project(
        '<aside xmlns:epub="https://example.invalid/other" epub:type="footnote"><p>Main</p></aside>',
      );
      expect(unrelated.blocks.single.speechEligible, true);
    },
  );
  test('NBSP is preserved inside class and EPUB type tokens', () async {
    final classes = await project(
      '<p class="a&#160;b">Visible</p>',
      '.a {display:none}',
    );
    expect(classes.blocks.single.text, 'Visible');
    final type = await project(
      '<aside xmlns:epub="http://www.idpf.org/2007/ops" epub:type="footnote&#160;other"><p>Main</p></aside>',
    );
    expect(type.blocks.single.speechEligible, true);
  });
}
