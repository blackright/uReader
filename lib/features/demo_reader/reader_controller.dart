import 'package:flutter/foundation.dart';

import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../infrastructure/database/position_repository.dart';
import '../listening/playback_coordinator.dart';
import 'corpus_repository.dart';

class ReaderController extends ChangeNotifier {
  ReaderController({required this.corpus, this.positions, this.playback});
  final CorpusRepository corpus;
  final PositionRepository? positions;
  final PlaybackCoordinator? playback;
  List<CorpusEntry> entries = [];
  CorpusEntry? selected;
  Locator? visualLocator;
  String? warning;
  final _audio = <String, Locator>{};
  Future<List<CorpusEntry>>? _loading;
  Future<void> _selecting = Future.value();
  Future<void> waitForSelection() => _selecting;
  int _selection = 0;
  bool _closed = false;
  Future<List<CorpusEntry>> load() => _loading ??= _load();
  Locator beginning(DemoText text) => Locator(
    textId: text.id,
    corpusVersion: text.corpusVersion,
    passageId: text.passages.first.id,
    offsetUtf16: 0,
  );
  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<List<CorpusEntry>> _load() async {
    entries = await corpus.load();
    try {
      final last = await positions?.latestVisual?.call();
      if (last != null) {
        final matches = entries.where((e) => e.text.id == last.locator.textId);
        if (matches.isEmpty) {
          warning =
              'Le dernier texte n’est plus disponible. Choisissez un texte.';
        } else {
          await selectText(matches.single, save: false);
        }
      }
    } catch (_) {
      warning =
          'Le dernier passage ne peut pas être restauré. Choisissez un texte.';
    }
    _changed();
    return entries;
  }

  Future<void> selectText(CorpusEntry? entry, {bool save = true}) =>
      _selecting = _selectText(entry, save: save);

  Future<void> _selectText(CorpusEntry? entry, {bool save = true}) async {
    final selection = ++_selection;
    if (entry == null) {
      selected = null;
      visualLocator = null;
      _changed();
      return;
    }
    Locator visual = beginning(entry.text);
    warning = null;
    try {
      final saved = await positions?.read(entry.text, ReadingMode.visual);
      visual = saved?.locator ?? visual;
    } catch (_) {
      warning = 'Passage visuel incompatible ou indisponible : retour au début du texte.';
    }
    try {
      final saved = await positions?.read(entry.text, ReadingMode.audio);
      if (saved != null) _audio[entry.text.id] = saved.locator;
    } catch (_) {
      _audio.remove(entry.text.id);
      warning = 'Repère audio incompatible ou indisponible. La reprise utilisera le passage visuel ; sa sauvegarde peut échouer.';
    }
    if (_closed || selection != _selection) return;
    selected = entry;
    visualLocator = visual;
    _changed();
    if (save) await _saveVisual(entry.text, visual, selection);
  }

  Future<void> _saveVisual(
    DemoText text,
    Locator locator,
    int selection,
  ) async {
    try {
      await positions?.save(
        text,
        locator,
        ReadingMode.visual,
        isCurrent: () => !_closed && selection == _selection,
      );
    } catch (_) {
      if (selection == _selection) {
        warning = 'Le passage visuel n’a pas été sauvegardé. La lecture reste possible.';
        _changed();
      }
    }
  }

  Future<void> selectPassage(Locator locator) async {
    final text = selected?.text;
    if (text == null) throw const AppError(ErrorCode.invalidLocator);
    text.validate(locator);
    final selection = ++_selection;
    visualLocator = locator;
    _changed();
    await _saveVisual(text, locator, selection);
  }

  Future<void> listen() {
    final text = selected?.text;
    final owner = playback;
    if (text == null || owner == null) return Future.value();
    if (owner.textId == text.id && owner.state == PlaybackState.paused) {
      return owner.resume();
    }
    final durable = owner.durableLocator;
    final from = durable?.textId == text.id
        ? durable
        : _audio[text.id] ?? visualLocator;
    return owner.play(text, from: from);
  }

  Future<void> listenHere(Locator locator) {
    final text = selected?.text;
    if (text == null) throw const AppError(ErrorCode.invalidLocator);
    text.validate(locator);
    return playback?.play(text, from: locator) ?? Future.value();
  }

  Future<void> showSpokenPassage() async {
    final locator = playback?.playedLocator;
    if (locator == null) return;
    final matches = entries.where((e) => e.text.id == locator.textId);
    if (matches.isEmpty) return;
    await selectText(matches.single, save: false);
    if (selected?.text.id == locator.textId) await selectPassage(locator);
  }

  @override
  void dispose() {
    _closed = true;
    _selection++;
    super.dispose();
  }
}
