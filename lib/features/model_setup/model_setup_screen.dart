import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/app_error.dart';
import 'model_installer.dart';
import 'model_removal_service.dart';

class ModelSetupScreen extends StatefulWidget {
  const ModelSetupScreen({
    super.key,
    required this.installer,
    required this.removal,
  });
  final ModelInstaller installer;
  final ModelRemovalService removal;
  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen> {
  bool _removing = false;
  String? _message;
  final _actionFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    unawaited(widget.installer.refresh());
  }

  @override
  void dispose() {
    _actionFocus.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String description) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(description)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuer'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _install() async {
    final catalog = widget.installer.catalog;
    if (!await _confirm(
      'Installer la voix française ?',
      'La voix permet une écoute hors ligne. Choisissez le dossier local contenant les ${catalog.bundle.files.length} fichiers validés. ${catalog.totalBytes} octets seront copiés dans le stockage privé ; le dossier source sera conservé. Aucun téléchargement réseau. Kyutai : CC-BY-4.0 ; moteur et runtime : MIT.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _message = null);
    await widget.installer.install();
    if (mounted) _actionFocus.requestFocus();
  }

  Future<void> _remove() async {
    if (!await _confirm(
      'Supprimer la voix installée ?',
      'La lecture sera arrêtée et les fichiers privés de la voix ainsi que son cache audio seront supprimés. Le dossier source et les textes resteront disponibles.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _removing = true;
      _message = null;
    });
    try {
      await widget.removal.remove(widget.installer.catalog.bundle);
      await widget.installer.refresh();
      if (mounted) {
        setState(
          () => _message = 'Voix supprimée. Les textes restent disponibles.',
        );
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => _message =
              (failure is AppError
                      ? failure
                      : const AppError(ErrorCode.storageUnavailable))
                  .message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _removing = false);
        _actionFocus.requestFocus();
      }
    }
  }

  Future<void> _notices() async {
    final text = await rootBundle.loadString(
      'assets/models/THIRD_PARTY_NOTICES.txt',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Licences et attribution'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              showLicensePage(
                context: this.context,
                applicationName: 'uReader',
              );
            },
            child: const Text('Licences des dépendances'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.installer,
    builder: (context, _) {
      final installer = widget.installer;
      final busy =
          installer.busy ||
          _removing ||
          installer.state == ModelSetupState.checking;
      final status = switch (installer.state) {
        ModelSetupState.absent => 'Voix non installée',
        ModelSetupState.checking => 'Vérification de la voix…',
        ModelSetupState.choosing => 'Choisissez un dossier local',
        ModelSetupState.copying => 'Copie des fichiers…',
        ModelSetupState.verifying => 'Vérification des fichiers…',
        ModelSetupState.publishing => 'Activation de la voix…',
        ModelSetupState.ready => 'Voix française prête',
        ModelSetupState.error =>
          installer.error?.message ?? 'Préparation interrompue.',
      };
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Préparation de la voix',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const Text(
            'Une voix française pour écouter sans réseau. Aucune installation ni lecture automatique.',
          ),
          Text(
            'Taille : ${(installer.catalog.totalBytes / 1000000).toStringAsFixed(1)} Mo (${installer.catalog.bundle.files.length} fichiers). Prévoir aussi de la place pour les fichiers temporaires et le cache audio.',
          ),
          Text(
            installer.catalog.demonstrated
                ? 'Français vérifié sur la configuration Samsung/API 29 évaluée.'
                : 'Compatibilité française déclarée, écoute Android non démontrée.',
          ),
          Semantics(liveRegion: true, child: Text(_message ?? status)),
          if (installer.busy) ...[
            LinearProgressIndicator(
              value: installer.state == ModelSetupState.copying
                  ? installer.copiedBytes / installer.catalog.totalBytes
                  : null,
              semanticsLabel: 'Progression de la préparation',
            ),
            Text(
              '${installer.copiedBytes} octets copiés sur ${installer.catalog.totalBytes}',
            ),
          ],
          FilledButton(
            focusNode: _actionFocus,
            onPressed: busy || !installer.catalog.demonstrated
                ? null
                : _install,
            child: Text(
              installer.state == ModelSetupState.error
                  ? 'Réessayer'
                  : 'Installer depuis un dossier',
            ),
          ),
          if (installer.busy && installer.state != ModelSetupState.publishing)
            OutlinedButton(
              onPressed: () => unawaited(installer.cancel()),
              child: const Text('Annuler la préparation'),
            ),
          OutlinedButton(
            onPressed: busy || !installer.resourcesPresent ? null : _remove,
            child: const Text('Supprimer la voix'),
          ),
          TextButton(
            onPressed: _notices,
            child: const Text('Licences et attribution'),
          ),
          const Text(
            'Conservez les noms des fichiers du bundle. Un fichier manquant, altéré ou incomplet empêche l’activation. En cas d’échec, les textes restent consultables ; vérifiez le dossier et l’espace libre.',
          ),
        ],
      );
    },
  );
}
