// Dedicated laboratory entry point. Does not open or migrate the product database.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/epub_projection_worker.dart';
import 'package:prototype/infrastructure/epub/image_policy.dart';

import 'epub_gate_resources.dart';

void main() => runApp(const MaterialApp(home: ProjectionGateScreen()));

class ProjectionGateScreen extends StatefulWidget {
  const ProjectionGateScreen({super.key});
  @override
  State<ProjectionGateScreen> createState() => _ProjectionGateState();
}

class _ProjectionGateState extends State<ProjectionGateScreen> {
  String _choice = gateFragments.keys.first;
  late Future<ProjectionResult> _projection;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _projection = EpubProjectionWorker.projectString(
      key: ContentKey(ContentKind.book, _choice, 1),
      chapterOrdinal: 0,
      xhtml: gateFragments[_choice]!,
      localStyles: ['.hidden {display:none}'],
    );
  }

  void _anchor(ProjectionResult result, String name) {
    final locator = result.anchors[name]!;
    final block = result.blocks.singleWhere((b) => b.id == locator.blockId);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ancre $name'),
        content: SingleChildScrollView(
          child: Text(block.text.substring(locator.offsetUtf16)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _text(BookBlock block) {
    final points = <int>{
      0,
      block.text.length,
      for (final span in block.inline) ...[span.startUtf16, span.endUtf16],
    }.toList()..sort();
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i + 1 < points.length; i++)
            TextSpan(
              text: block.text.substring(points[i], points[i + 1]),
              style: TextStyle(
                fontWeight:
                    block.inline.any(
                      (s) =>
                          s.strong &&
                          s.startUtf16 <= points[i] &&
                          s.endUtf16 >= points[i + 1],
                    )
                    ? FontWeight.bold
                    : null,
                fontStyle:
                    block.inline.any(
                      (s) =>
                          s.emphasis &&
                          s.startUtf16 <= points[i] &&
                          s.endUtf16 >= points[i + 1],
                    )
                    ? FontStyle.italic
                    : null,
              ),
            ),
        ],
      ),
      style: TextStyle(fontSize: block.kind == BookBlockKind.heading ? 24 : 18),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Validation EPUB — laboratoire')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            initialValue: _choice,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(
              labelText: 'Ressource synthétique',
            ),
            items: gateFragments.keys
                .map(
                  (id) => DropdownMenuItem(
                    value: id,
                    child: Text(
                      '$id — EPUB ${int.parse(id.split('-').last) <= 5 ? 2 : 3}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id != null) {
                setState(() {
                  _choice = id;
                  _load();
                });
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Essai du profil de rendu. Aucun livre personnel, aucune migration ni lecture vocale.',
          ),
        ),
        Expanded(
          child: FutureBuilder<ProjectionResult>(
            future: _projection,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('La projection de laboratoire a échoué.'),
                );
              }
              final result = snapshot.data;
              if (result == null) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Préparation du texte',
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: result.blocks.length + 1,
                itemBuilder: (context, index) {
                  if (index == result.blocks.length) {
                    final bytes = base64Decode(gatePngBase64);
                    final large = Uint8List.fromList(bytes);
                    ByteData.sublistView(large).setUint32(16, 8193);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!ImagePolicy.inspect(large).usable)
                          Semantics(
                            image: true,
                            label: 'Image remplacée : dimensions hors limites',
                            child: const ExcludeSemantics(
                              child: Text(
                                'Image remplacée : dimensions hors limites',
                              ),
                            ),
                          ),
                        if (!ImagePolicy.inspect([1, 2, 3]).usable)
                          Semantics(
                            image: true,
                            label: 'Image remplacée : fichier corrompu',
                            child: const ExcludeSemantics(
                              child: Text('Image remplacée : fichier corrompu'),
                            ),
                          ),
                        for (final name in result.anchors.keys)
                          TextButton(
                            onPressed: () => _anchor(result, name),
                            child: Text('Afficher l’ancre $name'),
                          ),
                      ],
                    );
                  }
                  final block = result.blocks[index];
                  if (block.kind == BookBlockKind.image) {
                    final bytes = base64Decode(gatePngBase64);
                    final local =
                        result.imageSources[block.resourceId] == 'cover.png';
                    return local && ImagePolicy.inspect(bytes).usable
                        ? Image.memory(
                            bytes,
                            width: 80,
                            height: 80,
                            semanticLabel: block.alternative ?? 'Image',
                            errorBuilder: (_, _, _) =>
                                Text(block.alternative ?? 'Image indisponible'),
                          )
                        : Text(block.alternative ?? 'Image indisponible');
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: block.kind == BookBlockKind.heading,
                          child: _text(block),
                        ),
                        if (!block.speechEligible)
                          const Text(
                            'Note consultable, exclue de la narration',
                          ),
                        for (final span in block.inline)
                          if (span.link != null)
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Lien de laboratoire'),
                                  content: Text(span.link!.target),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Fermer'),
                                    ),
                                  ],
                                ),
                              ),
                              child: Text(
                                'Ouvrir le lien : ${block.text.substring(span.startUtf16, span.endUtf16)}',
                              ),
                            ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
