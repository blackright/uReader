import 'app_error.dart';

enum ReadingMode { visual, audio }

class Passage {
  Passage({
    required this.id,
    required this.textId,
    required this.ordinal,
    required this.text,
  }) {
    requireIdentifier(id);
    requireIdentifier(textId);
    if (ordinal < 0 || text.trim().isEmpty) {
      throw const AppError(ErrorCode.invalidContent);
    }
  }
  final String id;
  final String textId;
  final int ordinal;
  final String text;
}

class DemoText {
  DemoText({
    required this.id,
    required this.corpusVersion,
    required this.title,
    required List<Passage> passages,
    this.language = 'fr',
  }) : passages = List.unmodifiable(passages) {
    requireIdentifier(id);
    if (corpusVersion < 1 ||
        title.trim().isEmpty ||
        passages.isEmpty ||
        language != 'fr') {
      throw const AppError(ErrorCode.invalidContent);
    }
    final ids = <String>{};
    for (var i = 0; i < passages.length; i++) {
      final p = passages[i];
      if (p.textId != id || p.ordinal != i || !ids.add(p.id)) {
        throw const AppError(ErrorCode.invalidContent);
      }
    }
  }
  final String id;
  final int corpusVersion;
  final String title;
  final String language;
  final List<Passage> passages;

  void validate(Locator locator) {
    if (locator.textId != id || locator.corpusVersion != corpusVersion) {
      throw const AppError(ErrorCode.invalidLocator);
    }
    final matches = passages.where((p) => p.id == locator.passageId);
    if (matches.isEmpty) throw const AppError(ErrorCode.invalidLocator);
    final text = matches.single.text;
    final offset = locator.offsetUtf16;
    if (offset < 0 ||
        offset > text.length ||
        (offset > 0 &&
            offset < text.length &&
            text.codeUnitAt(offset - 1) >= 0xd800 &&
            text.codeUnitAt(offset - 1) <= 0xdbff &&
            text.codeUnitAt(offset) >= 0xdc00 &&
            text.codeUnitAt(offset) <= 0xdfff)) {
      throw const AppError(ErrorCode.invalidLocator);
    }
  }
}

class Locator {
  Locator({
    required this.textId,
    required this.corpusVersion,
    required this.passageId,
    required this.offsetUtf16,
  }) {
    requireIdentifier(textId);
    requireIdentifier(passageId);
    if (corpusVersion < 1 || offsetUtf16 < 0) {
      throw const AppError(ErrorCode.invalidLocator);
    }
  }
  final String textId;
  final int corpusVersion;
  final String passageId;
  final int offsetUtf16;
}

class ResumePosition {
  const ResumePosition({
    required this.locator,
    required this.mode,
    required this.revision,
    required this.updatedAt,
  });
  final Locator locator;
  final ReadingMode mode;
  final int revision;
  final DateTime updatedAt;
}

class SessionToken {
  SessionToken(this.sessionId, this.generation) {
    requireIdentifier(sessionId);
    if (generation < 0) throw const AppError(ErrorCode.invalidMessage);
  }
  final String sessionId;
  final int generation;
  bool matches(SessionToken other) =>
      sessionId == other.sessionId && generation == other.generation;
}
