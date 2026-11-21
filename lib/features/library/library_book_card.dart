import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/books.dart';
import 'library_cover_cache.dart';

class LibraryBookCard extends StatelessWidget {
  const LibraryBookCard({
    super.key,
    required this.book,
    required this.coverHeight,
    required this.cache,
    this.onOpen,
    this.onRemove,
    this.removing = false,
    this.failed = false,
  });
  final Book book;
  final double coverHeight;
  final LibraryCoverCache? cache;
  final VoidCallback? onOpen, onRemove;
  final bool removing, failed;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: coverHeight,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: LibraryBookCover(
                        book: book,
                        cache: cache,
                        enabled: onOpen != null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  book.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  removing
                      ? 'Suppression en cours…'
                      : failed
                      ? 'Suppression incomplète. Réessayez.'
                      : book.authors.isEmpty
                      ? 'Auteur inconnu'
                      : book.authors.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
      if (onRemove != null)
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: failed
                ? 'Réessayer la suppression de ${book.title}'
                : 'Supprimer ${book.title}',
            onPressed: removing ? null : onRemove,
            icon: Icon(failed ? Icons.refresh : Icons.delete_outline),
          ),
        ),
    ],
  );
}

class LibraryBookCover extends StatefulWidget {
  const LibraryBookCover({
    super.key,
    required this.book,
    required this.cache,
    this.enabled = true,
  });
  final Book book;
  final LibraryCoverCache? cache;
  final bool enabled;
  @override
  State<LibraryBookCover> createState() => _LibraryBookCoverState();
}

class _LibraryBookCoverState extends State<LibraryBookCover> {
  ui.Image? image;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LibraryBookCover old) {
    super.didUpdateWidget(old);
    if (old.book.key != widget.book.key ||
        old.book.coverResource != widget.book.coverResource ||
        old.cache != widget.cache ||
        old.enabled != widget.enabled) {
      image?.dispose();
      image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final g = ++generation, id = widget.book.coverResource;
    if (id == null || widget.cache == null || !widget.enabled) return;
    final loaded = await widget.cache!.load(
      widget.book.key,
      id,
      () => !mounted || generation != g || !widget.enabled,
    );
    if (!mounted || g != generation) {
      loaded?.dispose();
      return;
    }
    setState(() => image = loaded);
  }

  @override
  void dispose() {
    ++generation;
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF365B4B),
      Color(0xFF8D5940),
      Color(0xFF465D76),
      Color(0xFF746047),
      Color(0xFF674D62),
    ];
    final index =
        widget.book.key.id.codeUnits.fold<int>(0, (s, n) => s + n) %
        colors.length;
    return ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.fromLTRB(2, 2, 5, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 5,
              offset: Offset(2, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                RawImage(image: image, fit: BoxFit.cover)
              else
                Container(
                  color: colors[index],
                  padding: const EdgeInsets.fromLTRB(20, 22, 14, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_stories,
                        color: Color(0xFFEDE8DC),
                        size: 22,
                      ),
                      const Spacer(),
                      Text(
                        widget.book.title,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontFamily: 'serif',
                          color: Color(0xFFF7F3EA),
                          fontSize: 21,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.book.authors.join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          color: Color(0xFFEDE8DC),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: .24),
                        Colors.transparent,
                        Colors.black.withValues(alpha: .07),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 0,
                top: 4,
                bottom: 4,
                width: 3,
                child: ColoredBox(color: Color(0xFFDAD6CC)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
