import '../../domain/word_alignment.dart';
import '../../domain/word_selection.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../domain/books.dart';
import '../../domain/pagination.dart';
import 'book_image_view.dart';
import 'reader_layout.dart';

/// A controlled window of at most three pages. The owner supplies pages from one
/// layout generation and owns all persistence. This surface never seeks audio.
class PagedBookView extends StatefulWidget {
  const PagedBookView({
    super.key,
    required this.layout,
    required this.generation,
    required this.current,
    required this.onPrevious,
    required this.onNext,
    required this.onLink,
    required this.onNote,
    this.previous,
    this.next,
    this.images,
    this.onParagraph,
    this.onWord,
    this.focusNode,
    this.busy = false,
    this.heardPassageId,
    this.heardSpan,
    this.heardParagraph = false,
    this.audioFollow = false,
  });
  final ReaderLayout layout;
  final int generation;
  final BookPage current;
  final BookPage? previous, next;
  final VoidCallback onPrevious, onNext;
  final void Function(BookBlock, String) onLink;
  final ValueChanged<BookBlock> onNote;
  final BookImageDecoder? images;
  final ValueChanged<BookLocator>? onParagraph;
  final ValueChanged<WordSelection>? onWord;
  final FocusNode? focusNode;
  final bool busy, audioFollow;
  final String? heardPassageId;
  final SourceSpan? heardSpan;
  final bool heardParagraph;

  @override
  State<PagedBookView> createState() => _PagedBookViewState();
}

class _PagedBookViewState extends State<PagedBookView> {
  final _ownedFocus = FocusNode(debugLabel: 'Passage paginé');
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _requestFocus();
  }

  @override
  void didUpdateWidget(PagedBookView old) {
    super.didUpdateWidget(old);
    if (!widget.audioFollow &&
        (old.generation != widget.generation ||
            old.current.start != widget.current.start)) {
      _requestFocus();
    }
  }

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageWindow(
    key: ValueKey(
      '${widget.generation}:${widget.current.start.ordinal}:'
      '${widget.current.start.offsetUtf16}:${widget.current.end.ordinal}:'
      '${widget.current.end.offsetUtf16}:${widget.previous != null}:${widget.next != null}',
    ),
    view: widget,
    focusNode: _focus,
  );
}

class _PageWindow extends StatefulWidget {
  const _PageWindow({super.key, required this.view, required this.focusNode});
  final PagedBookView view;
  final FocusNode focusNode;
  @override
  State<_PageWindow> createState() => _PageWindowState();
}

class _PageWindowState extends State<_PageWindow> {
  late final PageController _pages;
  bool _pending = false;
  double _drag = 0;
  int get _center => widget.view.previous == null ? 0 : 1;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: _center);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _navigate(bool forward) {
    final v = widget.view;
    if (_pending || v.busy || (forward ? v.next : v.previous) == null) return;
    setState(() => _pending = true);
    if (forward) {
      v.onNext();
    } else {
      v.onPrevious();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final window = [
      if (v.previous != null) v.previous!,
      v.current,
      if (v.next != null) v.next!,
    ];
    final reduced = MediaQuery.disableAnimationsOf(context);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.pageDown): _TurnIntent(true),
        SingleActivator(LogicalKeyboardKey.pageUp): _TurnIntent(false),
      },
      actions: {
        _TurnIntent: CallbackAction<_TurnIntent>(
          onInvoke: (intent) {
            _navigate(intent.forward);
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        label: 'Passage du livre',
        customSemanticsActions: {
          if (v.previous != null && !v.busy && !_pending)
            CustomSemanticsAction(label: 'Page précédente'): () =>
                _navigate(false),
          if (v.next != null && !v.busy && !_pending)
            CustomSemanticsAction(label: 'Page suivante'): () =>
                _navigate(true),
        },
        child: GestureDetector(
          onHorizontalDragStart: reduced ? (_) => _drag = 0 : null,
          onHorizontalDragUpdate: reduced
              ? (details) => _drag += details.delta.dx
              : null,
          onHorizontalDragEnd: reduced
              ? (_) {
                  if (_drag.abs() >= 40) _navigate(_drag < 0);
                }
              : null,
          child: SizedBox(
            width: v.layout.width,
            height: v.layout.height,
            child: PageView(
              controller: _pages,
              // EPUB reading order is kept even when the surrounding chrome is RTL.
              scrollDirection: Axis.horizontal,
              reverse: Directionality.of(context) == TextDirection.rtl,
              physics: v.busy || _pending || reduced
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (index) {
                if (mounted && index != _center) _navigate(index > _center);
              },
              children: [
                for (final page in window)
                  ExcludeSemantics(
                    excluding: page != v.current,
                    child: ExcludeFocus(
                      excluding: page != v.current,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final fragment in page.fragments)
                              ReaderFragmentView(
                                heardPassageId: v.heardPassageId,
                                heardSpan: v.heardSpan,
                                heardParagraph: v.heardParagraph,
                                layout: v.layout,
                                fragment: fragment,
                                images: v.images,
                                onLink: v.onLink,
                                onNote: v.onNote,
                                onParagraph: v.onParagraph,
                                onWord: v.onWord,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TurnIntent extends Intent {
  const _TurnIntent(this.forward);
  final bool forward;
}

/// Place outside the measured page viewport, in scrollable reader chrome.
/// The buttons also provide navigation when animations are disabled.
class PagedBookControls extends StatelessWidget {
  const PagedBookControls({super.key, this.onPrevious, this.onNext});
  final VoidCallback? onPrevious, onNext;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      TextButton.icon(
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left),
        label: const Text('Page précédente'),
      ),
      TextButton.icon(
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right),
        label: const Text('Page suivante'),
      ),
    ],
  );
}
