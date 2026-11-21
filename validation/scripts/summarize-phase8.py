"""Summarize actual phase-8 events, preserving failed attempts and missing values."""
import json
import statistics
from pathlib import Path


def summarize(directory):
    directory = Path(directory)
    cold = []
    warm = []
    for path in sorted((directory / 'profile-bench').glob('bench-run-*.json')):
        report = json.loads(path.read_text(encoding='utf-8'))
        if report.get('status') != 'passed':
            continue
        samples = [event for event in report['events'] if event.get('kind') == 'sample']
        if report['mode'] == 'cold':
            cold.extend(samples)
        elif report['mode'] == 'warm':
            warm.extend(samples[-5:])  # One explicit warm-up is excluded.

    def latency(samples):
        return {'count': len(samples), 'samples': samples,
                'medianFirstPcmUs': statistics.median(s['firstPcmUs'] for s in samples) if samples else None,
                'medianPlayerStartedUs': statistics.median(s['playerStartedUs'] for s in samples) if samples else None,
                'firstAudibleSoundUs': None}

    attempts = []
    for folder in ['profile-bench', 'profile-duration-retry']:
        path = directory / folder / 'bench-run-07.json'
        if not path.exists():
            continue
        report = json.loads(path.read_text(encoding='utf-8'))
        samples = report.get('systemSamples', [])
        events = report.get('events', [])
        completed = [e for e in events if e.get('kind') == 'duration_finished']
        starts = [e for e in events if e.get('kind') == 'sample']
        pss = [s.get('pssKiB', s.get('totalPssKiB')) for s in samples]
        pss = [value for value in pss if value is not None]
        gaps = [e['gapSincePreviousCompletionUs'] for e in starts if e.get('gapSincePreviousCompletionUs') is not None]
        before = samples[0].get('level') if samples else None
        after = samples[-1].get('level') if samples else None
        attempts.append({'source': str(path.relative_to(directory)), 'status': report.get('status', 'running'),
                         'lastObservedSeconds': samples[-1].get('runElapsedSeconds') if samples else None,
                         'completedSessionMs': completed[-1]['elapsedMs'] if completed else None,
                         'segmentsStarted': len(starts), 'systemSamples': len(samples),
                         'sampledPeakPssKiB': max(pss) if pss else None,
                         'batteryBeforePercent': before, 'batteryLastObservedPercent': after,
                         'batteryObservedChangePoints': after - before if before is not None and after is not None else None,
                         'usbPowered': samples[-1].get('usbPowered') if samples else None,
                         'medianGapUs': statistics.median(gaps) if gaps else None,
                         'maxObservedGapUs': max(gaps) if gaps else None,
                         'diagnosticEvents': [e for e in events if e.get('kind') in
                                              ['done', 'engine_failure', 'audio_interruption', 'output_became_noisy']]})
    return {'date': '2026-11-13', 'buildMode': 'profile',
            'cold': latency(cold), 'warm': latency(warm), 'warmupExcluded': True,
            'durationAttempts': attempts, 'firstAudibleSoundMeasured': False,
            'pcmMeaning': 'completed local WAV available to application, not first internal decoder sample',
            'cacheHit': 'not_evaluated; current adapter always synthesizes',
            'independentIntelligibilityRatings': 'not_evaluated',
            'physicalInterruptionsAndTalkBack': 'deferred_by_user',
            'conditions': json.loads((directory / 'profile-bench/device-conditions.json').read_text())}


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2] / 'validation/reports/final'
    result = summarize(root)
    (root / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'cold': result['cold']['count'], 'warm': result['warm']['count'],
                      'durationAttempts': [{k: a[k] for k in ['status', 'segmentsStarted', 'lastObservedSeconds']}
                                           for a in result['durationAttempts']]}))
