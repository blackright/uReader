import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/xhtml_projector.dart';

void main() {
  test('chapter projection uses shared canonical text and cumulative work counters', () async {
    final projector = XhtmlProjector(ContentKey(ContentKind.book, 'book', 1));
    final first = await projector.project(
      0,
      '<html><body><p id="a">Bon<em>jour</em> Léa</p></body></html>',
    );
    final second = await projector.project(
      1,
      '<html><body><p>Suite</p></body></html>',
    );
    expect(first.blocks.single.text, 'Bonjour Léa');
    expect(second.blocks.single.id, 'c1-b0-s0');
    expect(projector.blocks, 2);
    expect(projector.units, 16);
    expect(projector.xmlElements, 7);
  });
  test('cancelled import cannot publish a later chapter result', () async {
    var cancelled = false;
    final projector = XhtmlProjector(
      ContentKey(ContentKind.book, 'book', 1),
      cancelled: () => cancelled,
    );
    cancelled = true;
    await expectLater(
      projector.project(0, '<p>Bonjour</p>'),
      throwsA(
        isA<BookFailure>().having((e) => e.code, 'code', BookError.cancelled),
      ),
    );
  });
  test(
    'selector quota is cumulative across individually acceptable chapters',
    () async {
      final projector = XhtmlProjector(ContentKey(ContentKind.book, 'book', 1));
      final styles = List.filled(2600, '.x { display:block; }').join();
      await projector.project(
        0,
        '<html><body><p class="x">Un</p></body></html>',
        styles: [styles],
      );
      await expectLater(
        projector.project(
          1,
          '<html><body><p class="x">Deux</p></body></html>',
          styles: [styles],
        ),
        throwsA(
          isA<BookFailure>().having(
            (e) => e.code,
            'code',
            BookError.limitExceeded,
          ),
        ),
      );
    },
  );
}
