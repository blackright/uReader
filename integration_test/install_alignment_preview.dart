// Explicit debug-only installation tool. Uses the product installer and keeps
// the previous voice version intact; never writes a readiness flag directly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/features/model_setup/model_installer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) throw StateError('Debug installation tool only');
  runApp(const MaterialApp(home: _InstallPreview()));
}

class _InstallPreview extends StatefulWidget {
  const _InstallPreview();
  @override
  State<_InstallPreview> createState() => _InstallPreviewState();
}

class _InstallPreviewState extends State<_InstallPreview> {
  String status = 'Vérification du bundle de développement…';
  @override
  void initState() {
    super.initState();
    _install();
  }

  Future<void> _install() async {
    AppDependencies? dependencies;
    ModelInstaller? installer;
    try {
      final support = await getApplicationSupportDirectory();
      final root = await support.resolveSymbolicLinks();
      final source = Directory(p.join(root, 'alignment-preview-source'));
      if (await FileSystemEntity.type(source.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw StateError('Missing private source directory');
      }
      dependencies = await AppDependencies.open();
      final models = dependencies.models!;
      if (!models.catalog.alignmentAvailable ||
          models.catalog.alignmentQualified) {
        throw StateError('Expected an unvalidated development preview');
      }
      installer = ModelInstaller(
        catalog: models.catalog,
        files: dependencies.files,
        database: dependencies.database,
        gate: models.gate,
        source: _PrivateSource(
          source,
          models.catalog.bundle.files.map((f) => f.relativePath).toSet(),
        ),
        beforePublication: dependencies.playback?.suspendVoice,
        onSettled: dependencies.playback?.resumeVoice,
      );
      installer.addListener(() {
        if (mounted) {
          setState(
            () => status = 'Installation : ${installer!.copiedBytes} octets',
          );
        }
      });
      await installer.install();
      if (installer.state != ModelSetupState.ready) {
        throw StateError('Installation failed: ${installer.error}');
      }
      await File(p.join(root, 'alignment-preview-install.json')).writeAsString(
        jsonEncode({
          'status': 'installed',
          'version': models.catalog.bundle.version,
          'g1Verdict': 'not_evaluated',
          'previousVersionPreserved': true,
        }),
        flush: true,
      );
      if (mounted) {
        setState(
          () => status =
              'Bundle de développement installé. Validation G1 non évaluée.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => status = 'Installation refusée : $error');
    } finally {
      await installer?.close();
      await dependencies?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Installation vocale de développement')),
    body: Padding(padding: const EdgeInsets.all(24), child: Text(status)),
  );
}

class _PrivateSource implements LocalBundleSource {
  _PrivateSource(this.directory, this.names);
  final Directory directory;
  final Set<String> names;
  bool closed = false;
  @override
  Future<bool> chooseFolder() async => !closed;
  @override
  Stream<List<int>> readFile(String name) async* {
    if (closed || !names.contains(name) || p.basename(name) != name) {
      throw StateError('Invalid source file');
    }
    final file = File(p.join(directory.path, name));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        p.dirname(await file.resolveSymbolicLinks()) !=
            await directory.resolveSymbolicLinks()) {
      throw StateError('Unsafe source path');
    }
    await for (final bytes in file.openRead()) {
      if (closed) throw StateError('Cancelled');
      yield bytes;
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
