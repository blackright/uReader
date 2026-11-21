import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/listening/french_text_normalizer.dart';

void main() {
  const normalizer = FrenchTextNormalizer();
  test('Entrées bornées et UTF-16 valide avant préparation', () {
    expect(() => normalizer.normalize('a' * 4097), throwsArgumentError);
    expect(
      () => normalizer.normalize(String.fromCharCode(0xd800)),
      throwsArgumentError,
    );
    expect(
      () => normalizer.normalize(String.fromCharCode(0xdc00)),
      throwsArgumentError,
    );
    expect(normalizer.normalize('a' * 4096).source.length, 4096);
  });
  test('Nombres, date et heure du diagnostic, texte source conservé', () {
    const source =
        'Le 12 avril 2026, à 9 h 30, nous achetons 3 pommes, '
        '2 poires et 250 grammes de fromage.';
    final result = normalizer.normalize(source);
    expect(result.source, source);
    expect(
      result.speech,
      'Le douze avril deux mille vingt-six, à neuf heures '
      'trente, nous achetons trois pommes, deux poires et deux cent cinquante '
      'grammes de fromage.',
    );
  });
  test('Accords et bornes des entiers', () {
    const cases = {
      '0': 'zéro',
      '21': 'vingt-et-un',
      '31': 'trente-et-un',
      '71': 'soixante-et-onze',
      '80': 'quatre-vingts',
      '81': 'quatre-vingt-un',
      '91': 'quatre-vingt-onze',
      '200': 'deux cents',
      '201': 'deux cent un',
      '1000': 'mille',
      '80000': 'quatre-vingt mille',
      '200000': 'deux cent mille',
      '1000000': 'un million',
      '200000000': 'deux cents millions',
      '999999999':
          'neuf cent quatre-vingt-dix-neuf millions neuf cent '
          'quatre-vingt-dix-neuf mille neuf cent quatre-vingt-dix-neuf',
    };
    for (final entry in cases.entries) {
      expect(
        normalizer.normalize(entry.key).speech,
        entry.value,
        reason: entry.key,
      );
    }
  });
  test('Nombre composé lié, avec correspondance sur les chiffres source', () {
    final result = normalizer.normalize('📖 21 pommes.');
    expect(result.speech, '📖 vingt-et-un pommes.');
    final start = result.speech.indexOf('un');
    final range = result.sourceRange(start, start + 2);
    expect(result.source.substring(range.start, range.end), '21');
    expect(FrenchTextNormalizer.version, 'fr-numbers-v3');
  });
  test('Dates réelles et heures valides', () {
    expect(
      normalizer.normalize('1 janvier 2026 à 0h00.').speech,
      'premier janvier deux mille vingt-six à zéro heure.',
    );
    expect(
      normalizer.normalize('29 février 2024 à 1:05.').speech,
      'vingt-neuf février deux mille vingt-quatre à une heure cinq.',
    );
    for (final text in [
      '31 avril 2026',
      '29 février 2025',
      '25 h 70',
      '24:00',
      '00 avril 2026',
    ]) {
      expect(normalizer.normalize(text).speech, text);
    }
  });
  test('Notations ambiguës inchangées', () {
    for (final text in [
      '007',
      '-12',
      '+3',
      '1,25',
      '2.5',
      '12/04/2026',
      'v1.2.3',
      'ISBN978',
      'A12',
      '12B',
      '12-14',
      '1 000',
      '50%',
      '1000000000',
      'é12',
      '12é',
    ]) {
      expect(normalizer.normalize(text).speech, text, reason: text);
    }
    expect(normalizer.normalize('Bonjour !').speech, 'Bonjour !');
    expect(normalizer.normalize('').speech, '');
  });
  test(
    'Montants explicites en euros, sans flottants ni ambiguïté de version',
    () {
      for (final entry in {
        '12,50 euros': 'douze euros cinquante centimes',
        '7,50 euros': 'sept euros cinquante centimes',
        '1,01 euro': 'un euro un centime',
        '0,50 euros': 'zéro euro cinquante centimes',
        '12,00 euros': 'douze euros',
      }.entries) {
        expect(normalizer.normalize(entry.key).speech, entry.value);
      }
      for (final text in [
        '-12,50 euros',
        '12,500 euros',
        '007,50 euros',
        '1 234,50 euros',
        'v12,50 euros',
      ]) {
        expect(normalizer.normalize(text).speech, text);
      }
    },
  );
  test('Heures sans minutes et abréviations explicites de personnes', () {
    expect(
      normalizer.normalize('À 14 h. À 1h.').speech,
      'À quatorze heures. À une heure.',
    );
    expect(
      normalizer
          .normalize('Mme Martin rejoint M. Bernard. Le Dr Petit arrive, etc.')
          .speech,
      'madame Martin rejoint monsieur Bernard. Le docteur Petit arrive, et cetera',
    );
    expect(
      normalizer.normalize('Drive, drapeau, fichier. M.').speech,
      'Drive, drapeau, fichier. M.',
    );
    for (final text in ['25 h', '14 h 999', '-14 h', '24h00']) {
      expect(normalizer.normalize(text).speech, text);
    }
  });
  test('Les euros et heures développés gardent leurs plages UTF-16 source', () {
    const source = '📖 Mme Martin paie 12,50 euros à 14 h.';
    final result = normalizer.normalize(source);
    final cents = result.speech.indexOf('centimes');
    final money = result.sourceRange(cents, cents + 8);
    expect(source.substring(money.start, money.end), '12,50 euros');
    final hourStart = result.speech.indexOf('quatorze');
    final hours = result.sourceRange(hourStart, hourStart + 8);
    expect(source.substring(hours.start, hours.end), '14 h');
  });
  test('Correspondance UTF-16 : emoji, accent et remplacement entier', () {
    final result = normalizer.normalize('📖 Émile a 250 pommes.');
    final start = result.speech.indexOf('cinquante');
    final range = result.sourceRange(start, start + 'cinquante'.length);
    expect(result.source.substring(range.start, range.end), '250');
    final unchanged = result.speech.indexOf('pommes');
    final exact = result.sourceRange(unchanged, unchanged + 6);
    expect(result.source.substring(exact.start, exact.end), 'pommes');
    expect(() => result.sourceRange(1, 2), throwsArgumentError);
    expect(() => result.sourceRange(-1, 2), throwsArgumentError);
    expect(() => result.sourceRange(2, 2), throwsArgumentError);
    expect(() => result.spans.clear(), throwsUnsupportedError);
  });
  test('Les plages couvrent intégralement source et synthèse', () {
    final result = normalizer.normalize(
      '📖 3 pommes à 9h30, le 12 avril 2026.',
    );
    var sourceEnd = 0;
    var speechEnd = 0;
    for (final span in result.spans) {
      expect(span.sourceStart, sourceEnd);
      expect(span.speechStart, speechEnd);
      expect(span.sourceEnd, greaterThan(span.sourceStart));
      expect(span.speechEnd, greaterThan(span.speechStart));
      sourceEnd = span.sourceEnd;
      speechEnd = span.speechEnd;
    }
    expect(sourceEnd, result.source.length);
    expect(speechEnd, result.speech.length);
    final all = result.sourceRange(0, result.speech.length);
    expect(all.start, 0);
    expect(all.end, result.source.length);
  });
}
