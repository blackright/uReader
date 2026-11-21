"""Validate a completed US1 device report and summarize observed measurements."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REPORTS = ROOT / 'validation/epub/reports'


def bounds(values):
    values = [v for v in values if v is not None]
    return {'min': min(values), 'max': max(values)} if values else None


def main():
    data = json.loads((REPORTS / 'us1-device.json').read_text(encoding='utf-8'))
    config = json.loads((ROOT / 'validation/epub/private/us1-device/config.json').read_text(encoding='utf-8'))
    assert data['status'] == 'passed', 'Device campaign has not passed'
    cases = data['cases']
    assert len(cases) == len(config['cases']) == 66
    assert {c['id'] for c in cases} == {c['id'] for c in config['cases']}
    assert all(c['status'] == 'passed' for c in cases)
    allowed_rejections = {'invalidArchive', 'unsafeContent', 'unsupportedContent', 'limitExceeded',
                          'unsupportedFormat', 'protectedContent',
                          'fixedLayoutUnsupported', 'invalidContent'}
    for case in cases:
        if case['policy'] == 'reject':
            assert case['error'] in allowed_rejections, case
        if case['id'] == 'negative-protected':
            assert case['error'] == 'protectedContent', case
        if case['id'] == 'negative-fixed':
            assert case['error'] == 'fixedLayoutUnsupported', case
        if case['policy'] == 'lost':
            assert case['error'] == 'sourceUnavailable', case
    for policy, count in [('ready', 10), ('existing', 10), ('edition', 2), ('cancel', 5), ('interrupt', 5), ('lost', 1)]:
        assert sum(c['policy'] == policy for c in cases) == count, policy
    assert data['httpClientCreationsInImportIsolate'] == 0
    host = json.loads((REPORTS / 'us1-host-measurements.json').read_text(encoding='utf-8'))
    measured = [c for c in cases if c['policy'] == 'ready']
    report = {
        'date': '2026-11-17', 'status': 'measured',
        'configuration': 'us1-device-configuration.json', 'deviceReport': 'us1-device.json',
        'testedBuild': 'us1-tested-build.json',
        'measurementSelection': 'Latest successful result for repeated controls; 66 unique scenarios across campaigns',
        'buildMode': 'debug', 'projectionVersion': 1,
        'validCorpusImportIncludingPickerAndRecoveryMs': bounds([c['elapsedMs'] for c in measured]),
        'validCorpusCopyThroughRecoveryMs': bounds([c.get('copyThroughRecoveryMs') for c in measured]),
        'copyCancellationThroughCleanupMs': bounds([c['cancellationMs'] for c in cases if c['policy'] == 'cancel']),
        'rssSamplesBytes': bounds([c['rssBefore'] for c in cases] + [c['rssAfter'] for c in cases]),
        'processLifetimeRssHighWaterBytes': bounds([c.get('VmHWM') for c in host]),
        'sampledAllocatedTestBookDirectoriesBytes': bounds([c['allocatedTestBooksBytes'] for c in host]),
        'validBookPrivateLogicalBytes': bounds([c['ownedLogicalBytes'] for c in measured]),
        'testDatabaseLogicalBytes': bounds([c.get('databaseLogicalBytes') for c in cases]),
        'importEventLoopTimerLagUs': bounds([c.get('maxImportEventLoopTimerLagUs') for c in cases]),
        'casesWithTimerSamples': sum(c.get('timerSamplesDuringImport', 0) > 0 for c in cases),
        'limitations': [
            'Debug build, synthetic corpus, Samsung/API29 only; no performance guarantee.',
            'Total elapsed time includes the automated picker and recovery; picker setup can dominate.',
            'Timer lag measures event-loop scheduling, not frame rate or TalkBack usability.',
            'Kernel RSS high-water includes startup; current RSS samples are not a peak measurement.',
            'Allocated book-directory samples exclude transient staging and SQLite; no total peak-disk claim.',
            'Repository fault injection and database reopen are not physical process kills.',
        ],
    }
    (REPORTS / 'us1-measurements.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'passed', 'cases': len(cases), 'measurements': 'us1-measurements.json'}))


if __name__ == '__main__':
    main()
