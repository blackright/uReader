import '../../domain/word_alignment.dart';
import '../../domain/word_selection.dart';

import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import 'book_image_view.dart';
import 'reader_layout.dart';
import '../../domain/pagination.dart';
import '../../domain/paragraph_index.dart';

/// Renders canonical data only. No document parser, HTML or external resource URL.
class BookBlockRenderer extends StatelessWidget {
  const BookBlockRenderer({
    super.key,
    required this.block,
    required this.onLink,
    required this.onNote,
    this.fontScale = 1,
    this.lineHeight,
    this.showNoteBody = false,
    this.textKey,
    this.onWord,
    this.onParagraph,
    this.images,
    this.layout,
    this.fragment,
    this.sharedScrollLayout = false,
    this.paragraphEnd = true,
    this.heardPassageId,
    this.heardSpan,
    this.heardParagraph = false,
  });
  final BookBlock block;
  final String? heardPassageId;
  final SourceSpan? heardSpan;
  final bool heardParagraph;
  final void Function(BookBlock, String) onLink;
  final ValueChanged<BookBlock> onNote;
  final double fontScale;
  final double? lineHeight;
  final bool showNoteBody;
  final GlobalKey? textKey;
  final ValueChanged<WordSelection>? onWord;
  final ValueChanged<BookLocator>? onParagraph;
  final BookImageDecoder? images;
  final ReaderLayout? layout;
  final PageFragment? fragment;
  final bool sharedScrollLayout, paragraphEnd;
  @override
  Widget build(BuildContext context) {
    if (layout != null && fragment != null) {
      return ReaderFragmentView(
        heardPassageId: heardPassageId,
        heardSpan: heardSpan,
        heardParagraph: heardParagraph,
        layout: layout!,
        fragment: fragment!,
        images: images,
        onLink: onLink,
        onNote: onNote,
        textKey: textKey,
        onWord: onWord,
        onParagraph: onParagraph,
      );
    }
    if (sharedScrollLayout && !showNoteBody) {
      return LayoutBuilder(
        builder: (context, bounds) {
          final spec = ReaderLayout(
            width: bounds.maxWidth,
            height: MediaQuery.sizeOf(context).height,
            fontScale: fontScale,
            lineHeight: lineHeight ?? 1.5,
            textScaler: MediaQuery.textScalerOf(context),
            color: Theme.of(context).colorScheme.onSurface,
          );
          return _ScrollBookFragment(owner: this, layout: spec);
        },
      );
    }
    if (block.kind == BookBlockKind.image) {
      return BookImageView(block: block, decoder: images);
    }
    if (block.isIdentifiedNote && !showNoteBody) {
      return TextButton(
        onPressed: () => onNote(block),
        child: const Text('Consulter la note'),
      );
    }
    final spans = ReaderLayout.spans(block);
    final links = <String, BookLink>{};
    for (final s in block.inline) {
      if (s.link != null) links['${s.link!.target}:${s.startUtf16}'] = s.link!;
    }
    final heading = block.kind == BookBlockKind.heading;
    Widget text = Text.rich(
      TextSpan(children: spans),
      key: textKey,
      style: TextStyle(
        fontSize: (heading ? 22 : 18) * fontScale,
        height: lineHeight,
        fontWeight: heading ? FontWeight.bold : null,
        fontFamily: block.kind == BookBlockKind.preformatted
            ? 'monospace'
            : null,
      ),
    );
    if (block.kind == BookBlockKind.listItem) {
      text = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: text),
        ],
      );
    }
    return Semantics(
      container: true,
      header: heading,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: block.kind == BookBlockKind.quote
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                    width: 3,
                  ),
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (block.kind == BookBlockKind.tableCell)
              const Text('Cellule de tableau', style: TextStyle(fontSize: 12)),
            text,
            for (final link in links.values)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onLink(block, link.target),
                  child: Text(
                    'Ouvrir le lien : ${block.text.substring(link.startUtf16, link.endUtf16)}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A cache for this visible block only; never a book-sized metrics cache.
class _ScrollBookFragment extends StatefulWidget {
  const _ScrollBookFragment({required this.owner, required this.layout});
  final BookBlockRenderer owner;
  final ReaderLayout layout;
  @override
  State<_ScrollBookFragment> createState() => _ScrollBookFragmentState();
}

class _ScrollBookFragmentState extends State<_ScrollBookFragment> {
  BookBlock? _source;
  String? _geometry;
  MeasuredReaderBlock? _measured;
  @override
  Widget build(BuildContext context) {
    final owner = widget.owner, spec = widget.layout, block = owner.block;
    final geometry = [
      spec.width,
      spec.height,
      spec.fontScale,
      spec.lineHeight,
      spec.fontFamily,
      spec.locale,
      spec.direction,
      for (final size in [12.0, 18.0, 22.0])
        spec.textScaler.scale(size * spec.fontScale),
    ].join(':');
    if (!identical(_source, block) || _geometry != geometry) {
      _measured = spec.measureWholeBlock(block);
      _source = block;
      _geometry = geometry;
    }
    final measured = _measured!;
    final starts = ParagraphIndex().slice(block) == 0;
    return ReaderFragmentView(
      heardPassageId: owner.heardPassageId,
      heardSpan: owner.heardSpan,
      heardParagraph: owner.heardParagraph,
      layout: spec,
      fragment: PageFragment(
        block: block,
        startUtf16: 0,
        endUtf16: block.text.length,
        clipTop: 0,
        textHeight: measured.height,
        fullTextHeight: measured.height,
        leading: measured.atomic || !starts ? 0 : 8 + measured.prefix,
        trailing: measured.atomic || !owner.paragraphEnd ? 0 : 8,
        atomic: measured.atomic,
        paragraphStart: starts,
      ),
      textKey: owner.textKey,
      onWord: owner.onWord,
      onParagraph: owner.onParagraph,
      images: owner.images,
      onLink: owner.onLink,
      onNote: owner.onNote,
    );
  }
}
