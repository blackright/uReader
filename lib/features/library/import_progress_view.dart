import 'package:flutter/material.dart';

import 'book_importer.dart';

class ImportProgressView extends StatelessWidget {
  const ImportProgressView({
    super.key,
    required this.progress,
    required this.onCancel,
  });
  final ImportProgress progress;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    final label = switch (progress.step) {
      ImportStep.choosing => 'Choisissez un fichier EPUB',
      ImportStep.copying => 'Copie du livre',
      ImportStep.validating => 'Vérification du livre',
      ImportStep.finalizing => 'Finalisation : veuillez patienter',
      ImportStep.complete => 'Livre importé',
      ImportStep.cancelled => 'Import annulé',
      ImportStep.failed => 'Import interrompu',
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (progress.step == ImportStep.copying)
            Text('${progress.bytes} octets copiés'),
          if ([
            ImportStep.copying,
            ImportStep.validating,
            ImportStep.finalizing,
          ].contains(progress.step))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(
                semanticsLabel: 'Préparation du livre',
              ),
            ),
          if (progress.canCancel)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Annuler'),
              ),
            ),
        ],
      ),
    );
  }
}
