// G2: isolated content/projection/layout campaign. No production DB opened.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/features/book_reader/book_paginator.dart';
import 'package:prototype/features/book_reader/book_image_view.dart';

import '../test/features/book_reader/reader_fixture.dart';
import '../test/features/book_reader/image_bounds_test.dart' show ImageSource;
import 'epub_reader_images.dart';
import 'epub_management_harness.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> checkpoint() async {
    final support = await getApplicationSupportDirectory();
    await File('${support.path}/reader-layout-g2-checkpoint.json')
        .writeAsString(jsonEncode(binding.reportData ?? {}), flush: true);
  }

  testWidgets('G2 canonical text coverage and shared renderer on ten EPUBs', (
    tester,
  ) async {
    await waitForNative(tester);
    final h = EpubManagementHarness();
    await tester.runAsync(() => h.open());
    final observations = <Map<String, Object?>>[];
    try {
      for (var index = 0; index < 10; index++) {
        final book = (await tester.runAsync(() => h.importAt(index)))!;
        final images = BookImageDecoder(h.content);
        for (final scale in [1.0, 3.2]) {
          final layout = ReaderLayout(
            width: 280,
            height: 460,
            textScaler: TextScaler.linear(scale),
          );
          final expected = <String, String>{};
          var blockCount = 0;
          Stream<BookBlock> blocks() async* {
            BookCursor? next;
            do {
              final window = await h.content.window(
                book.key,
                1,
                after: next,
                maxBlocks: 1,
                maxUnits: 8192,
              );
              for (final block in window.blocks) {
                expected[block.id] = sha256
                    .convert(utf8.encode(block.text))
                    .toString();
                blockCount++;
                yield block;
              }
              next = window.next;
            } while (next != null);
          }

          final paginator = BookPaginator(layout);
          final iterator = StreamIterator(paginator.paginate(blocks()));
          String? active;
          var buffer = StringBuffer(),
              pages = 0,
              verified = 0,
              maxFragments = 0;
          var expectedPoint = PagePoint(0, 0);
          try {
            while ((await tester.runAsync(iterator.moveNext))!) {
              final page = iterator.current;
              expect(page.start, expectedPoint);
              expectedPoint = page.end;
              expect(page.height, lessThanOrEqualTo(460.01));
              if (page.fragments.length > maxFragments) {
                maxFragments = page.fragments.length;
              }
              for (final f in page.fragments) {
                if (active != null && active != f.block.id) {
                  expect(
                    sha256.convert(utf8.encode(buffer.toString())).toString(),
                    expected[active],
                  );
                  verified++;
                  buffer = StringBuffer();
                }
                active = f.block.id;
                buffer.write(f.block.text.substring(f.startUtf16, f.endUtf16));
              }
              if (pages == 0 || page.fragments.any((f) => f.atomic)) {
                await tester.pumpWidget(
                  MaterialApp(
                    home: Scaffold(
                      body: Center(
                        child: SizedBox(
                          width: 280,
                          height: 460,
                          child: Column(
                            children: [
                              for (final f in page.fragments)
                                ReaderFragmentView(
                                  layout: layout,
                                  fragment: f,
                                  images: images,
                                  onLink: (_, _) {},
                                  onNote: (_) {},
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pump(const Duration(milliseconds: 50));
                expect(tester.takeException(), isNull);
              }
              pages++;
            }
            if (active != null) {
              expect(
                sha256.convert(utf8.encode(buffer.toString())).toString(),
                expected[active],
              );
              verified++;
            }
            expect(verified, blockCount);
            expect(expectedPoint, PagePoint(blockCount, 0));
            observations.add({
              'book': h.corpus[index]['id'],
              'scale': scale,
              'pages': pages,
              'canonicalBlocksVerified': verified,
              'maxFragments': maxFragments,
              'maximumBatchMicros': paginator.maximumBatchMicros,
              'rssSampleBytes': ProcessInfo.currentRss,
            });
          } finally {
            await tester.runAsync(iterator.cancel);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    } finally {
      await tester.runAsync(h.close);
    }
    binding.reportData = {
      'paginationGate': observations,
      'source': 'injected authorized EPUBs, real importer and projection',
      'productDatabaseOpened': false,
      'talkBack': 'not_evaluated',
      'maximumPhysicalFontSetting': 'not_measured',
    };
    await tester.runAsync(checkpoint);
  }, timeout: const Timeout(Duration(minutes: 10)));
  testWidgets('G2 long logical paragraph keeps bounded page production', (
    tester,
  ) async {
    final f = ReaderFixture();
    await tester.runAsync(f.open);
    try {
      final key = (await tester.runAsync(
        () =>
            f.book('long-layout', blocks: 3, chapters: 1, text: 'mot ' * 2048),
      ))!;
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await f.db.customStatement(
            'UPDATE book_blocks SET block_id=? WHERE book_id=? AND ordinal=?',
            ['c0-b0-s$i', key.id, i],
          );
        }
      });
      final observations = <Map<String, Object?>>[];
      for (final scale in [1.0, 3.2]) {
        Stream<BookBlock> blocks() async* {
          BookCursor? next;
          do {
            final w = await f.content.window(key, 1, after: next, maxBlocks: 1);
            for (final b in w.blocks) {
              yield b;
            }
            next = w.next;
          } while (next != null);
        }

        final paginator = BookPaginator(
          ReaderLayout(
            width: 280,
            height: 460,
            textScaler: TextScaler.linear(scale),
          ),
        );
        var count = 0, units = 0, maxFragments = 0;
        final iterator = StreamIterator(paginator.paginate(blocks()));
        try {
          while ((await tester.runAsync(iterator.moveNext))!) {
            final page = iterator.current;
            count++;
            units += page.fragments.fold<int>(
              0,
              (sum, f) => sum + f.endUtf16 - f.startUtf16,
            );
            if (page.fragments.length > maxFragments) {
              maxFragments = page.fragments.length;
            }
            if (count == 1) {
              await tester.pumpWidget(
                MaterialApp(
                  home: Scaffold(
                    body: Column(
                      children: [
                        for (final fragment in page.fragments)
                          ReaderFragmentView(
                            layout: paginator.layout,
                            fragment: fragment,
                            onLink: (_, _) {},
                            onNote: (_) {},
                          ),
                      ],
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
            }
          }
        } finally {
          await tester.runAsync(iterator.cancel);
        }
        expect(units, 24576);
        observations.add({
          'scale': scale,
          'pages': count,
          'sourceUnits': units,
          'maxFragments': maxFragments,
          'maximumBatchMicros': paginator.maximumBatchMicros,
          'rssSampleBytes': ProcessInfo.currentRss,
        });
      }
      binding.reportData = {
        ...?binding.reportData,
        'longParagraph': observations,
      };
      await tester.runAsync(checkpoint);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
  testWidgets('G2 repeated 16MP PNG JPEG decoder stress without exclusion', (
    tester,
  ) async {
    final f = ReaderFixture();
    await tester.runAsync(f.open);
    final observations = <Map<String, Object?>>[];
    try {
      for (final encoded in [readerLargePng, readerLargeJpeg]) {
        final payload = BookImagePayload(base64Decode(encoded), 4000, 4000);
        final decoder = BookImageDecoder(ImageSource(f, payload));
        final rss = <int>[];
        var beats = 0;
        final timer = (await tester.runAsync(
          () async => Timer.periodic(const Duration(milliseconds: 10), (_) {
            beats++;
            if (rss.length < 10000) rss.add(ProcessInfo.currentRss);
          }),
        ))!;
        try {
          for (var repeat = 0; repeat < 10; repeat++) {
            final batch = (await tester.runAsync(
              () => Future.wait([
                for (var n = 0; n < 3; n++)
                  decoder.load(
                    ContentKey(ContentKind.book, 'image-book', 1),
                    'r0',
                    () => false,
                  ),
              ]),
            ))!;
            for (final image in batch) {
              expect(image, isNotNull);
              expect(image!.width, 2048);
              expect(image.height, 2048);
              image.dispose();
            }
            await tester.pump(const Duration(milliseconds: 20));
          }
        } finally {
          timer.cancel();
        }
        expect(decoder.peakActive, 1);
        expect(beats, greaterThan(0));
        observations.add({
          'format': observations.isEmpty ? 'PNG' : 'JPEG',
          'sourcePixels': 16000000,
          'decodes': 30,
          'peakActive': decoder.peakActive,
          'rssSamplesBytes': rss,
          'eventLoopBeats': beats,
        });
      }
      binding.reportData = {
        ...?binding.reportData,
        'imageStress': observations,
        'imageStressExcluded': false,
      };
      await tester.runAsync(checkpoint);
    } finally {
      await tester.runAsync(f.close);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
