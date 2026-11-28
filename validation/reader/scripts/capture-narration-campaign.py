"""Run/resume registered Android batches, preserving one verified original APK."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan',required=True,type=Path)
    parser.add_argument('--run-prefix',required=True)
    args=parser.parse_args()
    spec=importlib.util.spec_from_file_location('campaign',Path(__file__).with_name('narration-campaign.py'))
    tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
    plan_path=tool.private_path(args.plan)
    if not re.fullmatch('french-quality-[a-z0-9-]{1,50}',args.run_prefix):raise ValueError('Run prefix')
    plan=json.loads(plan_path.read_text(encoding='utf-8'))
    rollback=plan_path.parent/'rollback/original.apk'
    captures=[]
    for i,batch in enumerate(plan['batches'],1):
        name=batch['file']
        if name!=f'batch-{i:02d}.json':raise ValueError('Batch sequence')
        source=tool.private_path(plan_path.parent/name)
        if hashlib.sha256(source.read_bytes()).hexdigest()!=batch['sha256']:raise ValueError('Changed batch')
        run=f'{args.run_prefix}-b{i:02d}'
        output=tool.PRIVATE/run
        if not output.exists():
            subprocess.run([sys.executable,str(Path(__file__).with_name('capture-french-quality.py')),
                            '--cases',str(source),'--run-id',run,'--rollback-apk',str(rollback)],check=True,cwd=ROOT)
        native=tool.verify_capture(output,batch['sha256'])
        expected=json.loads(source.read_text(encoding='utf-8'))['cases']
        if [r['id'] for r in native['cases']]!=[r['id'] for r in expected]:raise ValueError('Case order')
        captures.append({'batch':name,'directory':output.relative_to(ROOT).as_posix(),'cases':len(native['cases'])})
        print('Verified batch '+str(i),flush=True)
    target=plan_path.parent/'android-captures.json'
    payload=json.dumps({'corpusSha256':plan['corpusSha256'],'captures':captures,'rollback':rollback.relative_to(ROOT).as_posix()},indent=2)+'\n'
    if target.exists() and target.read_text(encoding='utf-8')!=payload:raise ValueError('Existing campaign capture index differs')
    if not target.exists():target.write_text(payload,encoding='utf-8')


if __name__=='__main__':main()
