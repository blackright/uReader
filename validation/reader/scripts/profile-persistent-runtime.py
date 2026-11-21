"""Silent cold/warm profiling with an archived original APK and unconditional restoration."""
import argparse,hashlib,json,os,re,shutil,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];PACKAGE='com.ureader.prototype'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run-id',required=True);p.add_argument('--throughput',action='store_true');p.add_argument('--sustained',action='store_true');args=p.parse_args()
 if args.sustained:args.throughput=True
 if not re.fullmatch(r'[a-z0-9-]{1,50}',args.run_id):raise ValueError('Run ID')
 private=ROOT/'validation/reader/private'/args.run_id;private.mkdir(exist_ok=False)
 adb=str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe')
 devices=subprocess.check_output([adb,'devices'],text=True).splitlines()
 ids=[line.split()[0] for line in devices if line.endswith('\tdevice')]
 if len(ids)!=1:raise ValueError('Exactly one authorized device is required')
 base=[adb,'-s',ids[0]]
 def command(*words,timeout=180):return subprocess.check_output(base+list(words),stderr=subprocess.STDOUT,timeout=timeout)
 def apk_path():
  value=command('shell','pm','path',PACKAGE).decode().strip()
  if not value.startswith('package:/data/app/') or '\n' in value:raise ValueError('Unexpected installed APK')
  return value.removeprefix('package:')
 original=private/'original.apk';command('pull',apk_path(),str(original))
 original_sha=hashlib.file_digest(original.open('rb'),'sha256').hexdigest()
 app=private/'profiling.apk';test=private/'profiling-test.apk'
 shutil.copyfile(ROOT/'build/app/outputs/apk/debug/app-debug.apk',app)
 shutil.copyfile(ROOT/'build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk',test)
 before=set(command('exec-out','run-as',PACKAGE,'ls','files').decode().split())
 report={'runId':args.run_id,'audioPlaybackRequested':False,'g1':'not_evaluated','restored':False}
 try:
  print('Installing silent profiling build',flush=True)
  command('install','-r',str(app));command('install','-r','-t',str(test))
  output=command('shell','am','instrument','-w','-r','-e','sustained',str(args.sustained).lower(),'-e','class',
    ('com.ureader.prototype.speech.SpeechThroughputTest' if args.throughput else 'com.ureader.prototype.speech.PersistentSpeechRuntimeTest'),PACKAGE+'.test/androidx.test.runner.AndroidJUnitRunner',timeout=660)
  (private/'instrumentation.log').write_bytes(output)
  if not re.search(rb'OK \(1 test\)',output):raise ValueError('Instrumentation did not pass')
  after=set(command('exec-out','run-as',PACKAGE,'ls','files').decode().split())
  names=[name for name in after-before if re.fullmatch((r'throughput-report-\d+\.json' if args.throughput else r'persistent-runtime-report-\d+\.json'),name)]
  if len(names)!=1:raise ValueError('Fresh runtime report required')
  data=command('exec-out','run-as',PACKAGE,'cat','files/'+names[0])
  if len(data)>65536:raise ValueError('Report budget')
  native=json.loads(data);(private/'native.json').write_bytes(data)
  if args.throughput:
   report.update(status='passed',native=native)
   print(json.dumps({'status':'measured','configurations':[{k:c.get(k) for k in ('configuration','status','warmRtf','pcmIdenticalToBaseline')} for c in native['configurations']]}),flush=True)
  else:
   warm=native['runs'][1:];ratio=sum(r['totalMs'] for r in warm)/sum(r['audioMs'] for r in warm)
   report.update(status='passed',native=native,warmRtf=ratio,chapterPreparationRequired=ratio>=1)
   print(json.dumps({'status':'profiled','warmRtf':round(ratio,3),'initializations':native['initializations']}),flush=True)
 except Exception as error:
  report.update(status='failed',reason=type(error).__name__)
  print(json.dumps({'status':'failed','reason':type(error).__name__}),flush=True)
 finally:
  try:
   command('shell','am','force-stop',PACKAGE);command('install','-r',str(original))
   installed=command('shell','sha256sum',apk_path()).decode().split()[0]
   report['restored']=installed==original_sha
   if report['restored']:command('shell','am','start','-n',PACKAGE+'/.MainActivity')
  except Exception as error:report['restorationFailure']=type(error).__name__
  (ROOT/'validation/reader/reports'/f'{args.run_id}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 if report.get('status')!='passed' or not report['restored']:raise SystemExit(1)
if __name__=='__main__':main()
