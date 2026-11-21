import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import 'content_target_controller.dart';

class ContentSeekSheet extends StatefulWidget {
  const ContentSeekSheet({
    super.key,
    required this.book,
    required this.source,
    this.initial,
    this.confirmLabel = 'Confirmer le déplacement audio',
  });
  final Book book;
  final ParagraphNavigationSource source;
  final BookLocator? initial;
  final String confirmLabel;
  @override
  State<ContentSeekSheet> createState() => _ContentSeekSheetState();
}

class _ContentSeekSheetState extends State<ContentSeekSheet> {
  late final model = ContentTargetController(widget.book.key, widget.source)
    ..addListener(_changed);
  double draft = 0;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    model.initialize(initial: widget.initial);
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choisir un passage',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choisissez un chapitre ou une position dans le contenu. Rien ne change avant confirmation.',
            ),
            const SizedBox(height: 16),
            if (model.chapters.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.list),
                label: Text('Chapitre : ${model.chapter?.title ?? 'Choisir'}'),
                onPressed: model.loading
                    ? null
                    : () async {
                        final chosen = await showModalBottomSheet<BookChapter>(
                          context: context,
                          isScrollControlled: true,
                          builder: (ctx) => SafeArea(
                            child: SizedBox(
                              height: MediaQuery.sizeOf(ctx).height * .75,
                              child: ListView.builder(
                                itemCount: model.chapters.length,
                                itemBuilder: (_, i) => ListTile(
                                  title: Text(model.chapters[i].title),
                                  selected:
                                      model.chapter?.id == model.chapters[i].id,
                                  onTap: () =>
                                      Navigator.pop(ctx, model.chapters[i]),
                                ),
                              ),
                            ),
                          ),
                        );
                        if (chosen != null && mounted) {
                          await model.selectChapter(chosen);
                        }
                      },
              ),
            const SizedBox(height: 16),
            Text('Position souhaitée : ${(draft * 100).round()} % du contenu'),
            Slider(
              value: draft,
              label: '${(draft * 100).round()} % du contenu',
              onChanged: model.loading
                  ? null
                  : (v) => setState(() => draft = v),
              onChangeEnd: model.selectProgress,
            ),
            if (model.loading)
              const LinearProgressIndicator(
                semanticsLabel: 'Recherche du passage',
              ),
            if (model.error != null)
              Semantics(liveRegion: true, child: Text(model.error!)),
            if (model.chapter != null)
              TextButton(
                onPressed: model.loading
                    ? null
                    : () => model.selectChapter(model.chapter!),
                child: const Text('Début du chapitre / réessayer'),
              ),
            for (final choice in model.choices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected:
                    model.selected?.locator.blockId == choice.locator.blockId,
                title: Text(
                  choice.excerpt.isEmpty
                      ? 'Passage sans texte visible'
                      : choice.excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: const Icon(Icons.subject),
                onTap: model.loading
                    ? null
                    : () => model.choose(choice.locator),
              ),
            if (model.nextOrdinal != null)
              TextButton(
                onPressed: model.loading
                    ? null
                    : () => model.load(model.nextOrdinal!),
                child: const Text('Passages suivants'),
              ),
            if (model.selected != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cible retenue · début du paragraphe',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(model.selected!.excerpt),
                    if (model.actualProgress != null)
                      Text(
                        '${(model.actualProgress! * 100).floor()} % du contenu',
                      ),
                  ],
                ),
              ),
            FilledButton(
              onPressed: model.loading || model.selected == null
                  ? null
                  : () => Navigator.pop(context, model.selected!.locator),
              child: Text(widget.confirmLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    ),
  );
}
