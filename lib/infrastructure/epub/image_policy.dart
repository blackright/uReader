import 'epub_limits.dart';

class ImageInspection {
  const ImageInspection(this.usable, this.width, this.height, this.format);
  final bool usable;
  final int? width, height;
  final String? format;
}

abstract final class ImagePolicy {
  static bool dimensionsAllowed(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= EpubLimits.imageDimension &&
      height <= EpubLimits.imageDimension &&
      width <= EpubLimits.imagePixels ~/ height;

  /// Header inspection only; the renderer must also handle a later decode failure.
  /// Pass a bounded prefix, never allocate pixel buffers here.
  static ImageInspection inspect(List<int> prefix) {
    const rejected = ImageInspection(false, null, null, null);
    if (prefix.length > EpubLimits.markupBytes) return rejected;
    int be16(int p) => prefix[p] * 256 + prefix[p + 1];
    int be32(int p) => be16(p) * 65536 + be16(p + 2);
    if (prefix.length >= 33 &&
        prefix.take(8).join(',') == '137,80,78,71,13,10,26,10' &&
        be32(8) == 13 &&
        String.fromCharCodes(prefix.sublist(12, 16)) == 'IHDR') {
      final width = be32(16), height = be32(20);
      const depths = {
        0: [1, 2, 4, 8, 16],
        2: [8, 16],
        3: [1, 2, 4, 8],
        4: [8, 16],
        6: [8, 16],
      };
      if (!(depths[prefix[25]]?.contains(prefix[24]) ?? false) ||
          prefix[26] != 0 ||
          prefix[27] != 0 ||
          prefix[28] > 1) {
        return rejected;
      }
      if (!dimensionsAllowed(width, height)) {
        return ImageInspection(false, width, height, 'png');
      }
      var crc = 0xffffffff;
      for (var i = 12; i < 29; i++) {
        crc ^= prefix[i];
        for (var bit = 0; bit < 8; bit++) {
          crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
        }
      }
      if (((crc ^ 0xffffffff) & 0xffffffff) != be32(29)) return rejected;
      return ImageInspection(
        dimensionsAllowed(width, height),
        width,
        height,
        'png',
      );
    }
    if (prefix.length < 4 || prefix[0] != 255 || prefix[1] != 216) {
      return rejected;
    }
    var p = 2;
    int? width, height;
    while (p + 4 <= prefix.length) {
      if (prefix[p++] != 255) return rejected;
      while (p < prefix.length && prefix[p] == 255) {
        p++;
      }
      if (p + 2 >= prefix.length) return rejected;
      final marker = prefix[p++];
      if (marker == 217 || marker == 0) return rejected;
      final length = be16(p);
      if (length < 2 || p + length > prefix.length) return rejected;
      if (marker == 218) {
        return width != null && height != null
            ? ImageInspection(
                dimensionsAllowed(width, height),
                width,
                height,
                'jpeg',
              )
            : rejected;
      }
      if ([
        192,
        193,
        194,
        195,
        197,
        198,
        199,
        201,
        202,
        203,
        205,
        206,
        207,
      ].contains(marker)) {
        if (length < 8 ||
            width != null ||
            prefix[p + 2] != 8 ||
            prefix[p + 7] < 1 ||
            prefix[p + 7] > 4 ||
            length != 8 + 3 * prefix[p + 7]) {
          return rejected;
        }
        height = be16(p + 3);
        width = be16(p + 5);
        if (!dimensionsAllowed(width, height)) {
          return ImageInspection(false, width, height, 'jpeg');
        }
      }
      p += length;
    }
    return rejected;
  }
}
