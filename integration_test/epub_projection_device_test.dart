// Physical projection/image checks only. Never opens the product database.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/epub_projection_worker.dart';
import 'package:prototype/infrastructure/epub/image_policy.dart';

import 'epub_gate_jpeg.dart';
import 'epub_gate_resources.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'bounded projection and image decoding without database upgrade',
    (tester) async {
      await waitForNative(tester);
      final report = <String, Object?>{};
      await tester.runAsync(() async {
        final rss = <int>[ProcessInfo.currentRss];
        final clock = Stopwatch()..start();
        for (final entry in gateFragments.entries) {
          final result = await EpubProjectionWorker.projectString(
            key: ContentKey(ContentKind.book, entry.key, 1),
            chapterOrdinal: 0,
            xhtml: entry.value,
            localStyles: ['.hidden {display:none}'],
          );
          expect(result.blocks, isNotEmpty);
          expect(result.blocks.every((b) => b.text.length <= 8192), true);
          expect(result.anchors.containsKey('passage'), true);
          rss.add(ProcessInfo.currentRss);
        }
        report['projectionResources'] = gateFragments.length;
        report['projectionElapsedMs'] = clock.elapsedMilliseconds;
        report['rssBytesBeforeAfterEachResource'] = rss;
        report['rssIsPeakMeasurement'] = false;
        for (final data in [
          base64Decode(gatePngBase64),
          base64Decode(gateJpegBase64),
        ]) {
          expect(ImagePolicy.inspect(data).usable, true);
          final codec = await ui.instantiateImageCodec(data);
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, 2);
            expect(frame.image.height, 2);
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        }
        report['pngAndJpegDecodedOnAndroid'] = true;
      });
      report['productDatabaseOpened'] = false;
      report['maximumFontAccessibility'] = 'deferred';
      binding.reportData = report;
    },
  );
}
