import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/app_error.dart';
import '../../domain/content.dart';

class CorpusEntry {
  const CorpusEntry(
    this.text,
    this.category,
    this.transcript,
    this.attribution,
  );
  final DemoText text;
  final String category;
  final String transcript;
  final String attribution;
}

/// Corpus embarqué uniquement : aucun chargement de modèle ni accès réseau.
class CorpusRepository {
  CorpusRepository({Future<String> Function()? read})
    : _read =
          read ?? (() => rootBundle.loadString('assets/corpus/fr_demo.json'));
  final Future<String> Function() _read;
  Future<List<CorpusEntry>>? _loading;
  Future<List<CorpusEntry>> load() => _loading ??= _load();

  Future<List<CorpusEntry>> _load() async {
    try {
      final source = await _read();
      if (utf8.encode(source).length > 131072) {
        throw const AppError(ErrorCode.invalidContent);
      }
      final root = jsonDecode(source) as Map<String, dynamic>;
      if (root['schemaVersion'] != 1 ||
          root['corpusVersion'] != 1 ||
          root['language'] != 'fr') {
        throw const AppError(ErrorCode.invalidContent);
      }
      final rows = root['texts'] as List;
      if (rows.length != 10) throw const AppError(ErrorCode.invalidContent);
      final entries = <CorpusEntry>[];
      final ids = <String>{};
      final passageIds = <String>{};
      final counts = <String, int>{};
      for (final row in rows) {
        final data = row as Map<String, dynamic>;
        final id = data['id'] as String;
        if (!ids.add(id)) throw const AppError(ErrorCode.invalidContent);
        final passages = (data['passages'] as List).map((raw) {
          final p = raw as Map<String, dynamic>;
          final passage = Passage(
            id: p['id'] as String,
            textId: p['textId'] as String,
            ordinal: p['ordinal'] as int,
            text: p['text'] as String,
          );
          if (!passageIds.add(passage.id) || passage.text.length > 20000) {
            throw const AppError(ErrorCode.invalidContent);
          }
          return passage;
        }).toList();
        final text = DemoText(
          id: id,
          corpusVersion: 1,
          title: data['title'] as String,
          language: data['language'] as String,
          passages: passages,
        );
        final category = data['category'] as String;
        if (!{
              'narrative',
              'pronunciation',
              'multi_paragraph',
              'long_paragraph',
            }.contains(category) ||
            (category == 'multi_paragraph' && passages.length < 3) ||
            (category == 'long_paragraph' &&
                (passages.length != 1 || passages.single.text.length < 2000))) {
          throw const AppError(ErrorCode.invalidContent);
        }
        final transcript = data['referenceTranscript'] as String;
        final attribution = data['attribution'] as String;
        if (transcript != passages.map((p) => p.text).join('\n\n') ||
            attribution.trim().isEmpty) {
          throw const AppError(ErrorCode.invalidContent);
        }
        counts.update(category, (n) => n + 1, ifAbsent: () => 1);
        entries.add(CorpusEntry(text, category, transcript, attribution));
      }
      if (counts['narrative'] != 3 ||
          counts['pronunciation'] != 3 ||
          counts['multi_paragraph'] != 3 ||
          counts['long_paragraph'] != 1) {
        throw const AppError(ErrorCode.invalidContent);
      }
      return List.unmodifiable(entries);
    } catch (_) {
      throw const AppError(ErrorCode.invalidContent);
    }
  }
}
