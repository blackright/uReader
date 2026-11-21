import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/book_link_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'external launcher requires confirmation and correlated native reply',
    () async {
      const channel = MethodChannel('us2-links-test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            return {
              ...args,
              'result': {'opened': true},
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final launcher = BookExternalLauncher(channel: channel);
      final url = Uri.parse('https://example.org/read?q=1');
      await expectLater(
        launcher.open(url, userConfirmed: false),
        throwsA(isA<BookFailure>()),
      );
      expect(calls, isEmpty);
      expect(await launcher.open(url, userConfirmed: true), isTrue);
      expect(calls.single.method, 'openExternal');
      expect((calls.single.arguments as Map)['payload'], {
        'url': url.toString(),
        'userConfirmed': true,
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'result': {'opened': true},
            },
          );
      await expectLater(
        launcher.open(url, userConfirmed: true),
        throwsA(isA<BookFailure>()),
      );
    },
  );
  test(
    'relative parent references stay in container and fragments decode once',
    () {
      final link = BookLinkResolver.resolve(
        'OPS/text/c1.xhtml',
        '../c2.xhtml#note%20un',
      );
      expect(link.resource, 'OPS/c2.xhtml');
      expect(link.fragment, 'note un');
      expect(link.external, isNull);
    },
  );
  test('unsafe destinations and ambiguous encodings never activate', () {
    for (final url in [
      '../../../outside',
      'file:///secret',
      'javascript:alert(1)',
      'http://example.org',
      '//example.org',
      'https://user:secret@example.org',
      'https://example.org:65536',
      'https://example.org/%0aX',
      '../c.xhtml#%252e',
    ]) {
      expect(
        () => BookLinkResolver.resolve('OPS/text/c1.xhtml', url),
        throwsA(isA<BookFailure>()),
        reason: url,
      );
    }
    expect(
      BookLinkResolver.resolve(
        'OPS/c.xhtml',
        'https://example.org/read?q=1',
      ).external.toString(),
      'https://example.org/read?q=1',
    );
  });
}
