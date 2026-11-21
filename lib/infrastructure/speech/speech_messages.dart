import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../domain/ports.dart';
import '../../domain/storage.dart';

enum SpeechCommand { capabilities, loadBundle, synthesize, cancel, dispose }

class SpeechMessage {
  SpeechMessage({
    required this.command,
    required this.requestId,
    this.token,
    Map<String, Object?> payload = const {},
  }) : payload = Map.unmodifiable({
         for (final entry in payload.entries)
           entry.key: entry.value is Map
               ? Map.unmodifiable(entry.value! as Map)
               : entry.value,
       }) {
    requireIdentifier(requestId);
    if ((command == SpeechCommand.synthesize ||
            command == SpeechCommand.cancel) &&
        token == null) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    _validatePayload(command, payload);
  }
  static bool supportsAlignment(Map<dynamic, dynamic> capabilities) {
    final value = capabilities['alignment'];
    return capabilities['protocolVersion'] == 1 &&
        value is Map &&
        value['version'] == 1 &&
        value['available'] == true;
  }

  static const protocolVersion = 1;
  static const commandChannel = 'com.ureader.prototype/speech/v1';
  static const eventChannel = 'com.ureader.prototype/speech_events/v1';
  final SpeechCommand command;
  final String requestId;
  final SessionToken? token;
  final Map<String, Object?> payload;

  static void _validatePayload(
    SpeechCommand command,
    Map<String, Object?> payload,
  ) {
    final allowed = switch (command) {
      SpeechCommand.capabilities ||
      SpeechCommand.cancel ||
      SpeechCommand.dispose => <String>{},
      SpeechCommand.loadBundle => {'bundleId', 'version', 'manifestDigest'},
      SpeechCommand.synthesize => {
        'text',
        'voiceId',
        'bundleId',
        'start',
        'end',
        'synthesisText',
      },
    };
    if (payload.keys.toSet().difference(allowed).isNotEmpty ||
        !payload.keys.toSet().containsAll(
          allowed.difference({'synthesisText'}),
        )) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    if (command == SpeechCommand.loadBundle) {
      for (final key in ['bundleId', 'version']) {
        if (payload[key] is! String) {
          throw const AppError(ErrorCode.invalidMessage);
        }
        requireIdentifier(payload[key]! as String);
      }
      final digest = payload['manifestDigest'];
      if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const AppError(ErrorCode.invalidMessage);
      }
    } else if (command == SpeechCommand.synthesize) {
      if (payload.containsKey('synthesisText') &&
          (payload['synthesisText'] is! String ||
              (payload['synthesisText']! as String).trim().isEmpty ||
              (payload['synthesisText']! as String).length > 4096)) {
        throw const AppError(ErrorCode.invalidMessage);
      }
      if (payload['text'] is! String ||
          (payload['text']! as String).trim().isEmpty ||
          payload['voiceId'] is! String ||
          payload['bundleId'] is! String) {
        throw const AppError(ErrorCode.invalidMessage);
      }
      requireIdentifier(payload['voiceId']! as String);
      requireIdentifier(payload['bundleId']! as String);
      final start = _locator(payload['start']);
      final end = _locator(payload['end']);
      if (start.textId != end.textId ||
          start.corpusVersion != end.corpusVersion ||
          start.passageId != end.passageId ||
          start.offsetUtf16 >= end.offsetUtf16 ||
          (payload['text']! as String).length !=
              end.offsetUtf16 - start.offsetUtf16) {
        throw const AppError(ErrorCode.invalidMessage);
      }
    }
  }

  static Locator _locator(Object? value) {
    if (value is! Map ||
        value.length != 4 ||
        value['textId'] is! String ||
        value['corpusVersion'] is! int ||
        value['passageId'] is! String ||
        value['offsetUtf16'] is! int) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    return Locator(
      textId: value['textId'] as String,
      corpusVersion: value['corpusVersion'] as int,
      passageId: value['passageId'] as String,
      offsetUtf16: value['offsetUtf16'] as int,
    );
  }

  Map<String, Object?> toWire() => {
    'protocolVersion': protocolVersion,
    'command': command.name,
    'requestId': requestId,
    if (token != null) 'sessionId': token!.sessionId,
    if (token != null) 'generation': token!.generation,
    'payload': payload,
  };

  factory SpeechMessage.fromWire(Map<String, Object?> wire) {
    if (wire.keys.any(
          (key) => !{
            'protocolVersion',
            'command',
            'requestId',
            'sessionId',
            'generation',
            'payload',
          }.contains(key),
        ) ||
        wire['protocolVersion'] != protocolVersion ||
        wire['command'] is! String ||
        wire['requestId'] is! String ||
        wire['payload'] is! Map) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    final matching = SpeechCommand.values.where(
      (c) => c.name == wire['command'],
    );
    if (matching.isEmpty ||
        (wire.containsKey('sessionId') != wire.containsKey('generation'))) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    SessionToken? token;
    if (wire.containsKey('sessionId')) {
      if (wire['sessionId'] is! String || wire['generation'] is! int) {
        throw const AppError(ErrorCode.invalidMessage);
      }
      token = SessionToken(
        wire['sessionId']! as String,
        wire['generation']! as int,
      );
    }
    final rawPayload = wire['payload']! as Map;
    if (rawPayload.keys.any((key) => key is! String)) {
      throw const AppError(ErrorCode.invalidMessage);
    }
    return SpeechMessage(
      command: matching.single,
      requestId: wire['requestId']! as String,
      token: token,
      payload: Map<String, Object?>.from(rawPayload),
    );
  }
}

/// Adaptateur de production explicite : jamais le faux moteur de tests.
class UnavailableSpeechEngine implements SpeechEngine {
  @override
  Future<SpeechCapabilities> capabilities() async =>
      SpeechCapabilities(languages: [], voices: []);
  @override
  Future<void> loadBundle(BundleDescriptor bundle) async {
    throw const AppError(ErrorCode.engineUnavailable);
  }

  @override
  Future<void> synthesize(SpeechRequest request) async {
    throw const AppError(ErrorCode.engineUnavailable);
  }

  @override
  Future<void> cancel(SessionToken token) async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<SpeechEvent> get events => const Stream.empty();
}
