import 'package:flutter/material.dart';

import 'bookmark_controller.dart';

class BookmarksSheet extends StatefulWidget {
  const BookmarksSheet({super.key, required this.controller});
  final BookmarkController controller;
  @override
  State<BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<BookmarksSheet> {
  BookmarkController get model => widget.controller;
  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) model.load();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    super.dispose();
  }

  Future<void> _open(Future<bool> action) async {
    if (await action && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    liveRegion: true,
    label: model.error ?? model.status,
    child: SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              'Mes passages',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(model.reader.book.title),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: model.busy ? null : model.addVisible,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Ajouter un signet au passage visible'),
            ),
            const SizedBox(height: 12),
            if (model.busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Chargement ou enregistrement des signets',
              ),
            if (model.status != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ExcludeSemantics(child: Text(model.status!)),
              ),
            if (model.error != null) ...[
              ExcludeSemantics(child: Text(model.error!)),
              TextButton(
                onPressed: model.busy ? null : model.retry,
                child: const Text('Réessayer'),
              ),
            ],
            if (model.proposal != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.proposal!.chapter,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(model.proposal!.context),
                    TextButton(
                      onPressed: model.busy ? null : model.confirmProposal,
                      child: const Text('Ajouter ce passage voisin'),
                    ),
                  ],
                ),
              ),
            if (model.fallback != null) ...[
              if (model.reader.chapters.any(
                (c) => c.id == model.fallback!.chapterId,
              ))
                TextButton(
                  onPressed: model.busy
                      ? null
                      : () => _open(model.openFallback()),
                  child: const Text('Ouvrir le chapitre proposé'),
                ),
              TextButton(
                onPressed: model.busy
                    ? null
                    : () => _open(model.openFallback(chapter: false)),
                child: const Text('Ouvrir le début du livre'),
              ),
            ],
            if (!model.busy && model.entries.isEmpty && model.error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Aucun signet pour le moment. Gardez ici les passages que vous souhaitez retrouver.',
                ),
              ),
            for (final entry in model.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    key: ValueKey('bookmark-${entry.bookmark.id}'),
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    title: Text(
                      entry.chapter,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        entry.context,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    leading: Icon(
                      entry.exact
                          ? Icons.bookmark_outline
                          : Icons.bookmark_remove_outlined,
                    ),
                    onTap: model.busy
                        ? null
                        : () => _open(model.open(entry.bookmark)),
                    trailing: IconButton(
                      key: ValueKey('bookmark-remove-${entry.bookmark.id}'),
                      tooltip: 'Supprimer ce signet',
                      onPressed: model.busy
                          ? null
                          : () => model.remove(entry.bookmark),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
            if (model.hasNext)
              TextButton(
                onPressed: model.busy ? null : () => model.load(next: true),
                child: const Text('Signets suivants'),
              ),
            TextButton(
              onPressed: model.busy ? null : () => model.load(),
              child: const Text('Revenir aux premiers signets'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer les signets'),
            ),
          ],
        ),
      ),
    ),
  );
}
