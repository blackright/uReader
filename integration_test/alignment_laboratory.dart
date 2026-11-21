// Standalone debug entry. No AppDependencies, product database or installed bundle writes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/word_alignment.dart';
import 'package:prototype/features/listening/prepared_text_map.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

import 'alignment/attention_decoder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: AlignmentLaboratory(
        corpusRun: String.fromEnvironment('ALIGNMENT_CORPUS_RUN'),
      ),
    ),
  );
}

class AlignmentLaboratory extends StatefulWidget {
  const AlignmentLaboratory({super.key, this.corpusRun = ''});
  final String corpusRun;
  @override
  State<AlignmentLaboratory> createState() => _AlignmentLaboratoryState();
}

class _AlignmentLaboratoryState extends State<AlignmentLaboratory> {
  LocalSegmentPlayer? _player;
  StreamSubscription<PlayerClockSample>? _subscription;
  late Directory _root;
  late PreparedTextMap _map;
  String? _sha, _error;
  final List<({int start, int end, SourceSpan source})> _cues = [];
  SourceSpan? _active;
  Duration _position = Duration.zero;
  PlayerClockState _state = PlayerClockState.stopped;
  bool _ready = false, _hasStarted = false;
  final _transportStartedOccurrences = <int>{};
  int _caseIndex = 0, _caseCount = 1, _loadIntent = 0, _playGeneration = 0;
  bool _continuous = false,
      _advancing = false,
      _traceTruncated = false,
      _playbackRequested = false;
  SessionToken _currentToken = SessionToken('alignment-lab', 0);
  StreamSubscription<PlayerEvent>? _playerSubscription;
  Map<String, dynamic>? _batchInput, _batchResult;
  final _caseEvidence = <String, Map<String, Object?>>{};
  String? _alignmentNotice;
  final _events = <Map<String, Object?>>[];
  final _timestamp = Stopwatch()..start();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _json(File file) async {
    if (await file.length() > 1048576) {
      throw StateError('Laboratory input limit');
    }
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> _load() async {
    var stage = 'support-directory';
    final intent = ++_loadIntent;
    _currentToken = SessionToken(
      'alignment-lab-$_caseIndex',
      ++_playGeneration,
    );
    if (mounted) {
      setState(() {
        _ready = false;
        _hasStarted = false;
        _active = null;
        _position = Duration.zero;
        _state = PlayerClockState.stopped;
        _error = null;
      });
    }
    try {
      await _player?.stop();
      if (intent != _loadIntent || !mounted) return;
      final support = await getApplicationSupportDirectory();
      final base = Directory(await support.resolveSymbolicLinks());
      _root = Directory('${base.path}/ureader-alignment-lab');
      stage = 'report';
      Map<String, dynamic> report;
      Map<String, dynamic> fixture;
      Map<String, dynamic> attention;
      if (widget.corpusRun.isEmpty) {
        report = await _json(File('${_root.path}/result.json'));
        fixture = await _json(File('${_root.path}/fixture.json'));
        attention = await _json(File('${_root.path}/attention.json'));
      } else {
        if (!RegExp(r'^corpus-[a-z0-9-]{1,48}$').hasMatch(widget.corpusRun)) {
          throw StateError('Invalid corpus identity');
        }
        _root = Directory(
          '${base.path}/ureader-alignment-corpus/${widget.corpusRun}',
        );
        if (_batchInput == null) {
          final inputFile = File('${_root.path}/input.json');
          _batchResult = await _json(File('${_root.path}/result.json'));
          if (_batchResult!['status'] != 'complete' ||
              _batchResult!['allPcmBytesIdentical'] != true ||
              sha256.convert(await inputFile.readAsBytes()).toString() !=
                  _batchResult!['inputSha256']) {
            throw StateError('Incomplete corpus parity');
          }
          _batchInput = await _json(inputFile);
          _caseCount = (_batchInput!['occurrences'] as List).length;
          if (_caseCount < 1 || _caseCount > 256) {
            throw StateError('Occurrence budget');
          }
        }
        final occurrence =
            (_batchInput!['occurrences'] as List)[_caseIndex] as Map;
        final id = occurrence['uniqueId'] as String;
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
          throw StateError('Unsafe corpus path');
        }
        final spec = (_batchInput!['uniqueCases'] as List)
            .cast<Map>()
            .firstWhere((s) => s['id'] == id);
        final result = (_batchResult!['results'] as List)
            .cast<Map>()
            .firstWhere((s) => s['id'] == id);
        final attFile = File('${_root.path}/$id/attention.json');
        if (sha256.convert(await attFile.readAsBytes()).toString() !=
            result['attentionSha256']) {
          throw StateError('Attention hash mismatch');
        }
        attention = await _json(attFile);
        fixture = {
          ...occurrence.map((k, v) => MapEntry(k as String, v)),
          'tokenIds': spec['tokenIds'],
          'tokenOffsets': spec['tokenOffsets'],
        };
        report = {
          'androidExecuted': _batchResult!['androidExecuted'],
          'pcmBytesIdentical': result['pcmBytesIdentical'],
          'runs': result['runs'],
        };
      }
      if (report['androidExecuted'] != true ||
          report['pcmBytesIdentical'] != true) {
        throw StateError('Android parity proof required');
      }
      stage = 'fixture-attention';

      stage = 'text-mapping';
      final source = fixture['source'] as String;
      _map = PreparedTextMap.fromSource(
        source,
        sourceOffset: (fixture['sourceOffset'] as int?) ?? 0,
      );
      if (_map.prepared != fixture['prepared'] ||
          sha256.convert(utf8.encode(source)).toString() !=
              fixture['sourceSha256'] ||
          sha256.convert(utf8.encode(_map.prepared)).toString() !=
              fixture['preparedSha256']) {
        throw StateError('Text identity mismatch');
      }
      if (jsonEncode(fixture['tokenIds']) !=
          jsonEncode(attention['tokenIds'])) {
        throw StateError('Token identity mismatch');
      }
      stage = 'candidate-identity';
      final candidate = (report['runs'] as List).cast<Map>().firstWhere(
        (r) => r['kind'] == 'candidate',
      );
      final name = candidate['wav'] as String;
      if (!(widget.corpusRun.isEmpty
              ? RegExp(r'^generation-[a-f0-9-]+\.wav$')
              : RegExp(r'^[a-f0-9]{64}/generation-[a-f0-9-]+\.wav$'))
          .hasMatch(name)) {
        throw StateError('Invalid laboratory path');
      }
      stage = 'wav-read';
      final wav = File('${_root.path}/$name');
      if (await wav.length() > 960044) throw StateError('WAV limit');
      final bytes = await wav.readAsBytes();
      _sha = sha256.convert(bytes).toString();
      if (_sha != candidate['wavSha256']) {
        throw StateError('WAV identity mismatch');
      }
      stage = 'attention-decode';
      var preparedCues = <LaboratoryCue>[];
      _alignmentNotice = null;
      try {
        preparedCues = decodeAttention(
          attention: [
            for (final row in attention['rows'] as List)
              [for (final p in row as List) (p as num).toDouble()],
          ],
          tokenOffsets: [
            for (final pair in fixture['tokenOffsets'] as List)
              ((pair as List)[0] as int, pair[1] as int),
          ],
          prepared: _map.prepared,
          sampleCount: candidate['samples'] as int,
        );
      } on ArgumentError {
        _alignmentNotice =
            'Alignement expérimental indisponible pour ce segment.';
      }
      stage = 'source-cues';
      _cues.clear();
      for (final cue in preparedCues) {
        final sourceRange = _map.sourceRange(cue.startUtf16, cue.endUtf16);
        if (sourceRange == null) continue;
        if (_cues.isNotEmpty &&
            _cues.last.source.start == sourceRange.start &&
            _cues.last.source.end == sourceRange.end) {
          final previous = _cues.removeLast();
          _cues.add((
            start: previous.start,
            end: cue.endSample,
            source: sourceRange,
          ));
        } else {
          _cues.add((
            start: cue.startSample,
            end: cue.endSample,
            source: sourceRange,
          ));
        }
      }
      stage = 'clock-cache';
      final files = await PrivateFileStore.open(
        Directory('${base.path}/ureader-alignment-clock'),
      );
      final cache = AudioCache(files);
      stage = 'cache-publish';
      await cache.publish(
        _sha!,
        bytes,
        SpeechOutput(
          audioHandle: _sha!,
          sampleRate: 24000,
          channels: 1,
          encoding: AudioEncoding.pcm16,
          durationMs: (candidate['samples'] as int) * 1000 ~/ 24000,
          byteSize: bytes.length,
          start: Locator(
            textId: 'lab',
            corpusVersion: 1,
            passageId: 'p',
            offsetUtf16: _map.sourceOffset,
          ),
          end: Locator(
            textId: 'lab',
            corpusVersion: 1,
            passageId: 'p',
            offsetUtf16: _map.sourceOffset + source.length,
          ),
        ),
      );
      if (!mounted) return;
      stage = 'player-initialize';
      if (intent != _loadIntent || !mounted) return;
      _player ??= LocalSegmentPlayer(cache);
      _subscription ??= _player!.clockSamples.listen(_sample);
      _playerSubscription ??= _player!.events.listen(_playerEvent);
      if (widget.corpusRun.isNotEmpty) {
        final expected = (fixture['unitIds'] as List).cast<String>().toSet();
        final seen = {
          for (final cue in _cues)
            '${fixture['passageId']}-${cue.source.start}-${cue.source.end}',
        };
        _caseEvidence[fixture['id'] as String] = {
          'id': fixture['id'],
          'passageId': fixture['passageId'],
          'audioSha256': _sha,
          'sourceSha256': fixture['sourceSha256'],
          'preparedSha256': fixture['preparedSha256'],
          'alignmentAvailable': _alignmentNotice == null,
          'missingSourceUnits': expected.difference(seen).toList(),
          'cues': [
            for (final cue in _cues)
              {
                'startSample': cue.start,
                'endSample': cue.end,
                'sourceStart': cue.source.start,
                'sourceEnd': cue.source.end,
              },
          ],
        };
      }
      setState(() => _ready = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Banc indisponible : $stage (${error.runtimeType}).',
        );
      }
    }
  }

  void _sample(PlayerClockSample sample) {
    if (!mounted ||
        sample.audioSha256 != _sha ||
        sample.segmentId != _sha ||
        !sample.token.matches(_currentToken)) {
      return;
    }
    if (sample.state == PlayerClockState.playing) _hasStarted = true;
    if (sample.state == PlayerClockState.stopped) _hasStarted = false;
    SourceSpan? active;
    if (_hasStarted && sample.state != PlayerClockState.stopped) {
      final sampleIndex = sample.position.inMicroseconds * 24000 ~/ 1000000;
      for (final cue in _cues) {
        if (cue.start <= sampleIndex && sampleIndex < cue.end) {
          active = cue.source;
          break;
        }
      }
    }
    setState(() {
      _position = sample.position;
      _state = sample.state;
      _active = active;
    });
    if (_events.length < 20000) {
      final event = <String, Object?>{
        'caseIndex': _caseIndex,
        'sessionId': sample.token.sessionId,
        'generation': sample.token.generation,
        'audioSha256': sample.audioSha256,
        'playerMs': sample.position.inMilliseconds,
        'state': sample.state.name,
        'clockMonotonicUs': sample.monotonicMicros,
        'sourceStart': active?.start,
        'sourceEnd': active?.end,
      };
      _events.add(event);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        event['afterFrameMonotonicUs'] = _timestamp.elapsedMicroseconds;
      });
    } else {
      _traceTruncated = true;
      unawaited(_stop());
    }
  }

  Future<void> _select(int index) async {
    if (index < 0 || index >= _caseCount) return;
    _caseIndex = index;
    await _load();
  }

  void _playerEvent(PlayerEvent event) {
    if (event.kind == PlayerEventKind.started &&
        event.token.matches(_currentToken)) {
      _transportStartedOccurrences.add(_caseIndex);
    }
    if (event.kind != PlayerEventKind.completed ||
        !event.token.matches(_currentToken) ||
        !_continuous ||
        _advancing) {
      return;
    }
    unawaited(_advance());
  }

  Future<void> _advance() async {
    _advancing = true;
    try {
      if (_caseIndex + 1 >= _caseCount) {
        _continuous = false;
        return;
      }
      await _select(_caseIndex + 1);
      if (_continuous && mounted && _ready) await _play();
    } finally {
      _advancing = false;
    }
  }

  Future<void> _stop() async {
    _continuous = false;
    await _player?.stop();
  }

  Future<void> _exportCues() async {
    if (widget.corpusRun.isEmpty) return;
    await File('${_root.path}/corpus-cues.json').writeAsString(
      jsonEncode({
        'g1': 'not_evaluated',
        'inputSha256': _batchResult!['inputSha256'],
        'corpusSha256': _batchInput!['corpusSha256'],
        'occurrencesExpected': _caseCount,
        'occurrencesDecoded': _caseEvidence.length,
        'audioPlaybackRequested': _playbackRequested,
        'cases': _caseEvidence.values.toList(),
      }),
    );
  }

  Future<void> _playCorpus() async {
    _continuous = false;
    await _select(0);
    if (!mounted || !_ready) return;
    _events.clear();
    _transportStartedOccurrences.clear();
    _traceTruncated = false;
    _continuous = true;
    await _play();
  }

  Future<void> _play() async {
    _hasStarted = false;
    _playbackRequested = true;
    try {
      final token = _currentToken = SessionToken(
        'alignment-lab-$_caseIndex',
        ++_playGeneration,
      );
      await _player!.open(_sha!, token);
      if (!mounted || !token.matches(_currentToken) || !_ready) return;
      await _player!.play();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Lecture de laboratoire interrompue.');
      }
    }
  }

  Future<void> _export() async {
    await _stop();
    final path = File(
      '${_root.path}/clock-visible-trace-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await path.writeAsString(
      jsonEncode({
        'g1': 'not_evaluated',
        'audioSha256': widget.corpusRun.isEmpty ? _sha : null,
        'corpusRun': widget.corpusRun,
        'inputSha256': _batchResult?['inputSha256'],
        'corpusSha256': _batchInput?['corpusSha256'],
        'occurrenceMap': _batchInput == null
            ? null
            : [
                for (final c in _batchInput!['occurrences'] as List)
                  {
                    'id': c['id'],
                    'passageId': c['passageId'],
                    'sourceOffset': c['sourceOffset'],
                    'uniqueId': c['uniqueId'],
                  },
              ],
        'clockEpoch': 'local player instance',
        'frameEpoch': 'laboratory stopwatch; separate epoch',
        'events': _events,
        'traceTruncated': _traceTruncated,
        'transportStartedOccurrences': _transportStartedOccurrences.toList(),
        'occurrencesExpected': _caseCount,
        'notice': 'Software trace only. Audible/visible audiovisual annotations required.',
      }),
    );
  }

  @override
  void dispose() {
    ++_loadIntent;
    unawaited(_playerSubscription?.cancel());
    unawaited(_subscription?.cancel());
    unawaited(_player?.dispose());
    _timestamp.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alignement — laboratoire')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Candidat expérimental non qualifié. G1 reporté. Aucun suivi produit activé.',
          ),
          if (_error != null) Text(_error!),
          if (widget.corpusRun.isNotEmpty)
            Text(
              'Segment ${_caseIndex + 1} / $_caseCount',
              key: const ValueKey('lab-case-index'),
            ),
          if (_alignmentNotice != null) Text(_alignmentNotice!),
          if (!_ready && _error == null)
            const Text('Chargement des preuves Android…'),
          if (_ready) ...[
            const SizedBox(height: 24),
            Semantics(
              label: _map.source,
              child: ExcludeSemantics(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 26,
                      height: 1.5,
                      color: Colors.black,
                    ),
                    children: [
                      if (_active == null)
                        TextSpan(text: _map.source)
                      else ...[
                        TextSpan(
                          text: _map.source.substring(
                            0,
                            _active!.start - _map.sourceOffset,
                          ),
                        ),
                        TextSpan(
                          text: _map.source.substring(
                            _active!.start - _map.sourceOffset,
                            _active!.end - _map.sourceOffset,
                          ),
                          style: const TextStyle(
                            backgroundColor: Color(0xffa8d5ba),
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: _map.source.substring(
                            _active!.end - _map.sourceOffset,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Text(
              'Position player : ${_position.inMilliseconds} ms · ${_state.name}',
            ),
            FilledButton(
              onPressed: () {
                _continuous = false;
                _play();
              },
              child: const Text('Jouer l’extrait expérimental'),
            ),
            TextButton(
              onPressed: _state == PlayerClockState.playing
                  ? _player?.pause
                  : null,
              child: const Text('Pause'),
            ),
            TextButton(
              onPressed: _hasStarted && _state == PlayerClockState.paused
                  ? _player?.play
                  : null,
              child: const Text('Reprendre'),
            ),
            TextButton(onPressed: _stop, child: const Text('Arrêter')),
            if (widget.corpusRun.isNotEmpty) ...[
              TextButton(
                onPressed: _caseIndex == 0
                    ? null
                    : () {
                        _continuous = false;
                        _select(_caseIndex - 1);
                      },
                child: const Text('Segment précédent'),
              ),
              TextButton(
                onPressed: _caseIndex + 1 >= _caseCount
                    ? null
                    : () {
                        _continuous = false;
                        _select(_caseIndex + 1);
                      },
                child: const Text('Segment suivant'),
              ),
              FilledButton(
                onPressed: _playCorpus,
                child: const Text('Jouer le corpus expérimental'),
              ),
              TextButton(
                onPressed: _exportCues,
                child: const Text('Exporter les cues sans son'),
              ),
            ],
            TextButton(
              onPressed: _export,
              child: const Text('Exporter la trace logicielle'),
            ),
          ],
        ],
      ),
    ),
  );
}
