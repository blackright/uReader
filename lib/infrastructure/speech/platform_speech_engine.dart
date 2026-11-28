import 'alignment_provider.dart';
import '../audio/alignment_cache.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../domain/ports.dart';
import '../../domain/storage.dart';
import '../../features/listening/french_text_normalizer.dart';
import '../../features/listening/prepared_text_map.dart';
import '../files/audio_cache.dart';
import '../audio/punctuation_audio.dart';
import 'speech_messages.dart';

class PlatformSpeechEngine implements SpeechEngine {
  PlatformSpeechEngine(
    this.cache, {
    MethodChannel? commands,
    MethodChannel? audio,
    Stream<dynamic>? nativeEvents,
    this.onPublished,
    this.alignmentProvider,
  }) : _commands =
           commands ?? const MethodChannel(SpeechMessage.commandChannel),
       _audio = audio ?? const MethodChannel('com.ureader.prototype/audio/v1') {
    _subscription =
        (nativeEvents ??
                const EventChannel(SpeechMessage.eventChannel)
                    .receiveBroadcastStream())
            .listen(
              (dynamic event) {
                _tail = _tail.then((_) => _event(event)).catchError((Object _) {
                  for (final request in _pending.values.toList()) {
                    _fail(request);
                  }
                });
              },
              onError: (Object _) {
                for (final request in _pending.values.toList()) {
                  _fail(request);
                }
              },
            );
  }
  final AudioCache cache;
  final AlignmentProvider? alignmentProvider;
  bool _alignmentNegotiated = false;
  final Future<void> Function(
    String,
    SpeechRequest,
    SpeechOutput,
    BundleDescriptor,
  )?
  onPublished;
  final MethodChannel _commands, _audio;
  final _events = StreamController<SpeechEvent>.broadcast();
  final _pending = <String, SpeechRequest>{};
  final _finished = <String, Completer<void>>{};
  final _cancelled = <String, int>{};
  late final StreamSubscription<dynamic> _subscription;
  Future<void> _tail = Future.value();
  Future<void>? _disposal;
  BundleDescriptor? _bundle;
  int _sequence = 0;
  @override
  Stream<SpeechEvent> get events => _events.stream;

  Future<Object?> _invoke(
    SpeechCommand command, {
    SessionToken? token,
    Map<String, Object?> payload = const {},
  }) async {
    try {
      final message = SpeechMessage(
        command: command,
        requestId: 'command-${++_sequence}',
        token: token,
        payload: payload,
      );
      return await _commands.invokeMethod<Object?>(
        command.name,
        message.toWire(),
      );
    } on PlatformException catch (error) {
      throw AppError(
        ErrorCode.values.firstWhere(
          (v) => v.name == error.code,
          orElse: () => ErrorCode.engineUnavailable,
        ),
      );
    } on MissingPluginException {
      throw const AppError(ErrorCode.engineUnavailable);
    }
  }

  @override
  Future<SpeechCapabilities> capabilities() async {
    final value = await _invoke(SpeechCommand.capabilities);
    if (value is! Map ||
        value['protocolVersion'] != 1 ||
        value['languages'] is! List ||
        value['voices'] is! List) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    _alignmentNegotiated = SpeechMessage.supportsAlignment(value);
    return SpeechCapabilities(
      languages: List<String>.from(value['languages'] as List),
      voices: List<String>.from(value['voices'] as List),
    );
  }

  @override
  Future<void> loadBundle(BundleDescriptor bundle) async {
    if (_disposal != null) throw const AppError(ErrorCode.engineUnavailable);
    await _invoke(
      SpeechCommand.loadBundle,
      payload: {
        'bundleId': bundle.id,
        'version': bundle.version,
        'manifestDigest': bundle.manifestDigest,
      },
    );
    _bundle = bundle;
    _alignmentNegotiated = false;
    if (alignmentProvider != null) {
      try {
        await capabilities();
      } on Exception {
        _alignmentNegotiated = false;
      }
    }
  }

  Future<int> tokenCount(String text) async {
    final value = await _audio.invokeMethod<int>('tokenCount', {
      'protocolVersion': 1,
      'text': text,
    });
    if (value == null || value < 1) {
      throw const AppError(ErrorCode.invalidContent);
    }
    return value;
  }

  String _cacheKey(SpeechRequest request) => AudioCache.key(
    bundleDigest: _bundle!.manifestDigest,
    voice: request.voiceId,
    text: jsonEncode([
      PreparedTextMap.version,
      request.synthesisText,
      request.start.textId,
      request.start.corpusVersion,
      request.start.passageId,
      request.start.offsetUtf16,
      request.end.offsetUtf16,
    ]),
    normalizerVersion: FrenchTextNormalizer.version,
    owner: request.bookOwner,
  );

  @override
  Future<void> synthesize(SpeechRequest request) async {
    if (_disposal != null || _bundle?.id != request.bundleId) {
      throw const AppError(ErrorCode.modelMissing);
    }
    if (_pending.isNotEmpty || !_current(request)) {
      throw const AppError(ErrorCode.resourceInUse);
    }
    _pending[request.requestId] = request;
    _finished[request.requestId] = Completer<void>();
    try {
      final key = _cacheKey(request);
      final cached = await cache.lookup(key, request.start, request.end);
      if (!_current(request)) {
        _finish(request.requestId);
        return;
      }
      if (cached != null) {
        await onPublished?.call(key, request, cached, _bundle!);
        _finish(request.requestId);
        if (_current(request)) {
          _events.add(
            SpeechEvent(
              requestId: request.requestId,
              token: request.token,
              kind: SpeechEventKind.completed,
              output: cached,
            ),
          );
        }
        return;
      }
    } catch (_) {
      _finish(request.requestId);
      rethrow;
    }
    final payload = {
      'text': request.text,
      if (request.synthesisText != request.text)
        'synthesisText': request.synthesisText,
      'voiceId': request.voiceId,
      'bundleId': request.bundleId,
      'start': _wireLocator(request.start),
      'end': _wireLocator(request.end),
    };
    final message = SpeechMessage(
      command: SpeechCommand.synthesize,
      requestId: request.requestId,
      token: request.token,
      payload: payload,
    );
    try {
      await _commands.invokeMethod<Object?>('synthesize', message.toWire());
    } catch (_) {
      _finish(request.requestId);
      rethrow;
    }
  }

  bool _current(SpeechRequest r) =>
      _disposal == null &&
      r.token.generation > (_cancelled[r.token.sessionId] ?? -1);
  void _finish(String id) {
    _pending.remove(id);
    _finished.remove(id)?.complete();
  }

  void _fail(SpeechRequest request) {
    if (!_events.isClosed) {
      _events.add(
        SpeechEvent(
          requestId: request.requestId,
          token: request.token,
          kind: SpeechEventKind.failed,
          errorCode: ErrorCode.engineUnavailable,
        ),
      );
    }
    _finish(request.requestId);
  }

  static Map<String, Object> _wireLocator(Locator v) => {
    'textId': v.textId,
    'corpusVersion': v.corpusVersion,
    'passageId': v.passageId,
    'offsetUtf16': v.offsetUtf16,
  };
  static bool _sameLocator(Object? value, Locator locator) =>
      value is Map &&
      value.length == 4 &&
      value['textId'] == locator.textId &&
      value['corpusVersion'] == locator.corpusVersion &&
      value['passageId'] == locator.passageId &&
      value['offsetUtf16'] == locator.offsetUtf16;

  Future<void> _release(String handle) => _audio.invokeMethod<void>(
    'releaseAudio',
    {'protocolVersion': 1, 'audioHandle': handle},
  );
  Future<void> _event(dynamic raw) async {
    if (raw is! Map || raw['protocolVersion'] != 1) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    final request = _pending[raw['requestId']];
    if (request == null) return;
    if (raw['sessionId'] != request.token.sessionId ||
        raw['generation'] != request.token.generation) {
      _fail(request);
      return;
    }
    if (raw['kind'] != 'completed') {
      final cancelled = raw['kind'] == 'cancelled' || !_current(request);
      _events.add(
        SpeechEvent(
          requestId: request.requestId,
          token: request.token,
          kind: cancelled ? SpeechEventKind.cancelled : SpeechEventKind.failed,
          errorCode: cancelled ? null : ErrorCode.engineUnavailable,
        ),
      );
      _finish(request.requestId);
      return;
    }
    final output = raw['output'];
    if (output is! Map ||
        output['audioHandle'] is! String ||
        !_sameLocator(output['start'], request.start) ||
        !_sameLocator(output['end'], request.end)) {
      _fail(request);
      return;
    }
    final handle = output['audioHandle'] as String;
    requireIdentifier(handle);
    String? key;
    var released = false;
    try {
      if (!_current(request)) return;
      final metadata = SpeechOutput(
        audioHandle: handle,
        sampleRate: output['sampleRate'] as int,
        channels: output['channels'] as int,
        encoding: AudioEncoding.values.byName(output['encoding'] as String),
        durationMs: output['durationMs'] as int,
        byteSize: output['byteSize'] as int,
        start: request.start,
        end: request.end,
      );
      final bytes = await _audio.invokeMethod<Uint8List>('readAudio', {
        'protocolVersion': 1,
        'audioHandle': handle,
      });
      if (bytes == null) throw const AppError(ErrorCode.invalidContent);
      if (!_current(request)) return;
      final punctuated = PunctuationAudio.apply(bytes, metadata, request.text);
      key = _cacheKey(request);
      await cache.publish(key, punctuated.bytes, punctuated.output);
      // Optional metadata failure never turns valid audio into a failed synthesis.
      if (_alignmentNegotiated && alignmentProvider != null) {
        try {
          final alignment = alignmentProvider!.resolve(
            native: output['alignment'],
            request: request,
            rawWav: bytes,
            publishedWav: punctuated.bytes,
          );
          if (alignment != null && _current(request)) {
            await AlignmentCache(cache.files).publish(key, alignment);
          }
        } on Exception {
          /* Audio remains available; follow stays unavailable. */
        } on ArgumentError {
          /* Invalid optional alignment is never adopted. */
        }
      }
      await onPublished?.call(key, request, punctuated.output, _bundle!);
      if (!_current(request)) {
        await cache.remove(key);
        return;
      }
      await _release(handle);
      released = true;
      _finish(request.requestId);
      if (!_current(request)) {
        await cache.remove(key);
        return;
      }
      _events.add(
        SpeechEvent(
          requestId: request.requestId,
          token: request.token,
          kind: SpeechEventKind.completed,
          output: SpeechOutput(
            audioHandle: key,
            sampleRate: metadata.sampleRate,
            channels: metadata.channels,
            encoding: metadata.encoding,
            durationMs: punctuated.output.durationMs,
            byteSize: punctuated.output.byteSize,
            start: request.start,
            end: request.end,
          ),
        ),
      );
    } catch (_) {
      if (key != null) {
        await cache.remove(key);
      }
      _fail(request);
    } finally {
      try {
        if (!released) await _release(handle);
      } finally {
        _finish(request.requestId);
      }
    }
  }

  @override
  Future<void> cancel(SessionToken token) async {
    if (_disposal != null) return;
    _cancelled[token.sessionId] = max(
      token.generation,
      _cancelled[token.sessionId] ?? -1,
    );
    final pending = [
      for (final r in _pending.values)
        if (r.token.sessionId == token.sessionId &&
            r.token.generation <= token.generation)
          _finished[r.requestId]!.future,
    ];
    await _invoke(SpeechCommand.cancel, token: token);
    await Future.wait(pending).timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> dispose() => _disposal ??= _close();

  Future<void> unloadBundle() async {
    await const MethodChannel('com.ureader.prototype/audio/v1')
        .invokeMethod<void>('releaseBundle', {'protocolVersion': 1});
    _bundle = null;
  }

  Future<void> _close() async {
    try {
      await _invoke(SpeechCommand.dispose);
    } finally {
      await _subscription.cancel();
      await _tail;
      for (final id in _pending.keys.toList()) {
        _finish(id);
      }
      await _events.close();
    }
  }
}
