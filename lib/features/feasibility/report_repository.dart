import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../infrastructure/files/private_file_store.dart';
import 'feasibility_report.dart';

class ReportRepository {
  ReportRepository(this.root);
  final Directory root;
  static const _export = MethodChannel('com.ureader.prototype/reports/v1');
  Future<Directory> _directory() async {
    final store = await PrivateFileStore.open(root);
    final directory = Directory('${store.root.path}/reports');
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Lien refusé');
    }
    await directory.create();
    return directory;
  }

  Future<void> save(FeasibilityReport report) async {
    final directory = await _directory();
    final file = File('${directory.path}/${report.id}.json');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Preuve déjà enregistrée');
    }
    await file.create(exclusive: true);
    await file.writeAsString(jsonEncode(report.toJson()), flush: true);
  }

  Future<FeasibilityReport> load(String id) async {
    safeId(id);
    final directory = await _directory();
    final file = File('${directory.path}/$id.json');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Rapport indisponible');
    }
    if (await file.length() > 1024 * 1024) {
      throw StateError('Rapport trop grand');
    }
    return FeasibilityReport.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<bool> export(FeasibilityReport report) async =>
      await _export.invokeMethod<bool>('export', {
        'id': report.id,
        'json': jsonEncode(report.toJson()),
      }) ??
      false;
}
