"""Read corpus-test progress or collect verified segment WAVs and ordered content-only audio."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[2]
ADB = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'), '-d']


def read_remote(path):
    return subprocess.check_output(ADB + ['exec-out', 'run-as', 'com.ureader.prototype', 'cat', path], timeout=60)


def main(collect, run):
    if not re.fullmatch(r'\d{2}', run):
        raise ValueError('Expected two-digit run')
    names = subprocess.check_output(ADB + ['shell', 'run-as', 'com.ureader.prototype', 'ls', 'files'], timeout=20).decode().split()
    directories = sorted(n for n in names if re.fullmatch(r'ureader-corpus-validation-\d+', n))
    if not directories:
        print(json.dumps({'status': 'not_started'})); return
    remote = 'files/' + directories[-1] + '/'
    raw = read_remote(remote + 'report.json')
    if not raw.strip() or not raw.lstrip().startswith(b'{'):
        print(json.dumps({'status': 'initializing'})); return
    try:
        report = json.loads(raw)
    except json.JSONDecodeError:
        if collect:
            raise ValueError('Report incomplete; collect only after the test stops')
        print(json.dumps({'status': 'report_being_written'})); return
    if not collect:
        print(json.dumps({'status': report['status'], 'textsCompleted': len(report['cases']),
            'controlsCompleted': len(report['controls']), 'lastText': report['cases'][-1]['id'] if report['cases'] else None})); return
    target = ROOT / f'validation/private/corpus-listening-{run}'
    target.mkdir(exist_ok=False)
    audio = []
    for case in report['cases']:
        case_id = case['id']
        if not re.fullmatch(r'fr-(0[1-9]|10)', case_id):
            raise ValueError('Unsafe corpus ID')
        content = []
        for index, segment in enumerate(case['segments']):
            name = segment['file']
            if name != f'{case_id}-s{index:03}.wav':
                raise ValueError('Unexpected segment order/name')
            data = read_remote(remote + name)
            if len(data) != segment['byteSize'] or hashlib.sha256(data).hexdigest() != segment['sha256']:
                raise ValueError('Segment SHA or size mismatch')
            (target / name).write_bytes(data)
            with wave.open(io.BytesIO(data)) as wav:
                if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 24000):
                    raise ValueError('Unexpected segment PCM format')
                pcm = wav.readframes(wav.getnframes())
                if len(pcm) != wav.getnframes() * 2:
                    raise ValueError('Truncated PCM')
                content.append(pcm)
        output = ROOT / f'validation/reference-audio/recette-{case_id}-{run}.wav'
        with output.open('xb') as handle:
            with wave.open(handle, 'wb') as wav:
                wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000)
                for pcm in content:
                    wav.writeframes(pcm)
        entry = {'id': case_id, 'wav': output.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'samples': sum(len(p) // 2 for p in content), 'segmentCount': len(content),
            'scope': 'ordered_segment_content_only_not_real_time_gaps', 'humanAudition': 'pending'}
        audio.append(entry)
    report['remoteDirectory'] = directories[-1]
    report['collectedAudio'] = audio
    report['continuousMicrophoneRecording'] = False
    output = ROOT / f'validation/reports/us1/corpus-listening-{run}.json'
    with output.open('x', encoding='utf-8') as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2); handle.write('\n')
    print(json.dumps({'report': output.relative_to(ROOT).as_posix(), 'status': report['status'],
        'textsCollected': len(audio), 'controlsCompleted': len(report['controls'])}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect', action='store_true')
    parser.add_argument('--run', default='01')
    args = parser.parse_args()
    main(args.collect, args.run)
