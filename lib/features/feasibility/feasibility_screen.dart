import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:convert';

import 'feasibility_report.dart';
import 'feasibility_evaluator.dart';
import 'report_repository.dart';

class FeasibilityScreen extends StatefulWidget {
  const FeasibilityScreen({
    super.key,
    required this.repository,
    this.loadReport,
  });
  final ReportRepository repository;
  final Future<FeasibilityReport> Function()? loadReport;
  @override
  State<FeasibilityScreen> createState() => _FeasibilityScreenState();
}

class _FeasibilityScreenState extends State<FeasibilityScreen> {
  late final Future<FeasibilityReport> _report;
  bool _busy = false;
  String _message = '';
  final _exportFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    _report =
        widget.loadReport?.call() ??
        rootBundle
            .loadString('assets/reports/interim.json')
            .then(
              (s) => FeasibilityReport.fromJson(
                jsonDecode(s) as Map<String, dynamic>,
              ),
            );
  }

  @override
  void dispose() {
    _exportFocus.dispose();
    super.dispose();
  }

  Future<void> _export(FeasibilityReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exporter le bilan ?'),
        content: const Text(
          'Le rapport contient les résultats techniques, sans texte des livres ni audio. Choisissez ensuite sa destination.',
        ),
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
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _message = 'Export annulé.');
      _exportFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    try {
      final snapshot = FeasibilityReport.fromJson(
        report.toJson()
          ..['id'] = 'export-${DateTime.now().microsecondsSinceEpoch}',
      );
      await widget.repository.save(snapshot);
      final exported = await widget.repository.export(snapshot);
      if (mounted) {
        setState(
          () => _message = exported
              ? 'Bilan exporté.'
              : 'Export annulé. La copie privée est conservée.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Export impossible. Réessayez.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _exportFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FeasibilityReport>(
    future: _report,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Bilan indisponible. Le lecteur reste accessible.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: Text('Chargement du bilan…'));
      }
      final report = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Bilan de faisabilité',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Text(
            FeasibilityEvaluator.label(FeasibilityEvaluator.evaluate(report)),
          ),
          const Text(
            'Bilan intermédiaire des essais documentés sur Samsung API 29. Ce bilan ne décrit pas une nouvelle mesure de ce téléphone.',
          ),
          const Text(
            'Mesures absentes : non évaluées. Un seul évaluateur ; session de vingt minutes, contrôles système et reprise durable encore non démontrés. Annonce TalkBack sans voix non testée : réserve acceptée.',
          ),
          FilledButton(
            focusNode: _exportFocus,
            onPressed: _busy ? null : () => _export(report),
            child: Text(_busy ? 'Export en cours…' : 'Exporter le bilan'),
          ),
          Semantics(liveRegion: true, child: Text(_message)),
          for (final row in report.results.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                container: true,
                child: Text(
                  '${row.key} : ${switch (row.value.status) {
                    TrialStatus.passed => 'Réussi',
                    TrialStatus.failed => 'Échec',
                    TrialStatus.notEvaluated => 'Non évalué',
                  }}. ${switch (row.value.reason) {
                    'ten_texts_accepted' => 'Dix textes validés à l’écoute.',
                    'second_independent_evaluator_missing' => 'Une seconde évaluation indépendante est nécessaire.',
                    'accepted_accessibility_reservation' => 'Accessibilité partiellement vérifiée ; réserve acceptée.',
                    'cold_warm_measurements_missing' => 'Les mesures répétées à froid et à chaud restent à réaliser.',
                    'arbitrary_passage_change_pending' => 'Le changement de passage reste à vérifier.',
                    _ => 'Évaluation complète à réaliser.',
                  }}',
                ),
              ),
            ),
        ],
      );
    },
  );
}
