import 'word_alignment.dart';
import 'content.dart';
import 'storage.dart';
import 'app_error.dart';
import 'books.dart' show ContentKey;

abstract interface class PositionStore {
  Future<ResumePosition?> readPosition(String textId, ReadingMode mode);
  Future<ResumePosition> savePosition(
    DemoText text,
    Locator locator,
    ReadingMode mode, {
    required int expectedRevision,
    required DateTime updatedAt,
  });
}

abstract interface class PrototypeStore
    implements PositionStore, OperationJournal {
  Future<void> initialize();
  Future<void> close();
}

class SpeechCapabilities {
  SpeechCapabilities({
    required List<String> languages,
    required List<String> voices,
  }) : languages = List.unmodifiable(languages),
       voices = List.unmodifiable(voices);
  final List<String> languages;
  final List<String> voices;
}

class SpeechRequest {
  SpeechRequest({
    required this.requestId,
    required this.token,
    required this.start,
    required this.end,
    required this.text,
    required this.voiceId,
    required this.bundleId,
    String? synthesisText,
    this.bookOwner,
  }) : synthesisText = synthesisText ?? text {
    requireIdentifier(requestId);
    requireIdentifier(voiceId);
    requireIdentifier(bundleId);
    if (start.textId != end.textId ||
        start.corpusVersion != end.corpusVersion ||
        start.passageId != end.passageId ||
        start.offsetUtf16 >= end.offsetUtf16 ||
        text.trim().isEmpty ||
        text.length > 4096 ||
        this.synthesisText.trim().isEmpty ||
        this.synthesisText.length > 4096 ||
        text.length != end.offsetUtf16 - start.offsetUtf16) {
      throw const AppError(ErrorCode.invalidMessage);
    }
  }
  final String requestId;
  final SessionToken token;
  final Locator start;
  final Locator end;
  final String text;
  final String synthesisText;
  final ContentKey? bookOwner;
  final String voiceId;
  final String bundleId;
}

enum SpeechEventKind { completed, cancelled, failed }

enum AudioEncoding { pcm16, float32 }

class SpeechOutput {
  SpeechOutput({
    required this.audioHandle,
    required this.sampleRate,
    required this.channels,
    required this.encoding,
    required this.durationMs,
    required this.byteSize,
    required this.start,
    required this.end,
  }) {
    requireIdentifier(audioHandle);
    if (sampleRate <= 0 ||
        channels < 1 ||
        channels > 2 ||
        durationMs < 0 ||
        byteSize <= 0 ||
        start.textId != end.textId ||
        start.corpusVersion != end.corpusVersion ||
        start.passageId != end.passageId ||
        start.offsetUtf16 >= end.offsetUtf16) {
      throw const AppError(ErrorCode.invalidMessage);
    }
  }
  final String audioHandle;
  final int sampleRate;
  final int channels;
  final AudioEncoding encoding;
  final int durationMs;
  final int byteSize;
  final Locator start;
  final Locator end;
}

class SpeechEvent {
  SpeechEvent({
    required this.requestId,
    required this.token,
    required this.kind,
    this.output,
    this.errorCode,
  }) {
    requireIdentifier(requestId);
    if ((kind == SpeechEventKind.completed &&
            (output == null || errorCode != null)) ||
        (kind == SpeechEventKind.failed &&
            (errorCode == null || output != null)) ||
        (kind == SpeechEventKind.cancelled &&
            (output != null || errorCode != null))) {
      throw const AppError(ErrorCode.invalidMessage);
    }
  }
  final String requestId;
  final SessionToken token;
  final SpeechEventKind kind;
  final SpeechOutput? output;
  final ErrorCode? errorCode;
  String? get audioHandle => output?.audioHandle;
}

abstract interface class SpeechEngine {
  Future<SpeechCapabilities> capabilities();
  Future<void> loadBundle(BundleDescriptor bundle);
  Future<void> synthesize(SpeechRequest request);
  Future<void> cancel(SessionToken token);
  Future<void> dispose();
  Stream<SpeechEvent> get events;
}

enum PlayerEventKind { started, completed, interrupted }

class PlayerEvent {
  const PlayerEvent(this.kind, this.token);
  final PlayerEventKind kind;
  final SessionToken token;
}

abstract interface class AudioPlayer {
  Future<void> open(String audioHandle, SessionToken token);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
  Stream<PlayerEvent> get events;
}

/// Optional capability; legacy players and speech protocol v1 remain valid.
abstract interface class PlayerClock {
  Stream<PlayerClockSample> get clockSamples;
}

/// Optional bounded playlist capability. Legacy/fake players keep single-WAV semantics.
abstract interface class BufferedAudioPlayer implements AudioPlayer {
  Future<void> append(String audioHandle, SessionToken token);
  Future<void> retire(SessionToken token);
  bool contains(SessionToken token);
  bool isCurrent(SessionToken token);
}
