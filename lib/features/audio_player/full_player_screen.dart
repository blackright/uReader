import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/reader_experience.dart';
import '../listening/playback_coordinator.dart';
import '../book_reader/book_image_view.dart';
import 'player_presenter.dart';
import 'simple_player.dart';
import 'content_seek_sheet.dart';

class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({
    super.key,
    required this.presenter,
    required this.onShowHeard,
  });
  final PlayerPresenter presenter;
  final Future<void> Function(Book, BookLocator) onShowHeard;
  Future<void> _seek(BuildContext context) async {
    final book = presenter.book;
    if (book == null) return;
    final generation = presenter.owner.sessionGeneration;
    final chosen = await showModalBottomSheet<BookLocator>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContentSeekSheet(
        book: book,
        source: presenter.source,
        initial: presenter.target,
      ),
    );
    if (chosen != null) await presenter.seek(chosen, generation: generation);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: presenter,
    builder: (context, _) {
      if (presenter.owner.bookKey == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Lecture audio')),
          body: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune lecture en cours. Choisissez un livre dans la bibliothèque.',
              ),
            ),
          ),
        );
      }
      final book = presenter.book, heard = presenter.heard;
      final playing =
          presenter.state == PlaybackState.playing ||
          presenter.state == PlaybackState.preparing;
      final showHeard = book == null || heard == null
          ? null
          : () => onShowHeard(book, heard);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lecture audio'),
          leading: IconButton(
            tooltip: 'Réduire le player',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          actions: [
            TextButton(
              onPressed: presenter.owner.stop,
              child: const Text('Arrêter'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (book == null)
                  const Text(
                    'Les informations du livre sont en préparation. Le texte reste disponible.',
                  )
                else ...[
                  if (presenter.presentation == AudioPresentation.full)
                    Center(
                      child: PlayerCover(
                        details: presenter.details!,
                        presenter: presenter,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.authors.isEmpty
                        ? 'Auteur non renseigné'
                        : book.authors.join(', '),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    presenter.chapterTitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(presenter.status)),
                if (presenter.notice != null)
                  Semantics(liveRegion: true, child: Text(presenter.notice!)),
                const SizedBox(height: 24),
                Text(
                  presenter.heardProgress == null
                      ? 'Passage entendu : en attente du premier son'
                      : 'Passage entendu : ${(presenter.heardProgress! * 100).floor()} % du contenu',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: presenter.heardProgress ?? 0,
                  minHeight: 4,
                  semanticsLabel: 'Progression du passage entendu',
                ),
                const SizedBox(height: 12),
                if (presenter.targetProgress != null)
                  Text(
                    'Cible audio : ${(presenter.targetProgress! * 100).floor()} % du contenu',
                  ),
                const SizedBox(height: 24),
                if (presenter.presentation == AudioPresentation.simple)
                  SimplePlayer(
                    presenter: presenter,
                    onSeek: () => _seek(context),
                    onShowHeard: showHeard,
                  )
                else ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Paragraphe précédent',
                        onPressed: () => presenter.move(false),
                        icon: const Icon(Icons.skip_previous_rounded, size: 30),
                      ),
                      IconButton.filled(
                        tooltip: playing ? 'Pause' : 'Lecture',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(72, 72),
                        ),
                        onPressed: presenter.playPause,
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 40,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Paragraphe suivant',
                        onPressed: () => presenter.move(true),
                        icon: const Icon(Icons.skip_next_rounded, size: 30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: book == null ? null : () => _seek(context),
                    icon: const Icon(Icons.tune),
                    label: const Text('Choisir un passage'),
                  ),
                  TextButton(
                    onPressed: showHeard,
                    child: const Text('Afficher le passage entendu'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Présentation du player'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in AudioPresentation.values)
                      ChoiceChip(
                        label: Text(
                          value == AudioPresentation.full
                              ? 'Complet'
                              : 'Simplifié',
                        ),
                        selected: presenter.presentation == value,
                        onSelected: (_) => presenter.changePresentation(value),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class PlayerCover extends StatefulWidget {
  const PlayerCover({
    super.key,
    required this.details,
    required this.presenter,
  });
  final PlayerBook details;
  final PlayerPresenter presenter;
  @override
  State<PlayerCover> createState() => _PlayerCoverState();
}

class _PlayerCoverState extends State<PlayerCover> {
  late BookImageDecoder decoder = BookImageDecoder(widget.presenter.source);
  PlayerBook get details => widget.details;
  @override
  void didUpdateWidget(PlayerCover old) {
    super.didUpdateWidget(old);
    if (old.presenter.source != widget.presenter.source) {
      decoder = BookImageDecoder(widget.presenter.source);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    height: 260,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: details.coverResource == null
          ? ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF365B4B), Color(0xFF203D31)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_stories,
                      color: Color(0xFFEEE8DA),
                      size: 32,
                    ),
                    const Spacer(),
                    Text(
                      details.book.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: Color(0xFFF7F3EA),
                        fontFamily: 'serif',
                        fontSize: 24,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            )
          : BookImageView(
              block: BookBlock(
                key: details.book.key,
                chapterId: 'c0',
                id: 'player-cover',
                ordinal: 0,
                kind: BookBlockKind.image,
                text: '',
                resourceId: details.coverResource,
                alternative: 'Couverture du livre',
              ),
              decoder: decoder,
              viewportHeight: 260,
            ),
    ),
  );
}
