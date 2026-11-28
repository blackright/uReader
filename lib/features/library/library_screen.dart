import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import 'library_cover_cache.dart';
import 'library_book_card.dart';
import 'library_controller.dart';
import 'book_import_controller.dart';
import 'import_progress_view.dart';
import '../../infrastructure/database/book_repository.dart' show BookSort;

/// Explicit visual import and opening; no voice preparation or playback on entry.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.importController,
    required this.onOpen,
    this.recoveryIssues = const [],
    this.images,
    this.onWelcome,
  });
  final LibraryController library;
  final BookImportController importController;
  final ValueChanged<Book> onOpen;
  final List<BookFailure> recoveryIssues;
  final BookNavigationSource? images;
  final VoidCallback? onWelcome;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _importFocus = FocusNode();
  final _importAnchor = GlobalKey();
  final _scroll = ScrollController();
  final _search = TextEditingController();
  LibraryCoverCache? _covers;
  Future<void> _remove(Book book, {bool retry = false}) async {
    var confirmed = retry;
    if (!retry) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              scrollable: true,
              title: Text('Supprimer « ${book.title} » ?'),
              content: const SingleChildScrollView(
                child: Text(
                  'La copie importée, ses positions de lecture et son cache audio seront supprimés. Le fichier original, la voix installée et les autres livres seront conservés. L’écoute de ce livre sera arrêtée.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed || !mounted) return;
    final removed = await widget.library.remove(book, confirmed: true);
    if (mounted) {
      if (removed) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final anchor = _importAnchor.currentContext;
        if (anchor != null && anchor.mounted) {
          await Scrollable.ensureVisible(anchor, alignment: 0.5);
        }
        if (!mounted) return;
        _importFocus.requestFocus();
      }
      final message = widget.library.announcement;
      if (message != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Widget _bookTile(Book book, {bool pending = false}) {
    final library = widget.library;
    final busy = library.removing.contains(book.key.id);
    final failed = pending || library.removalErrors.containsKey(book.key.id);
    return ListTile(
      leading: const Icon(
        Icons.book_outlined,
        semanticLabel: 'Couverture indisponible',
      ),
      title: Text(book.title),
      subtitle: Text(
        busy
            ? 'Suppression en cours…'
            : failed
            ? 'Suppression incomplète. Réessayez.'
            : book.authors.isEmpty
            ? 'Auteur inconnu'
            : book.authors.join(', '),
      ),
      onTap: library.canOpen(book) ? () => widget.onOpen(book) : null,
      trailing: library.removal == null
          ? null
          : IconButton(
              tooltip: failed
                  ? 'Réessayer la suppression de ${book.title}'
                  : 'Supprimer ${book.title}',
              onPressed: busy ? null : () => _remove(book, retry: failed),
              icon: Icon(failed ? Icons.refresh : Icons.delete_outline),
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.images != null) _covers = LibraryCoverCache(widget.images!);
    widget.library.addListener(_changed);
    widget.importController.addListener(_importChanged);
    widget.library.refresh();
  }

  void _changed() {
    _covers?.retain(
      widget.library.books
          .where(widget.library.canOpen)
          .map((b) => b.key)
          .toSet(),
    );
    if (mounted) setState(() {});
  }

  bool _wasRunning = false;
  void _importChanged() {
    final c = widget.importController;
    if (_wasRunning && !c.running) {
      widget.library.refresh(search: _search.text);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) _scroll.jumpTo(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _importFocus.requestFocus();
        });
      });
    }
    _wasRunning = c.running;
    _changed();
  }

  @override
  void dispose() {
    widget.library.removeListener(_changed);
    widget.importController.removeListener(_importChanged);
    _scroll.dispose();
    _importFocus.dispose();
    _search.dispose();
    _covers?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library, job = widget.importController;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bibliothèque'),
        actions: [
          if (widget.onWelcome != null)
            IconButton(
              tooltip: 'Découvrir uReader',
              onPressed: widget.onWelcome,
              icon: const Icon(Icons.help_outline),
            ),
        ],
        toolbarHeight: math.max(
          kToolbarHeight,
          MediaQuery.textScalerOf(context).scale(24) + 24,
        ),
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final issue in widget.recoveryIssues)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(issue.message),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Rechercher un titre ou un auteur',
                    ),
                    onSubmitted: (s) => library.refresh(search: s),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<BookSort>(
                    initialValue: library.sort,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Trier les livres',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: BookSort.recent,
                        child: Text('Ajout récent'),
                      ),
                      DropdownMenuItem(
                        value: BookSort.title,
                        child: Text('Titre'),
                      ),
                      DropdownMenuItem(
                        value: BookSort.author,
                        child: Text('Auteur'),
                      ),
                    ],
                    onChanged: (sort) =>
                        library.refresh(search: _search.text, sort: sort),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    key: _importAnchor,
                    focusNode: _importFocus,
                    onPressed: job.running ? null : job.start,
                    child: const Text('Importer un EPUB'),
                  ),
                ),
                const ExpansionTile(
                  title: Text('À propos de l’import'),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Le fichier original est conservé. Taille maximale : 100 Mio. Aucune voix n’est installée automatiquement.',
                      ),
                    ),
                  ],
                ),
                if (job.running && job.progress != null)
                  ImportProgressView(
                    progress: job.progress!,
                    onCancel: job.cancel,
                  ),
                if (job.error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(job.error!.message),
                    ),
                  ),
                if (!job.running && job.result?.cancelled == true)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Import annulé'),
                  ),
                if (job.result?.existing == true &&
                    library.canOpen(job.result!.book!))
                  ListTile(
                    title: const Text(
                      'Ce livre est déjà dans votre bibliothèque.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onOpen(job.result!.book!),
                  ),
                if (library.error != null)
                  ListTile(
                    title: Text(library.error!.message),
                    subtitle: const Text('Réessayer'),
                    onTap: () => library.refresh(search: _search.text),
                  ),
                if (library.pendingRemovals.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Suppressions à terminer'),
                  ),
                for (final book in library.pendingRemovals)
                  _bookTile(book, pending: true),
                if (library.loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Chargement de la bibliothèque',
                    ),
                  ),
                if (!library.loading &&
                    library.books.isEmpty &&
                    library.pendingRemovals.isEmpty &&
                    library.error == null)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      library.searchText.isEmpty
                          ? 'Votre bibliothèque est vide. Importez votre premier livre EPUB.'
                          : 'Aucun livre ne correspond à cette recherche.',
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final columns = scaler.scale(18) > 28
                    ? 1
                    : (constraints.crossAxisExtent / 160).floor().clamp(1, 4);
                final width =
                    (constraints.crossAxisExtent - 20 * (columns - 1)) /
                    columns;
                final coverHeight = math.min(285.0, (width - 8) * 1.5);
                return SliverGrid.builder(
                  itemCount: library.books.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    mainAxisExtent:
                        coverHeight +
                        scaler.scale(18) * 1.35 * 3 +
                        scaler.scale(14) * 1.35 * 2 +
                        88,
                  ),
                  itemBuilder: (context, index) {
                    final book = library.books[index];
                    final busy = library.removing.contains(book.key.id);
                    final failed = library.removalErrors.containsKey(
                      book.key.id,
                    );
                    return LibraryBookCard(
                      key: ValueKey(book.key.id),
                      book: book,
                      coverHeight: coverHeight,
                      cache: _covers,
                      onOpen: library.canOpen(book)
                          ? () => widget.onOpen(book)
                          : null,
                      onRemove: library.removal == null
                          ? null
                          : () => _remove(book, retry: failed),
                      removing: busy,
                      failed: failed,
                    );
                  },
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                if (library.hasMore && !library.loading)
                  TextButton(
                    onPressed: library.nextPage,
                    child: const Text('Afficher plus de livres'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
