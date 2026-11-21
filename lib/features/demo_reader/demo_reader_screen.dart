import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/content.dart';
import '../listening/playback_coordinator.dart';
import '../listening/playback_controls.dart';
import 'corpus_repository.dart';
import 'reader_controller.dart';

class DemoReaderScreen extends StatefulWidget {
  const DemoReaderScreen({
    super.key,
    required this.corpus,
    this.playback,
    this.reader,
  });
  final CorpusRepository corpus;
  final PlaybackCoordinator? playback;
  final ReaderController? reader;
  @override
  State<DemoReaderScreen> createState() => _DemoReaderScreenState();
}

class _DemoReaderScreenState extends State<DemoReaderScreen> {
  late final ReaderController _reader =
      widget.reader ??
      ReaderController(corpus: widget.corpus, playback: widget.playback);
  late final Future<List<CorpusEntry>> _entries = _reader.load().then((
    entries,
  ) {
    _reveal();
    return entries;
  });
  final _scroll = ScrollController();
  final _heading = FocusNode();
  final _passages = <String, GlobalKey>{};

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final locator = _reader.visualLocator;
      final target = locator == null
          ? null
          : _passages['${locator.textId}/${locator.passageId}']?.currentContext;
      if (target != null) {
        unawaited(Scrollable.ensureVisible(target, alignment: 0.1));
      }
    });
  }

  Future<void> _select(CorpusEntry? entry) async {
    await _reader.selectText(entry);
    if (!mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _heading.requestFocus();
    _reveal();
  }

  @override
  void dispose() {
    if (widget.reader == null) _reader.dispose();
    _scroll.dispose();
    _heading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CorpusEntry>>(
    future: _entries,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Le corpus ne peut pas être ouvert. Le contenu est invalide.',
            semanticsLabel: 'Erreur : le corpus ne peut pas être ouvert.',
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: Text('Chargement des textes…'));
      }
      return ListenableBuilder(
        listenable: Listenable.merge([
          _reader,
          if (widget.playback != null) widget.playback!,
        ]),
        builder: (context, _) {
          final selected = _reader.selected;
          return ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(24),
            children: [
              if (selected != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _select(null),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Tous les textes'),
                  ),
                ),
              Focus(
                focusNode: _heading,
                child: Semantics(
                  header: true,
                  child: Text(
                    selected?.text.title ?? 'Choisir un texte',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              if (_reader.warning != null)
                Semantics(liveRegion: true, child: Text(_reader.warning!)),
              PlaybackControls(
                coordinator: widget.playback,
                text: selected?.text,
                onPlay: _reader.listen,
              ),
              if (widget.playback != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: widget.playback!.playedLocator == null
                        ? null
                        : () async {
                            await _reader.showSpokenPassage();
                            _reveal();
                          },
                    child: const Text('Afficher le passage entendu'),
                  ),
                ),
              if (selected == null)
                for (final entry in snapshot.data!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: OutlinedButton(
                      onPressed: () => _select(entry),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(16),
                      ),
                      child: Text(entry.text.title),
                    ),
                  )
              else ...[
                for (final passage in selected.text.passages)
                  Semantics(
                    selected: _reader.visualLocator?.passageId == passage.id,
                    child: Padding(
                      key: _passages.putIfAbsent(
                        '${selected.text.id}/${passage.id}',
                        GlobalKey.new,
                      ),
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await _reader.selectPassage(
                                    Locator(
                                      textId: selected.text.id,
                                      corpusVersion:
                                          selected.text.corpusVersion,
                                      passageId: passage.id,
                                      offsetUtf16: 0,
                                    ),
                                  );
                                  _reveal();
                                },
                                child: Text(
                                  'Lire le paragraphe ${passage.ordinal + 1}',
                                ),
                              ),
                              if (widget.playback != null)
                                OutlinedButton(
                                  onPressed: () => _reader.listenHere(
                                    Locator(
                                      textId: selected.text.id,
                                      corpusVersion:
                                          selected.text.corpusVersion,
                                      passageId: passage.id,
                                      offsetUtf16: 0,
                                    ),
                                  ),
                                  child: Text(
                                    'Écouter ici — paragraphe ${passage.ordinal + 1}',
                                  ),
                                ),
                            ],
                          ),
                          SelectableText(
                            passage.text,
                            key: ValueKey(passage.id),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  selected.attribution,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      );
    },
  );
}
