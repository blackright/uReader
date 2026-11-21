"""Provision local reproduced bundle and existing public-text fixtures to a separate Android directory."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[2]
    directory = root / 'validation/private/repro-bundle-01'
    audit = json.loads((directory / 'audit-lock.json').read_text())
    spec = importlib.util.spec_from_file_location('verifier', Path(__file__).with_name('verify-model-files.py'))
    verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
    errors = verifier.verify(directory, audit['downloadFiles'])
    if errors: raise ValueError('; '.join(errors))
    local = root / 'validation/private/android-runtime/reexport-generation-files.json'
    files = [{**entry, 'name': Path(entry['relativePath']).name} for entry in audit['downloadFiles']]
    if len({e['name'] for e in files}) != 7: raise ValueError('Flat filename collision')
    local.write_text(json.dumps({'files': files, 'scope': 'Test-only native host metadata; not product trust'}, indent=2),encoding='utf-8')
    fixture = root / 'validation/private/android-runtime/generation-fixtures.json'
    command = [str(Path(os.environ['LOCALAPPDATA'])/'Android/SDK/platform-tools/adb.exe'), '-d']
    remote = 'files/ureader-reexport-generation/'
    subprocess.run(command+['shell','run-as','com.ureader.prototype','mkdir','-p',remote],check=True,timeout=15)
    for source in [*(directory/e['relativePath'] for e in files), local, fixture]:
        with source.open('rb') as stream:
            subprocess.run(command+['exec-in',"run-as com.ureader.prototype sh -c 'cat > "+remote+source.name+"'"],stdin=stream,check=True,timeout=90)
        actual=subprocess.check_output(command+['shell','run-as','com.ureader.prototype','sha256sum',remote+source.name],timeout=30).decode().split()[0]
        if actual!=hashlib.sha256(source.read_bytes()).hexdigest():raise ValueError('Private transfer integrity failed')
    print('Reproduced bundle and fixtures provisioned separately with SHA-256; application resolver unchanged.')


if __name__=='__main__': main()
