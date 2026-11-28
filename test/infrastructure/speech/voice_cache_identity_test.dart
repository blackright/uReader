import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';

void main() {
  String key({String? bundle, String voice = 'estelle'}) => AudioCache.key(
    bundleDigest: bundle ?? 'a' * 64,
    voice: voice,
    text: 'Même texte préparé.',
    normalizerVersion: 'fr-numbers-v3',
  );

  test('switching to SIWIS cannot reuse an Estelle WAV', () {
    expect(key(voice: 'ff_siwis'), isNot(key()));
  });

  test(
    'a new trusted model or frontend digest invalidates the old voice render',
    () {
      expect(
        key(bundle: 'b' * 64, voice: 'ff_siwis'),
        isNot(key(voice: 'ff_siwis')),
      );
    },
  );
}
