import 'package:prototype/features/book_reader/book_image_view.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';

import '../book_reader/image_bounds_test.dart' show ImageSource;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/library/library_cover_cache.dart';

import '../book_reader/reader_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ui.Image> image() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff336655), ui.BlendMode.src);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(8, 12);
    } finally {
      picture.dispose();
    }
  }

  test('page projection includes cover IDs; real decode sizes thumbnails and rejects corruption', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('thumb', blocks: 1, chapters: 1);
    await f.db.customStatement(
      "UPDATE books SET cover_resource_id='cover.png' WHERE book_id=?",
      [key.id],
    );
    final books = await BookRepository(f.db).readyPage();
    expect(books.single.coverResource, 'cover.png');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff336655), ui.BlendMode.src);
    final picture = recorder.endRecording(),
        large = await picture.toImage(600, 900);
    final bytes = (await large.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    large.dispose();
    picture.dispose();
    final decoder = BookImageDecoder(
      ImageSource(f, BookImagePayload(bytes, 600, 900)),
      maxDimension: 384,
    );
    final thumb = await decoder.load(key, 'cover.png', () => false);
    expect(thumb, isNotNull);
    expect(thumb!.height, 384);
    expect(thumb.width, 256);
    thumb.dispose();
    final corrupt = BookImageDecoder(
      ImageSource(f, BookImagePayload(bytes.sublist(0, 30), 600, 900)),
      maxDimension: 384,
    );
    expect(await corrupt.load(key, 'bad.png', () => false), isNull);
  });
  test('local cover cache bounds decoded and pending work; broken cover is nullable', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    var active = 0, peak = 0;
    final cache = LibraryCoverCache(
      f.content,
      maxEntries: 3,
      maxPending: 5,
      loader: (key, resource, cancelled) async {
        active++;
        if (active > peak) peak = active;
        try {
          await Future<void>.delayed(Duration.zero);
          return resource == 'broken' ? null : await image();
        } finally {
          active--;
        }
      },
    );
    addTearDown(cache.close);
    final keys = List.generate(
      50,
      (i) => ContentKey(ContentKind.book, 'cover-$i', 1),
    );
    final results = await Future.wait([
      for (final key in keys) cache.load(key, 'cover', () => false),
    ]);
    for (final value in results) {
      value?.dispose();
    }
    expect(cache.peakCached, lessThanOrEqualTo(3));
    expect(cache.peakPending, lessThanOrEqualTo(5));
    expect(peak, 1);
    expect(await cache.load(keys.first, 'broken', () => false), isNull);
    cache.retain({});
    expect(cache.cached, 0);
  });
  test(
    'deletion invalidates in-flight cover; late image is never published',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      final pending = Completer<ui.Image?>();
      final cache = LibraryCoverCache(
        f.content,
        loader: (_, _, _) => pending.future,
      );
      addTearDown(cache.close);
      final result = cache.load(
        ContentKey(ContentKind.book, 'removed', 1),
        'cover',
        () => false,
      );
      cache.retain({});
      expect(await result, isNull);
      pending.complete(await image());
      await Future<void>.delayed(Duration.zero);
      expect(cache.cached, 0);
    },
  );
}
