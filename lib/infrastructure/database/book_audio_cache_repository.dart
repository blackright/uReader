import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/books.dart';
import '../../domain/ports.dart';
import '../../domain/storage.dart';
import '../../features/listening/french_text_normalizer.dart';
import '../files/audio_cache.dart';
import 'prototype_database.dart';

/// Index only: the private file store owns paths and enforces active WAV leases.
/// Alignment sidecars share that WAV lease and removal boundary through AudioCache;
/// no independent index entry can survive a targeted book purge.
class BookAudioCacheRepository {
  BookAudioCacheRepository(this.db);
  final PrototypeDatabase db;
  Future<void> record(
    String key,
    SpeechRequest request,
    SpeechOutput output,
    BundleDescriptor bundle,
  ) async {
    final owner = request.bookOwner;
    if (owner == null) return;
    if (owner.kind != ContentKind.book ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const BookFailure(BookError.invalidContent);
    }
    await db.transaction(() async {
      final ready = await db
          .customSelect(
            "SELECT 1 FROM books WHERE book_id=? AND projection_version=? AND state='ready'",
            variables: [Variable(owner.id), Variable(owner.version)],
          )
          .get();
      if (ready.length != 1) throw const BookFailure(BookError.invalidContent);
      await db.customStatement(
        'INSERT OR REPLACE INTO book_audio_cache VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          key,
          owner.id,
          owner.version,
          request.voiceId,
          bundle.id,
          bundle.version,
          FrenchTextNormalizer.version,
          jsonEncode({
            'block': request.start.passageId,
            'start': request.start.offsetUtf16,
            'end': request.end.offsetUtf16,
          }),
          output.byteSize,
          'cache/audio/$key.wav',
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<void> forget(String key) => db.customStatement(
    'DELETE FROM book_audio_cache WHERE cache_key=?',
    [key],
  );
  Future<void> purge(ContentKey owner, AudioCache cache) async {
    while (true) {
      final rows = await db
          .customSelect(
            'SELECT cache_key FROM book_audio_cache WHERE book_id=? AND projection_version=? ORDER BY cache_key LIMIT 64',
            variables: [Variable(owner.id), Variable(owner.version)],
          )
          .get();
      if (rows.isEmpty) return;
      for (final row in rows) {
        final key = row.read<String>('cache_key');
        await cache.remove(
          key,
        ); // Refuses a leased file; retain index if removal fails.
        await forget(key);
      }
    }
  }
}
