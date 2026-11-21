import 'package:flutter/services.dart';

import '../../domain/books.dart';
import 'epub_package_parser.dart';
import 'request_identity.dart';

class ResolvedBookLink {
  const ResolvedBookLink({this.resource, this.fragment = '', this.external});
  final String? resource;
  final String fragment;
  final Uri? external;
}

abstract final class BookLinkResolver {
  static ResolvedBookLink resolve(String base, String target) {
    if (target.isEmpty ||
        target.contains(RegExp(r'[\x00-\x20\x7f]')) ||
        target.contains(r'\')) {
      throw const BookFailure(BookError.unsafeLink);
    }
    try {
      final uri = Uri.parse(target);
      if (uri.hasScheme || uri.hasAuthority) {
        if (uri.scheme != 'https' ||
            !uri.hasAuthority ||
            uri.host.isEmpty ||
            uri.port > 65535 ||
            uri.userInfo.isNotEmpty ||
            RegExp(
              r'%(?:0[0-9a-f]|1[0-9a-f]|7f|5c)',
              caseSensitive: false,
            ).hasMatch(target)) {
          throw const BookFailure(BookError.unsafeLink);
        }
        return ResolvedBookLink(external: uri);
      }
      final fragment = Uri.decodeComponent(uri.fragment);
      if (fragment.contains('%') ||
          fragment.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const BookFailure(BookError.unsafeLink);
      }
      return ResolvedBookLink(
        resource: resolveEpubReference(base, target),
        fragment: fragment,
      );
    } on BookFailure {
      rethrow;
    } catch (_) {
      throw const BookFailure(BookError.unsafeLink);
    }
  }
}

class BookExternalLauncher {
  BookExternalLauncher({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.ureader.prototype/epub/v1');
  final MethodChannel _channel;
  int _sequence = 0;
  final _client = newEpubClientId();
  Future<bool> open(Uri url, {required bool userConfirmed}) async {
    if (!userConfirmed) throw const BookFailure(BookError.unsafeLink);
    final resolved = BookLinkResolver.resolve(
      'OPS/chapter.xhtml',
      url.toString(),
    );
    if (resolved.external == null) {
      throw const BookFailure(BookError.unsafeLink);
    }
    final id = 'external-$_client-${++_sequence}';
    try {
      final reply = await _channel.invokeMethod<Object?>('openExternal', {
        'protocolVersion': 1,
        'requestId': id,
        'operationId': id,
        'generation': 1,
        'payload': {'url': url.toString(), 'userConfirmed': true},
      });
      if (reply is! Map ||
          reply['protocolVersion'] != 1 ||
          reply['requestId'] != id ||
          reply['operationId'] != id ||
          reply['generation'] != 1 ||
          reply.containsKey('error') ||
          reply['result'] is! Map ||
          (reply['result'] as Map)['opened'] is! bool) {
        throw const BookFailure(BookError.unsafeLink);
      }
      return (reply['result'] as Map)['opened'] == true;
    } on BookFailure {
      rethrow;
    } catch (_) {
      throw const BookFailure(BookError.sourceUnavailable);
    }
  }
}
