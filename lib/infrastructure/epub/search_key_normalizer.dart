import 'package:flutter/services.dart';

import '../../domain/books.dart';
import 'request_identity.dart';

/// ICU normalization happens on Android only; no locale-dependent Dart fallback.
class SearchKeyNormalizer {
  SearchKeyNormalizer({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.ureader.prototype/epub/v1');
  final MethodChannel _channel;
  static const version = 1;
  int _sequence = 0;
  final _clientId = newEpubClientId();
  Future<String> normalize(String text) async {
    if (text.length > 16384) throw const BookFailure(BookError.limitExceeded);
    final id = 'search-$_clientId-${++_sequence}';
    try {
      final raw = await _channel.invokeMethod<Object?>('normalizeSearchKey', {
        'protocolVersion': 1,
        'requestId': id,
        'operationId': id,
        'generation': 1,
        'payload': {'text': text},
      });
      if (raw is! Map ||
          raw['protocolVersion'] != 1 ||
          raw['requestId'] != id ||
          raw['operationId'] != id ||
          raw['generation'] != 1 ||
          raw.containsKey('error') ||
          raw['result'] is! Map) {
        throw const BookFailure(BookError.invalidContent);
      }
      final key = (raw['result'] as Map)['key'];
      if (key is! String || key.length > 65536) {
        throw const BookFailure(BookError.limitExceeded);
      }
      return key;
    } on PlatformException {
      throw const BookFailure(BookError.sourceUnavailable);
    } on MissingPluginException {
      throw const BookFailure(BookError.sourceUnavailable);
    }
  }
}
