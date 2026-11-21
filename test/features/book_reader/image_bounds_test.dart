import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/book_image_view.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';

import '../../../integration_test/epub_gate_resources.dart';
import '../../../integration_test/epub_gate_jpeg.dart';
import 'reader_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReaderFixture f;
  setUp(() async {
    f = ReaderFixture();
    await f.open();
  });
  tearDown(() async {
    await f.close();
  });
  test('oversized or unverifiable headers never reach a decoder', () async {
    final data = base64Decode(gatePngBase64);
    final huge = Uint8List.fromList(data);
    ByteData.sublistView(huge).setUint32(16, 5000);
    ByteData.sublistView(huge).setUint32(20, 4000);
    for (final payload in [
      BookImagePayload(huge, 5000, 4000),
      BookImagePayload(Uint8List.fromList([1, 2, 3]), 1, 1),
    ]) {
      final source = ImageSource(f, payload);
      var decodes = 0;
      final decoder = BookImageDecoder(
        source,
        decodeValidated: (_) async {
          decodes++;
          return null;
        },
      );
      expect(
        await decoder.load(
          ContentKey(ContentKind.book, 'book', 1),
          'r0',
          () => false,
        ),
        isNull,
      );
      expect(decodes, 0);
    }
  });
  test('real PNG decodes; failures replace safely and queued work is single flight', () async {
    final bytes = base64Decode(gatePngBase64);
    final source = ImageSource(f, BookImagePayload(bytes, 2, 2));
    final real = await BookImageDecoder(source)
        .load(ContentKey(ContentKind.book, 'book', 1), 'r0', () => false);
    expect(real, isNotNull);
    expect(real!.width, 2);
    real.dispose();
    final jpeg = await BookImageDecoder(
      ImageSource(f, BookImagePayload(base64Decode(gateJpegBase64), 2, 2)),
    ).load(ContentKey(ContentKind.book, 'book', 1), 'jpeg', () => false);
    expect(jpeg, isNotNull);
    expect(jpeg!.width, 2);
    jpeg.dispose();
    expect(
      await BookImageDecoder(
        source,
        decodeValidated: (_) async => throw StateError('corrupt'),
      ).load(ContentKey(ContentKind.book, 'book', 1), 'r0', () => false),
      isNull,
    );
    final gate = Completer<ui.Image?>();
    final decoder = BookImageDecoder(
      source,
      decodeValidated: (_) => gate.future,
    );
    source.reads = 0;
    final one = decoder.load(
      ContentKey(ContentKind.book, 'book', 1),
      'r0',
      () => false,
    );
    await Future<void>.delayed(Duration.zero);
    final two = decoder.load(
      ContentKey(ContentKind.book, 'book', 1),
      'r1',
      () => false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.reads, 1);
    gate.complete(null);
    await Future.wait([one, two]);
    expect(source.reads, 2);
    expect(decoder.peakActive, 1);
  });
}

class ImageSource extends BookContentRepository {
  ImageSource(ReaderFixture f, this.payload) : super(f.db, f.content.files);
  final BookImagePayload payload;
  int reads = 0;
  @override
  Future<BookImagePayload?> image(
    ContentKey key,
    String resourceId, {
    bool Function()? cancelled,
  }) async {
    reads++;
    return payload;
  }
}
