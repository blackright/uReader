import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/brand_mark.dart';

class WelcomeStore {
  WelcomeStore(Directory root) : file = File('${root.path}/welcome-v1.done');
  final File file;
  Future<bool> completed() async =>
      await file.exists() && await file.readAsString() == '1';
  Future<void> complete() async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString('1', flush: true);
    await temporary.rename(file.path);
  }
}

class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key, required this.store, required this.child});
  final WelcomeStore store;
  final Widget child;
  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  bool? done;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool value;
    try {
      value = await widget.store.completed();
    } catch (_) {
      value = false;
    }
    if (mounted) setState(() => done = value);
  }

  @override
  Widget build(BuildContext context) => done == null
      ? const BrandedSplash()
      : done!
      ? widget.child
      : WelcomeScreen(
          onFinish: () async {
            await widget.store.complete();
            if (mounted) setState(() => done = true);
          },
        );
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinish});
  final Future<void> Function() onFinish;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  int step = 0;
  bool saving = false;
  String? error;
  static const pages = [
    (
      'VOTRE BIBLIOTHÈQUE',
      'Vos livres.\nVotre univers.',
      'Importez vos EPUB depuis le téléphone et retrouvez vos livres, vos couvertures et votre progression au même endroit.',
      Icons.auto_stories_rounded,
      '01 / Lire',
    ),
    (
      'À VOTRE RYTHME',
      'Un confort\nqui vous ressemble.',
      'Choisissez les pages ou le défilement, adaptez la taille du texte et la couleur du suivi. Gardez vos passages préférés grâce aux signets.',
      Icons.tune_rounded,
      '02 / Personnaliser',
    ),
    (
      'UNE AUTRE FAÇON DE LIRE',
      'Laissez la voix\nprendre le relais.',
      'Installez la voix française depuis l’onglet Voix, puis écoutez vos livres hors ligne. Un appui long permet de choisir où commencer ; le suivi accompagne le passage lu.',
      Icons.headphones_rounded,
      '03 / Écouter',
    ),
  ];
  Future<void> finish() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onFinish();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Votre choix n’a pas pu être enregistré. Réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = pages[step];
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bounds.maxHeight - 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 36),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'uReader',
                          style: TextStyle(fontFamily: 'serif', fontSize: 24),
                        ),
                      ),
                      TextButton(
                        onPressed: saving ? null : finish,
                        child: const Text('Passer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Container(
                    height: 185,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: -.10,
                          child: Container(
                            width: 116,
                            height: 140,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary
                                  .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        Container(
                          width: 116,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .12),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            page.$4,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 58,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    page.$1,
                    style: TextStyle(
                      letterSpacing: 1.8,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      page.$2,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 34,
                        height: 1.12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    page.$3,
                    style: const TextStyle(fontSize: 16, height: 1.55),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    page.$5,
                    semanticsLabel: 'Étape ${step + 1} sur 3',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 14),
                  if (error != null)
                    Semantics(liveRegion: true, child: Text(error!)),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : step == 2
                        ? finish
                        : () => setState(() => step++),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        saving
                            ? 'Enregistrement…'
                            : step == 2
                            ? 'Ouvrir ma bibliothèque'
                            : 'Continuer',
                      ),
                    ),
                  ),
                  if (step > 0)
                    TextButton(
                      onPressed: saving ? null : () => setState(() => step--),
                      child: const Text('Précédent'),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vos livres restent sur votre appareil.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
