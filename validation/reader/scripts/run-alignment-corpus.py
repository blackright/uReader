"""Run the private silent Android corpus; restore the normal APK/settings in all cases."""
import argparse,hashlib,json,os,re,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
ADB=[str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe'),'-s','2291940c08037ece']
PACKAGE='com.ureader.prototype';ACTIVITY=PACKAGE+'/.reader.AlignmentCorpusLaboratoryActivity'
def command(*args,timeout=60):return subprocess.run(ADB+list(args),capture_output=True,check=True,timeout=timeout).stdout

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run-id',required=True);parser.add_argument('--cancel-on-inference',action='store_true');parser.add_argument('--attempt',default='02');args=parser.parse_args()
 if not re.fullmatch(r'[a-z0-9-]{1,16}',args.attempt):raise ValueError('Invalid attempt')
 if not re.fullmatch(r'corpus-[a-z0-9-]{1,48}',args.run_id):raise ValueError('Invalid run ID')
 local=ROOT/'validation/reader/private'/args.run_id
 preparation=json.loads((local/'preparation.json').read_text(encoding='utf-8'))
 if (local/'android-result.json').exists():raise ValueError('Fresh results required')
 test_apk=ROOT/'validation/reader/private/phase5-corpus-host-20261120.apk'
 normal_apk=ROOT/'validation/reader/private/phase5-foundations-v3.apk'
 if not test_apk.is_file() or not normal_apk.is_file():raise ValueError('APK missing')
 original=command('shell','settings','get','global','stay_on_while_plugged_in').decode().strip()
 (local/('original-screen-setting-'+args.attempt+'.json')).write_text(json.dumps({'value':original}),encoding='utf-8')
 remote='files/ureader-alignment-corpus/'+args.run_id
 report={'runId':args.run_id,'g1':'not_evaluated','audioPlaybackRequested':False};started=time.monotonic();restored=False
 def read(name):
  result=subprocess.run(ADB+['exec-out','run-as',PACKAGE,'cat',remote+'/'+name],capture_output=True,timeout=30)
  if result.returncode or not result.stdout.strip() or result.stdout.lstrip().startswith(b'cat:'):return None
  return json.loads(result.stdout)
 def fetch(relative,expected):
  if not re.fullmatch(r'[a-f0-9]{64}/(?:generation-[a-f0-9-]+\.wav|attention\.json)',relative):raise ValueError('Unsafe laboratory artifact')
  data=command('exec-out','run-as',PACKAGE,'cat',remote+'/'+relative)
  if len(data)>1048576 or hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Artifact integrity failure')
  path=local/relative;path.parent.mkdir(exist_ok=True)
  with path.open('xb') as file:file.write(data)
 try:
  command('shell','settings','put','global','stay_on_while_plugged_in','3')
  command('install','-r',str(test_apk),timeout=180)
  command('shell','am','force-stop',PACKAGE)
  command('shell','am','start','-n',ACTIVITY,'--es','runId',args.run_id,'--es','inputSha256',preparation['inputSha256'])
  previous=None;sent=False
  while time.monotonic()-started<1800:
   progress=read('progress.json')
   if progress is not None and progress!=previous:
    previous=progress;print(json.dumps(progress),flush=True)
   if args.cancel_on_inference and not sent and progress and progress.get('stage')=='inference':
    command('shell','am','start','-f','0x20000000','-n',ACTIVITY,'--ez','cancel','true');sent=True
   result=read('result.json') or read('failure.json')
   if result is not None:
    if result.get('inputSha256')!=preparation['inputSha256']:raise ValueError('Stale result')
    (local/'android-result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    if result['status']=='complete':
     for item in result['results']:
      for run in item['runs']:fetch(run['wav'],run['wavSha256'])
      fetch(item['attentionFile'],item['attentionSha256'])
    report.update({'androidStatus':result['status'],'uniqueCompleted':len(result['results']),'occurrences':result.get('occurrences'),
      'allPcmBytesIdentical':result.get('allPcmBytesIdentical'),'cancelCommandSent':sent,'cooperativeCancelLatencyMs':result.get('cooperativeCancelLatencyMs')})
    break
   time.sleep(2)
  else:raise TimeoutError('Corpus budget exceeded')
 except Exception as error:
  report.update(status='failed',reason=type(error).__name__)
 finally:
  try:
   command('shell','am','force-stop',PACKAGE)
   command('install','-r',str(normal_apk),timeout=180);restored=True
   if original=='null':command('shell','settings','delete','global','stay_on_while_plugged_in')
   else:command('shell','settings','put','global','stay_on_while_plugged_in',original)
   command('shell','am','start','-n',PACKAGE+'/.MainActivity')
  except Exception as error:report['restorationFailure']=type(error).__name__
  report.update(normalApkRestored=restored,elapsedSeconds=time.monotonic()-started)
  (ROOT/'validation/reader/reports'/('phase5-'+args.run_id+'-'+args.attempt+'.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
  print(json.dumps(report),flush=True)
 if not restored or report.get('status')=='failed' or report.get('androidStatus')!=('cancelled' if args.cancel_on_inference else 'complete'):raise SystemExit(1)
if __name__=='__main__':main()
