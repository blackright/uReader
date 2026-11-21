"""Collect only generated CC0 validation audio, not user books/audio."""
from pathlib import Path
import json
import os
import re
import subprocess
import wave
import argparse

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--progress', action='store_true')
args = parser.parse_args()
report_name = 'us3-audio-progress.json' if args.progress else 'us3-audio-device.json'
report = json.loads((root / 'validation/epub/reports' / report_name).read_text(encoding='utf-8'))
directory = report['audioDirectory']
if not re.fullmatch(r'files/us3-epub-audio-validation-\d+/evidence', directory):
    raise ValueError('Unexpected validation directory')
adb = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
dest = root / 'validation/epub/reference-audio/us3'
dest.mkdir(parents=True, exist_ok=True)
for capture in report['captures']:
    name = capture['filename']
    if not re.fullmatch(r'epub-0[1-9]-c\d+\.wav', name):
        raise ValueError('Unexpected evidence filename')
    data = subprocess.run([adb, '-d', 'exec-out', 'run-as', 'com.ureader.prototype',
        'cat', directory + '/' + name], check=True, capture_output=True).stdout
    (dest / name).write_bytes(data)
numbers = [int(book['book'].split('-')[1]) for book in report['books']]
if set(numbers) != {1, 2, 3, 4, 6, 7, 8, 9}:
    raise ValueError('Expected the eight French corpus books')
for number in numbers:
    parts = sorted(dest.glob(f'epub-{number:02}-c*.wav'))[:2]
    if len(parts) != 2:
        raise ValueError('Missing chapter evidence')
    output = dest.parent / f'us3-epub-{number:02}.wav'
    with wave.open(str(output), 'wb') as combined:
        for index, part in enumerate(parts):
            with wave.open(str(part), 'rb') as audio:
                if index == 0:
                    params = audio.getparams()
                    combined.setparams(params)
                elif audio.getparams()[:3] != params[:3]:
                    raise ValueError('Incompatible PCM formats')
                combined.writeframes(audio.readframes(audio.getnframes()))
    print(output)
