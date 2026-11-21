/// Local, conservative speech preparation. Never rewrites the displayed source.
class FrenchTextNormalizer {
  const FrenchTextNormalizer();

  static const version = 'fr-numbers-v3';
  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  static final _date = RegExp(
    r'(\d{1,2}) (janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre) (\d{4})',
    caseSensitive: false,
  );
  static final _time = RegExp(
    r'([+-]?\d{1,2})(?:[ \u00a0\u202f]*h(?:[ \u00a0\u202f]*(\d+))?|:(\d+))',
    caseSensitive: false,
  );
  static final _euros = RegExp(
    r'([+-]?\d{1,9}),(\d+)[ \u00a0\u202f]+euros?',
    caseSensitive: false,
  );
  static final _candidate = RegExp(
    '${_date.pattern}|${_time.pattern}|${_euros.pattern}|'
    r'Mme|M\.|Dr\.?|etc\.|[-+]?\d+(?:[.,:/-]\d+|[ \u00a0\u202f]\d{3})*%?',
    caseSensitive: false,
  );
  static final _identifier = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  NormalizedFrenchText normalize(String source, {int maxSourceUnits = 4096}) {
    if (maxSourceUnits < 1 ||
        maxSourceUnits > 8192 ||
        source.length > maxSourceUnits) {
      throw ArgumentError('Text exceeds preparation limit');
    }
    for (var i = 0; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= source.length ||
            source.codeUnitAt(i) < 0xdc00 ||
            source.codeUnitAt(i) > 0xdfff) {
          throw ArgumentError('Invalid UTF-16 source');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw ArgumentError('Invalid UTF-16 source');
      }
    }
    final output = StringBuffer();
    final spans = <SpeechTextSpan>[];
    void append(int start, int end, String text) {
      if (start == end) return;
      final speechStart = output.length;
      output.write(text);
      final replaced = text != source.substring(start, end);
      if (!replaced && spans.isNotEmpty && !spans.last.replaced) {
        final previous = spans.removeLast();
        spans.add(
          SpeechTextSpan(
            previous.sourceStart,
            end,
            previous.speechStart,
            output.length,
            false,
          ),
        );
        return;
      }
      spans.add(
        SpeechTextSpan(start, end, speechStart, output.length, replaced),
      );
    }

    var cursor = 0;
    for (final match in _candidate.allMatches(source)) {
      append(cursor, match.start, source.substring(cursor, match.start));
      final raw = match.group(0)!;
      final attached =
          (match.start > 0 &&
              _identifier.hasMatch(
                source.substring(match.start - 1, match.start),
              )) ||
          (match.end < source.length &&
              _identifier.hasMatch(source.substring(match.end, match.end + 1)));
      append(
        match.start,
        match.end,
        attached ? raw : _replace(raw, source.substring(match.end)),
      );
      cursor = match.end;
    }
    append(cursor, source.length, source.substring(cursor));
    return NormalizedFrenchText._(source, output.toString(), spans);
  }

  String _replace(String raw, String following) {
    final title = {
      'Mme': 'madame',
      'M.': 'monsieur',
      'Dr': 'docteur',
      'Dr.': 'docteur',
    }[raw];
    if (title != null) {
      return RegExp(r'^[ \u00a0\u202f]+[A-ZÀ-ÖØ-Þ]').hasMatch(following)
          ? title
          : raw;
    }
    if (raw.toLowerCase() == 'etc.') return 'et cetera';
    final euros = _euros.firstMatch(raw);
    if (euros != null && euros.group(0) == raw) {
      if (!RegExp(r'^(0|[1-9]\d{0,8})$').hasMatch(euros.group(1)!) ||
          euros.group(2)!.length != 2) {
        return raw;
      }
      final whole = int.parse(euros.group(1)!);
      final cents = int.parse(euros.group(2)!);
      return '${_number(whole)} euro${whole > 1 ? 's' : ''}'
          '${cents == 0 ? '' : ' ${_number(cents)} centime${cents > 1 ? 's' : ''}'}';
    }
    final date = _date.firstMatch(raw);
    if (date != null && date.group(0) == raw) {
      final day = int.parse(date.group(1)!);
      final month = _months.indexOf(date.group(2)!.toLowerCase()) + 1;
      final year = int.parse(date.group(3)!);
      final actual = DateTime.utc(year, month, day);
      if (year < 1000 ||
          actual.year != year ||
          actual.month != month ||
          actual.day != day ||
          date.group(1)!.startsWith('0')) {
        return raw;
      }
      return '${day == 1 ? 'premier' : _number(day)} '
          '${date.group(2)} ${_number(year)}';
    }
    final time = _time.firstMatch(raw);
    if (time != null && time.group(0) == raw) {
      if (!RegExp(r'^\d{1,2}$').hasMatch(time.group(1)!)) return raw;
      final hour = int.parse(time.group(1)!);
      final minuteText = time.group(2) ?? time.group(3);
      if (minuteText != null && minuteText.length != 2) return raw;
      final minute = int.parse(minuteText ?? '0');
      if (hour > 23 || minute > 59) return raw;
      final hours = hour == 1
          ? 'une heure'
          : '${_number(hour)} heure${hour > 1 ? 's' : ''}';
      return '$hours${minute == 0 ? '' : ' ${_number(minute)}'}';
    }
    if (!RegExp(r'^(0|[1-9]\d{0,8})$').hasMatch(raw)) return raw;
    return _number(int.parse(raw));
  }

  static const _small = [
    'zéro',
    'un',
    'deux',
    'trois',
    'quatre',
    'cinq',
    'six',
    'sept',
    'huit',
    'neuf',
    'dix',
    'onze',
    'douze',
    'treize',
    'quatorze',
    'quinze',
    'seize',
  ];
  static String _number(int n, {bool beforeThousand = false}) {
    if (n < 17) return _small[n];
    if (n < 20) return 'dix-${_small[n - 10]}';
    if (n < 70) {
      final tens = [
        '',
        '',
        'vingt',
        'trente',
        'quarante',
        'cinquante',
        'soixante',
      ][n ~/ 10];
      final unit = n % 10;
      return '$tens${unit == 0
          ? ''
          : unit == 1
          ? '-et-un'
          : '-${_small[unit]}'}';
    }
    if (n < 80) return 'soixante${n == 71 ? '-et-' : '-'}${_number(n - 60)}';
    if (n < 100) {
      return 'quatre-vingt${n == 80
          ? beforeThousand
                ? ''
                : 's'
          : '-${_number(n - 80)}'}';
    }
    if (n < 1000) {
      final hundreds = n ~/ 100;
      final rest = n % 100;
      return '${hundreds == 1 ? '' : '${_small[hundreds]} '}cent'
          '${hundreds > 1 && rest == 0 && !beforeThousand ? 's' : ''}'
          '${rest == 0 ? '' : ' ${_number(rest, beforeThousand: beforeThousand)}'}';
    }
    if (n < 1000000) {
      final thousands = n ~/ 1000;
      return '${thousands == 1 ? '' : '${_number(thousands, beforeThousand: true)} '}mille'
          '${n % 1000 == 0 ? '' : ' ${_number(n % 1000)}'}';
    }
    final millions = n ~/ 1000000;
    return '${_number(millions)} million${millions == 1 ? '' : 's'}'
        '${n % 1000000 == 0 ? '' : ' ${_number(n % 1000000)}'}';
  }
}

class SpeechTextSpan {
  const SpeechTextSpan(
    this.sourceStart,
    this.sourceEnd,
    this.speechStart,
    this.speechEnd,
    this.replaced,
  );
  final int sourceStart, sourceEnd, speechStart, speechEnd;
  final bool replaced;
}

class SourceTextRange {
  const SourceTextRange(this.start, this.end);
  final int start, end;
}

class NormalizedFrenchText {
  NormalizedFrenchText._(this.source, this.speech, List<SpeechTextSpan> spans)
    : spans = List.unmodifiable(spans);
  final String source, speech;
  final List<SpeechTextSpan> spans;

  /// A partial spoken replacement maps to its entire source expression.
  /// These are text coordinates, not word timestamps or playback progress.
  SourceTextRange sourceRange(int start, int end) {
    bool boundary(int offset) =>
        offset >= 0 &&
        offset <= speech.length &&
        !(offset > 0 &&
            offset < speech.length &&
            speech.codeUnitAt(offset - 1) >= 0xd800 &&
            speech.codeUnitAt(offset - 1) <= 0xdbff &&
            speech.codeUnitAt(offset) >= 0xdc00 &&
            speech.codeUnitAt(offset) <= 0xdfff);
    if (start >= end || !boundary(start) || !boundary(end)) {
      throw ArgumentError('Invalid UTF-16 speech range');
    }
    final first = spans.firstWhere((s) => s.speechEnd > start);
    final last = spans.lastWhere((s) => s.speechStart < end);
    return SourceTextRange(
      first.replaced
          ? first.sourceStart
          : first.sourceStart + start - first.speechStart,
      last.replaced
          ? last.sourceEnd
          : last.sourceStart + end - last.speechStart,
    );
  }
}
