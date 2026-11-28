import 'follow_controller.dart';
import '../../domain/word_selection.dart';
import 'word_selection_source.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/reader_theme.dart';
import 'reading_settings_sheet.dart';
import 'reader_chrome.dart';
import 'paragraph_actions.dart';
import 'bookmark_controller.dart';
import 'bookmarks_sheet.dart';
import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/reader_experience.dart';
import 'book_pagination_controller.dart';
import 'paged_book_view.dart';
import 'reader_layout.dart';
import '../../infrastructure/epub/book_link_resolver.dart';
import 'book_reader_controller.dart';
import 'book_block_renderer.dart';
import 'book_image_view.dart';
import 'narration_language_controller.dart';
import '../listening/playback_coordinator.dart';

class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.book,
    required this.content,
    this.controller,
    this.onOpenPlayer,
    this.onPresentationChanged,
  });
  final Book book;
  final BookContentSource content;
  final BookReaderController? controller;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onPresentationChanged;
  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with WidgetsBindingObserver {
  late final BookReaderController reader;
  late final BookImageDecoder? images;
  late final BookPaginationController? pages;
  late final BookmarkController? marks;
  String? _layoutSignature;
  bool _pagedFallback = false;
  bool get _usingPages =>
      pages != null &&
      reader.experience.mode == ReaderMode.paged &&
      !_pagedFallback;
  final _scroll = ScrollController(), _viewport = GlobalKey();
  final _textKeys = <String, GlobalKey>{}, _blockKeys = <String, GlobalKey>{};
  Timer? _debounce;
  int _presentation = 0;
  bool _allowPop = false, _exiting = false, _initial = true;
  bool _restoring = false, _dirtyScroll = false;
  bool _followMove = false;
  int _followIntent = 0;
  void _followChanged() {
    if (!mounted) return;
    setState(() {});
    if (!reader.follow.canNavigate || _followMove) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _followVisible());
  }

  Future<void> _followVisible() async {
    if (!mounted) return;
    // A player, dialog or another route must not move the reader behind it.
    if (ModalRoute.of(context)?.isCurrent == false) {
      reader.userNavigation();
      return;
    }
    final follow = reader.follow, span = reader.follow.targetSpan;
    final passage = follow.passageId,
        audio = reader.playback?.activePlayerToken;
    if (!mounted ||
        !follow.canNavigate ||
        _followMove ||
        span == null ||
        passage == null ||
        audio == null ||
        !reader.ownsPlayback) {
      return;
    }
    final intent = ++_followIntent, layout = follow.layoutGeneration;
    bool current() =>
        mounted &&
        intent == _followIntent &&
        follow.canNavigate &&
        follow.layoutGeneration == layout &&
        reader.ownsPlayback &&
        reader.playback!.activePlayerToken.matches(audio) &&
        follow.passageId == passage;
    if (_usingPages && (pages?.current == null || pages!.navigating)) return;
    if (_usingPages && pages?.current != null) {
      final shown = pages!.current!.fragments.any(
        (f) =>
            f.block.id == passage &&
            f.startUtf16 <= span.start &&
            f.endUtf16 > span.start,
      );
      if (shown) return;
    } else {
      final paragraph = _textKeys[passage]?.currentContext?.findRenderObject();
      final viewport = _viewport.currentContext?.findRenderObject();
      if (paragraph is RenderParagraph &&
          viewport is RenderBox &&
          _scroll.hasClients) {
        final caret = paragraph.getOffsetForCaret(
          TextPosition(offset: span.start),
          Rect.zero,
        );
        final y =
            paragraph.localToGlobal(caret).dy -
            viewport.localToGlobal(Offset.zero).dy;
        if (y >= 0 && y < viewport.size.height - 32) return;
        _restoring = true;
        try {
          _scroll.jumpTo(
            (_scroll.offset + y - 24).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            ),
          );
        } finally {
          _restoring = false;
        }
        return;
      }
    }
    final source = reader.navigation;
    if (source == null) return;
    _followMove = true;
    var moved = false;
    try {
      final block = await source.block(reader.book.key, passage);
      if (!current()) return;
      final locator = BookLocator(
        key: block.key,
        chapterId: block.chapterId,
        blockId: block.id,
        offsetUtf16: span.start,
      );
      locator.validate(block);
      if (_usingPages) {
        moved = await pages!.followTo(locator, stillCurrent: current);
      } else {
        await reader.go(
          locator,
          savePosition: false,
          origin: ReaderNavigationOrigin.audioFollow,
          stillCurrent: current,
        );
        moved = current();
      }
    } catch (_) {
      if (current()) reader.follow.navigation(ReaderNavigationOrigin.user);
    } finally {
      _followMove = false;
      if (moved && current()) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _followVisible());
      }
    }
  }

  final _passageFocus = FocusNode(debugLabel: 'Passage paginé');
  @override
  void initState() {
    super.initState();
    reader =
        widget.controller ??
        BookReaderController(book: widget.book, content: widget.content);
    images = reader.navigation == null
        ? null
        : BookImageDecoder(reader.navigation!);
    pages = reader.pagination;
    marks = reader.bookmarkStore == null || reader.navigation == null
        ? null
        : BookmarkController(reader, reader.bookmarkStore!);
    pages?.addListener(_changed);
    reader.addListener(_changed);
    reader.follow.addListener(_followChanged);
    _scroll.addListener(_scrolled);
    WidgetsBinding.instance.addObserver(this);
    unawaited(reader.initialize());
  }

  void _changed() {
    if (!mounted) return;
    if (reader.presentation != _presentation) {
      _presentation = reader.presentation;
      _pagedFallback = false;
      _layoutSignature = null;
      final ids = {
        for (final b in reader.window?.blocks ?? <BookBlock>[]) b.id,
      };
      _textKeys.removeWhere((id, _) => !ids.contains(id));
      _blockKeys.removeWhere((id, _) => !ids.contains(id));
      WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    }
    setState(() {});
    if (reader.follow.canNavigate && !_followMove) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followVisible());
    }
  }

  void _scrolled() {
    if (_restoring || !_scroll.hasClients) return;
    if (_scroll.position.userScrollDirection != ScrollDirection.idle) {
      reader.userNavigation();
    }
    if (_scroll.position.userScrollDirection == ScrollDirection.idle &&
        !_dirtyScroll) {
      return;
    }
    _dirtyScroll = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _capture);
  }

  void _capture() {
    if (!mounted || reader.loading || reader.isClosed || _usingPages) return;
    if (!_dirtyScroll && reader.durable != null) return;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy,
        bottom = top + viewport.size.height;
    for (final b in reader.window?.blocks ?? <BookBlock>[]) {
      final box = _blockKeys[b.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= top || y >= bottom) continue;
      var offset = 0;
      final paragraph = _textKeys[b.id]?.currentContext?.findRenderObject();
      if (paragraph is RenderParagraph && paragraph.hasSize) {
        final origin = paragraph.localToGlobal(Offset.zero);
        offset = paragraph
            .getPositionForOffset(Offset(0, math.max(0, top - origin.dy + 1)))
            .offset
            .clamp(0, b.text.length);
        if (!validUtf16Offset(b.text, offset)) offset--;
      }
      _dirtyScroll = false;
      reader.recordVisible(
        BookLocator(
          key: b.key,
          chapterId: b.chapterId,
          blockId: b.id,
          offsetUtf16: offset,
        ),
      );
      break;
    }
  }

  void _restore() {
    if (!mounted || !_scroll.hasClients || _usingPages) return;
    _restoring = true;
    _dirtyScroll = false;
    _debounce?.cancel();
    _scroll.jumpTo(0);
    final skip = _initial && reader.durable == null;
    _initial = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final locator = reader.focusLocator;
      if (!skip && locator != null) {
        final paragraph = _textKeys[locator.blockId]?.currentContext
            ?.findRenderObject();
        final viewport = _viewport.currentContext?.findRenderObject();
        if (paragraph is RenderParagraph &&
            viewport is RenderBox &&
            paragraph.hasSize &&
            viewport.hasSize) {
          final caret = paragraph.getOffsetForCaret(
            TextPosition(offset: locator.offsetUtf16),
            Rect.zero,
          );
          final delta =
              paragraph.localToGlobal(caret).dy -
              viewport.localToGlobal(Offset.zero).dy;
          _scroll.jumpTo(
            (_scroll.position.pixels + delta).clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        } else if (viewport is RenderBox && viewport.hasSize) {
          final blockBox = _blockKeys[locator.blockId]?.currentContext
              ?.findRenderObject();
          if (blockBox is RenderBox && blockBox.hasSize) {
            final delta =
                blockBox.localToGlobal(Offset.zero).dy -
                viewport.localToGlobal(Offset.zero).dy;
            _scroll.jumpTo(
              (_scroll.position.pixels + delta).clamp(
                0,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
        }
      }
      _restoring = false;
      if (!reader.follow.canNavigate) _passageFocus.requestFocus();
      // Restoring presentation is not a new reading action. Save on subsequent scroll.
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    reader.follow.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _capture();
      unawaited(reader.flush());
    }
  }

  Future<void> _leave() async {
    if (_exiting) return;
    _exiting = true;
    _debounce?.cancel();
    _capture();
    await reader.flush();
    if (!mounted) return;
    if (reader.saveError != null) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Repère non enregistré'),
          content: const Text(
            'Quitter sans enregistrer ce passage ? Le dernier repère confirmé sera conservé.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Rester'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Quitter'),
            ),
          ],
        ),
      );
      if (leave != true) {
        _exiting = false;
        return;
      }
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _bookmarks(BuildContext ctx) async {
    reader.userNavigation();
    _capture();
    final model = marks;
    if (model == null) return;
    final opened = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => BookmarksSheet(controller: model),
    );
    if (opened == true && mounted) _passageFocus.requestFocus();
  }

  Future<void> _toc(BuildContext ctx) async {
    reader.userNavigation();
    _capture();
    final chapter = await showModalBottomSheet<String>(
      context: ctx,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .75,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sommaire',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: reader.chapters.length,
                  itemBuilder: (_, i) {
                    final c = reader.chapters[i];
                    return ListTile(
                      leading: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: Theme.of(sheet).colorScheme.primary,
                        ),
                      ),
                      selected: reader.visible?.chapterId == c.id,
                      title: Text(c.title),
                      trailing: reader.visible?.chapterId == c.id
                          ? const Icon(Icons.bookmark_outline)
                          : null,
                      onTap: () => Navigator.pop(sheet, c.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chapter != null && mounted) await reader.chapter(chapter);
  }

  Future<void> _settings(BuildContext ctx) async {
    reader.userNavigation();
    _capture();
    var experience = reader.experience;
    try {
      experience = await reader.experienceStore?.read() ?? experience;
    } catch (_) {
      if (ctx.mounted) {
        _message(ctx, 'Les derniers réglages ne peuvent pas être chargés.');
      }
      return;
    }
    if (!ctx.mounted) return;
    final value = await showModalBottomSheet<ReadingSettings>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => ReadingSettingsSheet(
        preferences: reader.preferences,
        experience: experience,
        extended: reader.supportsPagination,
      ),
    );
    if (value != null && mounted) {
      if (reader.supportsPagination) {
        await reader.changeExperience(
          value.experience,
          readerValue: value.reader,
        );
      } else {
        await reader.changePreferences(value.reader);
      }
      widget.onPresentationChanged?.call();
    }
  }

  Future<void> _listen({
    bool resumeSaved = false,
    bool prepareChapter = false,
    BookLocator? from,
    WordSelection? word,
  }) async {
    _capture();
    if (resumeSaved &&
        reader.ownsPlayback &&
        reader.playback?.state == PlaybackState.paused) {
      await reader.playback!.resume();
      return;
    }
    var confirmed = false;
    if (reader.narrationLanguage == NarrationLanguage.confirmationRequired) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('Lire en français ?'),
              content: const Text(
                'La langue du livre est absente ou multiple. La voix disponible lit en français ; le texte du livre restera inchangé.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Lire en français'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    await reader.listenHere(
      prepareChapter: prepareChapter,
      word: word,
      frenchConfirmed: confirmed,
      resumeSaved: resumeSaved,
      from: from,
    );
    // Keep the source visible so starting narration cannot suspend its follow.
    // The full player remains available through the explicit footer action.
  }

  int _selectionIntent = 0;

  Future<void> _paragraphActions(
    BuildContext ctx, [
    BookLocator? at,
    WordSelection? word,
  ]) async {
    reader.userNavigation();
    _capture();
    final source = reader.navigation;
    if (source is! ParagraphNavigationSource) return;
    final intent = ++_selectionIntent;
    try {
      final selected = word == null
          ? null
          : await WordSelectionSource.resolve(source, word.start);
      if (!mounted ||
          !ctx.mounted ||
          reader.isClosed ||
          intent != _selectionIntent) {
        return;
      }
      final chosen = await ParagraphActions.show(
        ctx,
        book: widget.book,
        source: source,
        at: at,
        word: selected,
        onBookmark: marks == null
            ? null
            : (at) async {
                await marks!.addParagraph(at);
                return marks!.error ??
                    marks!.status ??
                    'Le signet n’a pas été enregistré.';
              },
        canListen:
            reader.playback != null &&
            reader.narrationLanguage != NarrationLanguage.unsupported,
      );
      if (mounted) _passageFocus.requestFocus();
      if (chosen != null && mounted) {
        await _listen(from: chosen.locator, word: chosen.word);
      }
    } on BookFailure catch (e) {
      if (mounted) _message(context, e.message);
    }
  }

  void _message(BuildContext ctx, String message) {
    if (mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _link(BuildContext ctx, BookBlock block, String target) async {
    _capture();
    try {
      final link = await reader.resolve(block, target);
      if (!mounted || !ctx.mounted) return;
      if (link.external != null) {
        final confirmed = await showDialog<bool>(
          context: ctx,
          builder: (dialog) => AlertDialog(
            title: const Text('Ouvrir dans le navigateur ?'),
            content: SingleChildScrollView(
              child: Text(link.external.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Ouvrir'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          final opened = await BookExternalLauncher().open(
            link.external!,
            userConfirmed: true,
          );
          if (!opened && ctx.mounted) {
            _message(ctx, 'Aucun navigateur ne peut ouvrir ce lien.');
          }
        }
      } else {
        final locator = await reader.internalTarget(link);
        final b = await reader.navigation?.block(
          widget.book.key,
          locator.blockId,
        );
        if (!mounted || !ctx.mounted) return;
        if (b?.isIdentifiedNote == true) {
          await _note(ctx, b!);
        } else {
          await reader.go(locator);
        }
      }
    } on BookFailure catch (e) {
      if (ctx.mounted) _message(ctx, e.message);
    } catch (_) {
      if (ctx.mounted) _message(ctx, 'Ce lien ne peut pas être ouvert.');
    }
  }

  Future<void> _note(BuildContext ctx, BookBlock block) async {
    reader.userNavigation();
    _capture();
    try {
      var window = await reader.openNote(
        BookLocator(
          key: block.key,
          chapterId: block.chapterId,
          blockId: block.id,
          offsetUtf16: 0,
        ),
      );
      if (!mounted || !ctx.mounted) return;
      await showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .8,
            child: StatefulBuilder(
              builder: (ctx, setLocal) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Note',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final b in window.blocks.takeWhile(
                    (b) => b.isIdentifiedNote,
                  ))
                    BookBlockRenderer(
                      block: b,
                      fontScale: reader.preferences.fontScale,
                      lineHeight: reader.supportsPagination
                          ? reader.experience.lineHeight
                          : null,
                      showNoteBody: true,
                      images: images,
                      onLink: (b, url) async {
                        // Replace the modal before following another destination;
                        // a chain of notes must not retain a stack of windows.
                        Navigator.pop(sheet);
                        await WidgetsBinding.instance.endOfFrame;
                        if (mounted) await _link(context, b, url);
                      },
                      onNote: (_) {},
                    ),
                  if (window.next != null &&
                      window.blocks.every((b) => b.isIdentifiedNote))
                    TextButton(
                      onPressed: () async {
                        final next = await reader.continueNote();
                        if (next != null && ctx.mounted) {
                          setLocal(() => window = next);
                        }
                      },
                      child: const Text('Suite de la note'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('Fermer la note'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } on BookFailure catch (e) {
      if (ctx.mounted) _message(ctx, e.message);
    } finally {
      reader.closeNote();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    marks?.dispose();
    reader.follow.removeListener(_followChanged);
    reader.removeListener(_changed);
    pages?.removeListener(_changed);
    unawaited(reader.close());
    _scroll.dispose();
    _passageFocus.dispose();
    super.dispose();
  }

  Widget _scrollBody(BuildContext ctx, List<BookBlock> blocks) {
    const itemsPrefix = <Widget>[];
    final content = Focus(
      focusNode: _passageFocus,
      child: ClipRect(
        key: _viewport,
        child: ListView.builder(
          controller: _scroll,
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          padding: EdgeInsets.symmetric(
            vertical: 16,
            horizontal: reader.supportsPagination
                ? reader.experience.margins
                : 16,
          ),
          itemCount:
              itemsPrefix.length +
              blocks.length +
              (reader.window?.done == true ? 1 : 0),
          itemBuilder: (_, index) {
            if (index < itemsPrefix.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: itemsPrefix[index],
              );
            }
            final ordinal = index - itemsPrefix.length;
            if (ordinal == blocks.length) {
              return const Text('Fin du livre');
            }
            final b = blocks[ordinal];
            return KeyedSubtree(
              key: _blockKeys.putIfAbsent(b.id, () => GlobalKey()),
              child: Semantics(
                customSemanticsActions: {
                  if (b.speechEligible && !reader.supportsPagination)
                    CustomSemanticsAction(label: 'Choisir ce paragraphe'): () =>
                        _paragraphActions(
                          ctx,
                          BookLocator(
                            key: b.key,
                            chapterId: b.chapterId,
                            blockId: b.id,
                            offsetUtf16: 0,
                          ),
                        ),
                },
                child: GestureDetector(
                  onLongPress: reader.supportsPagination || !b.speechEligible
                      ? null
                      : () => _paragraphActions(
                          ctx,
                          BookLocator(
                            key: b.key,
                            chapterId: b.chapterId,
                            blockId: b.id,
                            offsetUtf16: 0,
                          ),
                        ),
                  child: BookBlockRenderer(
                    onParagraph: (at) => _paragraphActions(ctx, at),
                    onWord: (word) => _paragraphActions(ctx, word.start, word),
                    heardPassageId: reader.follow.passageId,
                    heardParagraph: reader.follow.paragraphActive,
                    heardSpan: reader.follow.mode == FollowMode.off
                        ? null
                        : reader.follow.active,
                    block: b,
                    fontScale: reader.preferences.fontScale,
                    lineHeight: reader.supportsPagination
                        ? reader.experience.lineHeight
                        : null,
                    sharedScrollLayout:
                        reader.supportsPagination ||
                        reader.wordAlignmentAvailable,
                    paragraphEnd: reader.paragraphEnds(b),
                    textKey: _textKeys.putIfAbsent(b.id, () => GlobalKey()),
                    images: images,
                    onLink: (b, url) => _link(ctx, b, url),
                    onNote: (b) => _note(ctx, b),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    return content;
  }

  Widget _pagedBody(BuildContext ctx) {
    final pager = pages!;
    return LayoutBuilder(
      builder: (context, available) => Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final margins = reader.experience.margins;
                final width = viewport.maxWidth - 2 * margins;
                final height = viewport.maxHeight;
                if (width <= 20 || height < 48) {
                  return _paginationFallback(
                    'L’espace disponible est trop petit pour cette mise en page.',
                  );
                }
                final scaler = MediaQuery.textScalerOf(context);
                final signature = [
                  width,
                  height,
                  margins,
                  reader.preferences.fontScale,
                  reader.experience.lineHeight,
                  reader.preferences.theme.name,
                  scaler.scale(12),
                  scaler.scale(18),
                  scaler.scale(22),
                  _presentation,
                  MediaQuery.viewInsetsOf(context),
                  Directionality.of(context),
                ].join(':');
                if (_layoutSignature != signature) {
                  _layoutSignature = signature;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _layoutSignature == signature) {
                      reader.follow.layoutChanged(
                        reader.follow.layoutGeneration + 1,
                      );
                    }
                  });
                  final target = reader.visible!;
                  final layout = ReaderLayout(
                    width: width,
                    height: height,
                    margins: margins,
                    fontScale: reader.preferences.fontScale,
                    lineHeight: reader.experience.lineHeight,
                    textScaler: scaler,
                    color: Theme.of(context).colorScheme.onSurface,
                    viewInsets: MediaQuery.viewInsetsOf(context),
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        _usingPages &&
                        _layoutSignature == signature) {
                      unawaited(pager.configure(layout, target));
                    }
                  });
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Mise en page',
                    ),
                  );
                }
                if (pager.error != null) {
                  return _paginationFallback(
                    'Cette mise en page n’est pas disponible. Le texte reste accessible en défilement.',
                  );
                }
                if (pager.current == null || pager.layout == null) {
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Mise en page',
                    ),
                  );
                }
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: margins),
                  child: PagedBookView(
                    layout: pager.layout!,
                    generation: pager.generation,
                    heardPassageId: reader.follow.passageId,
                    heardParagraph: reader.follow.paragraphActive,
                    heardSpan: reader.follow.mode == FollowMode.off
                        ? null
                        : reader.follow.active,
                    audioFollow: reader.follow.canNavigate,
                    focusNode: _passageFocus,
                    current: pager.current!,
                    previous: pager.previous,
                    next: pager.next,
                    busy: pager.navigating || pager.pageNumber == null,
                    images: images,
                    onPrevious: () {
                      reader.userNavigation();
                      pager.turn(false);
                    },
                    onNext: () {
                      reader.userNavigation();
                      pager.turn(true);
                    },
                    onLink: (block, url) => _link(ctx, block, url),
                    onNote: (block) => _note(ctx, block),
                    onParagraph: (at) => _paragraphActions(ctx, at),
                    onWord: (word) => _paragraphActions(ctx, word.start, word),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _paginationFallback(String message) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Semantics(liveRegion: true, child: Text(message)),
        TextButton(
          onPressed: () async {
            await pages?.suspend();
            if (!mounted) return;
            setState(() {
              _pagedFallback = true;
            });
            final target = reader.visible;
            if (target != null) await reader.go(target, savePosition: false);
            // go() is a presentation change; keep this local fallback for this layout.
            if (mounted) {
              setState(() {
                _pagedFallback = true;
              });
            }
          },
          child: const Text('Lire en défilement'),
        ),
      ],
    ),
  );

  Widget _footer(BuildContext ctx) {
    final pager = _usingPages ? pages : null;
    final percent = reader.totalUnits != null && reader.totalUnits! > 0
        ? ((reader.unitsBefore ?? 0) / reader.totalUnits!).clamp(0.0, 1.0)
        : null;
    final label = pager != null
        ? pager.pageNumber == null
              ? 'Numéro de page en calcul'
              : pager.total == null
              ? 'Page ${pager.pageNumber} · total en calcul'
              : 'Page ${pager.pageNumber} sur ${pager.total}'
        : 'Lecture en défilement';
    final preparing =
        reader.ownsPlayback &&
        reader.playback!.state == PlaybackState.preparing;
    final playing =
        reader.ownsPlayback && reader.playback!.state == PlaybackState.playing;
    return ReaderChromeFooter(
      label: label,
      progress: percent,
      previousLabel: pager != null ? 'Page précédente' : 'Passages précédents',
      nextLabel: pager != null ? 'Page suivante' : 'Passages suivants',
      onPrevious: pager != null
          ? (pager.navigating || pager.previous == null
                ? null
                : () {
                    reader.userNavigation();
                    pager.turn(false);
                  })
          : (reader.loading || !reader.hasPrevious
                ? null
                : () {
                    _capture();
                    reader.userNavigation();
                    reader.previous();
                  }),
      onNext: pager != null
          ? (pager.navigating || pager.next == null
                ? null
                : () {
                    reader.userNavigation();
                    pager.turn(true);
                  })
          : (reader.loading || reader.window?.next == null
                ? null
                : () {
                    _capture();
                    reader.userNavigation();
                    reader.next();
                  }),
      audioAction: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          if (reader.follow.paragraphActive)
            TextButton.icon(
              onPressed: reader.follow.mode == FollowMode.following
                  ? null
                  : reader.follow.resume,
              icon: const Icon(Icons.my_location),
              label: Text(
                reader.follow.mode == FollowMode.following
                    ? reader.follow.message
                    : 'Reprendre le suivi',
              ),
            ),
          if (reader.playback != null &&
              reader.narrationLanguage != NarrationLanguage.unsupported)
            FilledButton.tonalIcon(
              onPressed: reader.loading || preparing
                  ? null
                  : playing
                  ? reader.playback!.pause
                  : () => _listen(
                      resumeSaved:
                          reader.ownsPlayback &&
                          reader.playback!.state == PlaybackState.paused,
                    ),
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.headphones_rounded,
              ),
              label: Text(
                preparing
                    ? 'Préparation de la voix…'
                    : playing
                    ? 'Pause'
                    : reader.ownsPlayback &&
                          reader.playback!.state == PlaybackState.paused
                    ? 'Reprendre l’écoute'
                    : 'Écouter ici',
              ),
            ),
          if (reader.playback != null &&
              reader.navigation is ParagraphNavigationSource)
            TextButton(
              onPressed: reader.loading ? null : () => _paragraphActions(ctx),
              child: const Text('Choisir un paragraphe'),
            ),
          if (preparing && reader.ownsPlayback)
            TextButton(
              onPressed: reader.playback!.stop,
              child: const Text('Annuler la préparation'),
            ),
          if (reader.ownsPlayback && widget.onOpenPlayer != null)
            TextButton.icon(
              onPressed: widget.onOpenPlayer,
              icon: const Icon(Icons.headphones),
              label: const Text('Ouvrir le player'),
            ),
        ],
      ),
    );
  }

  List<Widget> _audioDetails() => <Widget>[
    const Text('Mise en page simplifiée : styles EPUB limités.'),
    if (reader.playback == null)
      const Text(
        'Lecture visuelle. La lecture audio des EPUB n’est pas disponible ici.',
      )
    else ...[
      if (reader.narrationLanguage == NarrationLanguage.unsupported)
        const Text('Narration française uniquement. Ce livre reste lisible.')
      else
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _listen(prepareChapter: true),
              child: const Text('Préparer ce chapitre avant l’écoute'),
            ),
            if (reader.savedAudio != null ||
                reader.ownsPlayback &&
                    reader.playback!.state == PlaybackState.paused)
              TextButton(
                onPressed: () => _listen(resumeSaved: true),
                child: const Text('Reprendre l’écoute'),
              ),
            if (reader.ownsPlayback) ...[
              TextButton(
                onPressed: reader.playback!.pause,
                child: const Text('Pause'),
              ),
              TextButton(
                onPressed: reader.playback!.stop,
                child: const Text('Arrêter'),
              ),
            ],
            if (reader.canShowHeard)
              TextButton(
                onPressed: reader.showHeard,
                child: const Text('Afficher le passage entendu'),
              ),
          ],
        ),
      if (reader.ownsPlayback)
        Semantics(
          liveRegion: true,
          child: Text(switch (reader.playback!.state) {
            PlaybackState.preparing => reader.playback!.preparationStatus,
            PlaybackState.playing => 'Lecture en cours',
            PlaybackState.paused => 'Lecture en pause',
            PlaybackState.completed => reader.playback!.completionStatus,
            PlaybackState.error =>
              reader.playback!.error?.message ?? 'Lecture audio indisponible',
            PlaybackState.stopped => 'Lecture arrêtée',
          }),
        ),
      if (reader.ownsPlayback && reader.playback!.positionError != null)
        const Text('Le repère audio n’a pas pu être enregistré.'),
    ],
  ];

  @override
  Widget build(BuildContext context) => Theme(
    data: ReaderVisualTheme.theme(
      dark: reader.preferences.theme == ReaderTheme.dark,
      highlightColor: reader.experience.highlightColor,
    ),
    child: Builder(
      builder: (ctx) {
        final blocks = reader.window?.blocks ?? <BookBlock>[];
        final notices = <Widget>[
          if (reader.ownsPlayback &&
              reader.playback!.state == PlaybackState.error)
            Semantics(
              liveRegion: true,
              child: Text(
                reader.playback!.error?.message ?? 'Lecture audio indisponible',
              ),
            ),
          if (reader.ownsPlayback && reader.playback!.positionError != null)
            const Text('Le repère audio n’a pas pu être enregistré.'),
          if (reader.narrationMessage != null)
            Semantics(liveRegion: true, child: Text(reader.narrationMessage!)),

          if (reader.warning != null)
            Semantics(liveRegion: true, child: Text(reader.warning!)),
          if (reader.fallbackChapter != null)
            TextButton(
              onPressed: reader.fallback,
              child: Text(
                reader.fallbackChapter!.isEmpty
                    ? 'Reprendre au début du livre'
                    : 'Reprendre au début du chapitre',
              ),
            ),
          if (reader.error != null)
            Column(
              children: [
                Semantics(liveRegion: true, child: Text(reader.error!.message)),
                TextButton(
                  onPressed: reader.fallback,
                  child: const Text('Recommencer au début du livre'),
                ),
              ],
            ),
          if (reader.saveError != null)
            Column(
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Repère non enregistré : ${reader.saveError!.message}',
                  ),
                ),
                TextButton(
                  onPressed: reader.retrySave,
                  child: const Text('Enregistrer ce passage'),
                ),
              ],
            ),
        ];
        return PopScope(
          canPop: _allowPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_leave());
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: math.max(
                kToolbarHeight,
                MediaQuery.textScalerOf(ctx).scale(24) + 24,
              ),
              leading: IconButton(
                tooltip: 'Retour',
                onPressed: _leave,
                icon: const Icon(Icons.arrow_back),
              ),
              title: Text(
                widget.book.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (marks != null)
                  IconButton(
                    tooltip: 'Signets',
                    onPressed: reader.loading ? null : () => _bookmarks(ctx),
                    icon: const Icon(Icons.bookmarks_outlined),
                  ),
                IconButton(
                  tooltip: 'Sommaire',
                  onPressed: reader.chapters.isEmpty ? null : () => _toc(ctx),
                  icon: const Icon(Icons.list),
                ),
                IconButton(
                  tooltip: 'Réglages de lecture',
                  onPressed: () => _settings(ctx),
                  icon: const Icon(Icons.text_fields),
                ),
                IconButton(
                  tooltip: 'Audio et informations',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => showModalBottomSheet<void>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => AnimatedBuilder(
                      animation: reader,
                      builder: (context, _) => SafeArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Audio et informations',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              ..._audioDetails(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 2,
                    child: reader.loading
                        ? const LinearProgressIndicator(
                            semanticsLabel: 'Chargement du texte',
                          )
                        : null,
                  ),
                  if (notices.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * .25,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: notices,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _usingPages && reader.visible != null
                        ? _pagedBody(ctx)
                        : _scrollBody(ctx, blocks),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: _footer(ctx),
          ),
        );
      },
    ),
  );
}
