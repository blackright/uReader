import '../../domain/word_selection.dart';
import 'word_selection_source.dart';

import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../audio_player/content_seek_sheet.dart';
import '../listening/book_segment_cursor.dart';
import '../listening/content_source_adapter.dart';

class ReadingStart {
  const ReadingStart(this.locator, {this.word});
  final BookLocator locator;
  final WordSelection? word;
}

abstract final class ParagraphActions {
  static Future<ReadingStart?> show(
    BuildContext context, {
    required Book book,
    required ParagraphNavigationSource source,
    BookLocator? at,
    WordSelection? word,
    bool canListen = true,
    Future<String> Function(BookLocator)? onBookmark,
  }) async {
    final chosen =
        at ??
        await showModalBottomSheet<BookLocator>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ContentSeekSheet(
            book: book,
            source: source,
            confirmLabel: 'Choisir ce paragraphe',
          ),
        );
    if (chosen == null || !context.mounted) return null;
    final range = await BookParagraphCommands.resolve(
      BookSpeechContext(book.key, source),
      chosen,
    );
    final block = await source.block(book.key, range.start.blockId);
    if (!context.mounted) return null;
    String? bookmarkMessage;
    var selectedWord = word;
    var saving = false, selecting = false;
    final listen = await showDialog<ReadingStart>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialog).height * .78,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      selectedWord == null
                          ? 'Paragraphe sélectionné'
                          : 'Mot sélectionné',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(block.text.characters.take(240).toString()),
                  if (selectedWord != null) ...[
                    const SizedBox(height: 16),
                    Chip(label: Text(selectedWord!.text)),
                    if (!selectedWord!.canStart)
                      const Text(
                        'Le départ exact de ce mot est indisponible dans cette portion de texte ; vous pouvez choisir le début du paragraphe.',
                      ),
                    FilledButton(
                      onPressed:
                          !canListen ||
                              saving ||
                              selecting ||
                              !selectedWord!.canStart
                          ? null
                          : () => Navigator.pop(
                              dialog,
                              ReadingStart(
                                selectedWord!.start,
                                word: selectedWord,
                              ),
                            ),
                      child: const Text('Commencer à partir d’ici'),
                    ),
                  ],
                  TextButton(
                    onPressed: saving || selecting
                        ? null
                        : () async {
                            setLocal(() => selecting = true);
                            try {
                              final result = await chooseWord(
                                dialog,
                                source,
                                chosen,
                              );
                              if (dialog.mounted && result != null) {
                                setLocal(() => selectedWord = result);
                              }
                            } on BookFailure catch (failure) {
                              if (dialog.mounted) {
                                setLocal(
                                  () => bookmarkMessage = failure.message,
                                );
                              }
                            } finally {
                              if (dialog.mounted) {
                                setLocal(() => selecting = false);
                              }
                            }
                          },
                    child: const Text('Choisir un mot dans ce passage'),
                  ),
                  if (bookmarkMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(bookmarkMessage!),
                      ),
                    ),
                  if (!canListen)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'La narration française n’est pas disponible ici. Le texte reste consultable.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (onBookmark != null)
                    TextButton.icon(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(
                        saving ? 'Enregistrement…' : 'Ajouter un signet ici',
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              setLocal(() => saving = true);
                              String message;
                              try {
                                message = await onBookmark(range.start);
                              } catch (_) {
                                message = 'Le signet n’a pas pu être enregistré. Réessayez.';
                              }
                              if (dialog.mounted) {
                                setLocal(() {
                                  bookmarkMessage = message;
                                  saving = false;
                                });
                              }
                            },
                    ),
                  FilledButton(
                    onPressed: !canListen || saving || selecting
                        ? null
                        : () =>
                              Navigator.pop(dialog, ReadingStart(range.start)),
                    child: Text(
                      selectedWord == null
                          ? 'Écouter à partir d’ici'
                          : 'Commencer au début du paragraphe',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return listen;
  }

  static Future<WordSelection?> chooseWord(
    BuildContext context,
    ParagraphNavigationSource source,
    BookLocator at,
  ) async {
    var block = await source.block(at.key, at.blockId);
    final range = await source.paragraphAt(at);
    if (!context.mounted) return null;
    var offset = 0;
    String? error;
    var busy = false;
    return showModalBottomSheet<WordSelection>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) {
          final words = WordSelection.words
              .allMatches(block.text)
              .where((m) => m.start >= offset)
              .take(41)
              .toList();
          final more = words.length > 40;
          final visible = words.take(40).toList();
          return SafeArea(
            key: const ValueKey('word-choice-sheet'),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: ListView(
                children: [
                  const ListTile(
                    title: Text('Choisir un mot'),
                    subtitle: Text(
                      'La sélection reste silencieuse jusqu’à confirmation.',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Semantics(liveRegion: true, child: Text(error!)),
                    ),
                  for (final match in visible)
                    ListTile(
                      key: ValueKey('word-choice-${block.id}-${match.start}'),
                      title: Text(match.group(0)!),
                      subtitle: Text(
                        block.text.substring(
                          match.start,
                          (match.end + 55).clamp(0, block.text.length),
                        ),
                      ),
                      onTap: busy
                          ? null
                          : () async {
                              update(() {
                                busy = true;
                                error = null;
                              });
                              try {
                                final selection =
                                    await WordSelectionSource.resolve(
                                      source,
                                      BookLocator(
                                        key: block.key,
                                        chapterId: block.chapterId,
                                        blockId: block.id,
                                        offsetUtf16: match.start,
                                      ),
                                    );
                                if (sheet.mounted) {
                                  Navigator.pop(sheet, selection);
                                }
                              } on BookFailure catch (failure) {
                                if (sheet.mounted) {
                                  update(() => error = failure.message);
                                }
                              } finally {
                                if (sheet.mounted) update(() => busy = false);
                              }
                            },
                    ),
                  if (more)
                    TextButton(
                      onPressed: () => update(() => offset = words[40].start),
                      child: const Text('Mots suivants'),
                    ),
                  if (!more && block.ordinal < range.lastOrdinal)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              update(() {
                                busy = true;
                                error = null;
                              });
                              try {
                                final next = await source.window(
                                  block.key,
                                  1,
                                  after: BookCursor(
                                    key: block.key,
                                    generation: 1,
                                    nextOrdinal: block.ordinal + 1,
                                  ),
                                  maxBlocks: 1,
                                );
                                if (sheet.mounted && next.blocks.isNotEmpty) {
                                  update(() {
                                    block = next.blocks.first;
                                    offset = 0;
                                  });
                                }
                              } on BookFailure catch (failure) {
                                if (sheet.mounted) {
                                  update(() => error = failure.message);
                                }
                              } finally {
                                if (sheet.mounted) update(() => busy = false);
                              }
                            },
                      child: const Text('Suite du paragraphe'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
