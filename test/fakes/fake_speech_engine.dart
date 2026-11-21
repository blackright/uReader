import 'dart:async';

import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';

/// Simulation de protocole uniquement : ne produit aucun son.
class FakeSpeechEngine implements SpeechEngine {
  final _events = StreamController<SpeechEvent>.broadcast(sync: true);
  final _requests = <String, SpeechRequest>{};
  final _cancelled = <String>{};
  bool _disposed = false;
  bool _loaded = false;
  @override
  Stream<SpeechEvent> get events => _events.stream;
  @override
  Future<SpeechCapabilities> capabilities() async => SpeechCapabilities(
    languages: _loaded ? ['fr-test'] : [],
    voices: _loaded ? ['fake-voice'] : [],
  );
  @override
  Future<void> loadBundle(BundleDescriptor bundle) async {
    if (_disposed) throw const AppError(ErrorCode.engineUnavailable);
    _loaded = true;
  }

  @override
  Future<void> synthesize(SpeechRequest request) async {
    if (_disposed || !_loaded) {
      throw const AppError(ErrorCode.engineUnavailable);
    }
    if (_requests.containsKey(request.requestId)) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    _requests[request.requestId] = request;
  }

  @override
  Future<void> cancel(SessionToken token) async {
    if (_disposed) return;
    for (final request in _requests.values.where(
      (r) => r.token.matches(token),
    )) {
      if (_cancelled.add(request.requestId)) {
        _events.add(
          SpeechEvent(
            requestId: request.requestId,
            token: token,
            kind: SpeechEventKind.cancelled,
          ),
        );
      }
    }
  }

  void complete(String requestId, {bool simulateLateResult = false}) {
    if (_disposed) return;
    final request = _requests[requestId];
    if (request == null ||
        (!simulateLateResult && _cancelled.contains(requestId))) {
      return;
    }
    _events.add(
      SpeechEvent(
        requestId: requestId,
        token: request.token,
        kind: SpeechEventKind.completed,
        output: SpeechOutput(
          audioHandle: 'fake-audio',
          sampleRate: 24000,
          channels: 1,
          encoding: AudioEncoding.pcm16,
          durationMs: 10,
          byteSize: 100,
          start: request.start,
          end: request.end,
        ),
      ),
    );
  }

  void fail(String requestId) {
    final request = _requests[requestId];
    if (request == null || _disposed) return;
    _events.add(
      SpeechEvent(
        requestId: requestId,
        token: request.token,
        kind: SpeechEventKind.failed,
        errorCode: ErrorCode.engineUnavailable,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _requests.clear();
    await _events.close();
  }
}
