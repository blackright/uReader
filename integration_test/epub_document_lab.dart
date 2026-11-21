// Manual debug entrypoint; no AppDependencies, SQLite, model installation or audio.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/android_document_source.dart';
import 'package:prototype/infrastructure/epub/epub_package_parser.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

void main() => runApp(const MaterialApp(home: DocumentLab()));

class DocumentLab extends StatefulWidget {
  const DocumentLab({super.key});
  @override
  State<DocumentLab> createState() => _DocumentLabState();
}

class _DocumentLabState extends State<DocumentLab> {
  final source = AndroidDocumentSource();
  bool running = false;
  String message =
      'Choisissez un EPUB synthétique. La base produit reste fermée.';
  String? operation;
  int generation = 0;
  void status(String text) {
    if (mounted) setState(() => message = text);
  }

  Future<void> start() async {
    if (running) return;
    setState(() => running = true);
    final op =
        'lab-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1000000)}';
    operation = op;
    final gen = ++generation;
    try {
      status('Sélection du fichier…');
      final handle = await source.choose(op, gen);
      if (handle == null) {
        status('Sélection annulée. Aucun livre publié.');
        return;
      }
      status('Copie et vérification…');
      final copy = await source.copyAndHash(handle);
      final archive = await source.openArchive();
      final count = archive.names.length;
      await EpubPackageParser(archive).parse();
      await archive.verifyRemaining();
      await archive.close();
      status(
        'Essai réussi : ${copy.bytes} octets copiés, $count entrées vérifiées. Aucun livre publié.',
      );
    } on BookFailure catch (e) {
      status(e.message);
    } catch (_) {
      status('Essai interrompu. Réessayez.');
    } finally {
      try {
        await source.cancel(op, gen);
      } catch (_) {
        /* may already be cancelled */
      }
      final support = await getApplicationSupportDirectory();
      final files = await BookFileStore.open(
        Directory(
          p.join(await support.resolveSymbolicLinks(), 'epub-source-lab'),
        ),
      );
      await files.removeStaging(op);
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> cancel() async {
    if (operation != null) await source.cancel(operation!, generation);
  }

  @override
  void dispose() {
    if (running) unawaited(cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Validation EPUB — sélection')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Laboratoire isolé : aucune migration ni import dans la bibliothèque produit.',
        ),
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(message)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: running ? null : start,
          child: const Text('Choisir un EPUB pour l’essai'),
        ),
        if (running)
          TextButton(onPressed: cancel, child: const Text('Annuler l’essai')),
      ],
    ),
  );
}
