import '../domain/book_reader.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/app_error.dart';
import '../features/feasibility/feasibility_screen.dart';
import '../features/model_setup/model_setup_screen.dart';
import '../features/demo_reader/demo_reader_screen.dart';
import '../features/library/library_controller.dart';
import '../features/library/book_import_controller.dart';
import '../features/library/library_screen.dart';
import '../features/book_reader/book_reader_screen.dart';
import 'dependencies.dart';
import 'reader_theme.dart';
import '../domain/books.dart';
import '../features/audio_player/full_player_screen.dart';
import '../features/audio_player/mini_player.dart';

class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key, this.createDependencies});

  /// Si fourni, l’appelant conserve la propriété et la fermeture des dépendances.
  final Future<AppDependencies> Function()? createDependencies;
  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late final Future<AppDependencies> _initialization;
  AppDependencies? _dependencies;
  LibraryController? _library;
  BookImportController? _import;
  int _selected = 0;
  bool _dark = false;
  int _themeIntent = 0;
  Future<void> _appearanceChanged() async {
    final intent = ++_themeIntent;
    final deps = _dependencies;
    if (deps == null) return;
    try {
      final value = await deps.bookPreferences.read();
      if (mounted && intent == _themeIntent) {
        setState(() => _dark = value.theme == ReaderTheme.dark);
      }
    } on BookFailure {
      // A failed presentation preference must not prevent opening the library.
    }
    if (mounted) await deps.playerPresenter?.initialize();
  }

  @override
  void initState() {
    super.initState();
    _initialization =
        (widget.createDependencies?.call() ?? AppDependencies.open()).then((
          deps,
        ) {
          if (!mounted) {
            if (widget.createDependencies == null) {
              unawaited(deps.dispose());
            }
          } else {
            _dependencies = deps;
            setState(() => _dark = deps.initialReaderTheme == ReaderTheme.dark);
            _library = LibraryController(
              deps.books,
              normalizeKey: deps.normalizeBookKey,
              removal: deps.bookRemoval,
            );
            _import = BookImportController(deps.bookImporter);
          }
          return deps;
        });
  }

  @override
  void dispose() {
    _import?.dispose();
    _library?.dispose();
    final deps = _dependencies;
    if (deps != null && widget.createDependencies == null) {
      unawaited(deps.dispose());
    }
    super.dispose();
  }

  Future<void> _openHeard(
    BuildContext ctx,
    Book book,
    BookLocator locator,
  ) async {
    final deps = _dependencies;
    if (deps == null) return;
    final generation = deps.playback?.sessionGeneration;
    final reader = deps.createBookReader(book);
    await reader.initialize();
    if (reader.error == null) await reader.go(locator);
    if (!ctx.mounted ||
        generation != deps.playback?.sessionGeneration ||
        deps.playback?.bookKey != book.key) {
      await reader.close();
      return;
    }
    await Navigator.of(ctx).push<void>(
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(
          book: book,
          content: deps.bookContent,
          controller: reader,
          onOpenPlayer: () => _openPlayer(ctx),
          onPresentationChanged: _appearanceChanged,
        ),
      ),
    );
  }

  void _openPlayer(BuildContext ctx) {
    final presenter = _dependencies?.playerPresenter;
    if (presenter == null) return;
    Navigator.of(ctx).push<void>(
      MaterialPageRoute(
        builder: (_) => FullPlayerScreen(
          presenter: presenter,
          onShowHeard: (book, locator) => _openHeard(ctx, book, locator),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'uReader',
    debugShowCheckedModeBanner: false,
    theme: ReaderVisualTheme.theme(dark: _dark),
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: FutureBuilder<AppDependencies>(
      future: _initialization,
      builder: (context, snapshot) {
        final ready = snapshot.hasData;
        return Scaffold(
          appBar: ready && _selected == 0
              ? null
              : AppBar(title: const Text('uReader')),
          body: SafeArea(
            child: ready && _selected == 0
                ? LibraryScreen(
                    library: _library!,
                    importController: _import!,
                    recoveryIssues: snapshot.data!.bookRecoveryIssues,
                    images: snapshot.data!.bookContent,
                    onOpen: (book) => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => BookReaderScreen(
                          book: book,
                          onOpenPlayer: () => _openPlayer(context),
                          onPresentationChanged: _appearanceChanged,
                          controller: snapshot.data!.createBookReader(book),
                          content: snapshot.data!.bookContent,
                        ),
                      ),
                    ),
                  )
                : ready && _selected == 1
                ? DemoReaderScreen(
                    corpus: snapshot.data!.corpus,
                    reader: snapshot.data!.reader,
                    playback: snapshot.data!.playback,
                  )
                : ready && _selected == 3
                ? FeasibilityScreen(repository: snapshot.data!.reports)
                : ready && _selected == 2
                ? snapshot.data!.models == null
                      ? const Center(
                          child: Text(
                            'Le catalogue vocal est indisponible. Les textes restent consultables.',
                          ),
                        )
                      : ModelSetupScreen(
                          installer: snapshot.data!.models!,
                          removal: snapshot.data!.modelRemoval,
                        )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (snapshot.hasError)
                          Text(
                            (snapshot.error is AppError
                                    ? snapshot.error! as AppError
                                    : const AppError(
                                        ErrorCode.storageUnavailable,
                                      ))
                                .message,
                          )
                        else if (!ready)
                          const Text('Préparation du stockage local…'),
                      ],
                    ),
                  ),
          ),
          bottomNavigationBar: ready
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (snapshot.data!.playerPresenter != null)
                      MiniPlayer(
                        presenter: snapshot.data!.playerPresenter!,
                        onOpen: () => _openPlayer(context),
                      ),
                    NavigationBar(
                      selectedIndex: _selected,
                      onDestinationSelected: (index) =>
                          setState(() => _selected = index),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.menu_book),
                          label: 'Livres',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.science_outlined),
                          label: 'Démo',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.record_voice_over),
                          label: 'Voix',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.fact_check_outlined),
                          label: 'Bilan',
                        ),
                      ],
                    ),
                  ],
                )
              : null,
        );
      },
    ),
  );
}
