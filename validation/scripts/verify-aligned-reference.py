"""Verify manually downloaded official-default 3.3.0 weights/voice; no activation or network."""
import importlib.util
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
lock = json.loads((root / 'validation/reference-3.3-aligned-lock.json').read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('verifier', Path(__file__).with_name('verify-model-files.py'))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
errors = verifier.verify(root / lock['directory'], lock['downloadFiles'])
if errors:
    print('Aligned reference files missing or invalid. No model loaded or activated.')
    for error in errors:
        print(error)
    sys.exit(1)
print('Two official-default files verified by size and SHA-256. No model loaded or activated.')
