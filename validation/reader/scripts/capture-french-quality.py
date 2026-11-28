"""Silent private Android capture. Preserve APK and restore normal app without clearing data."""
import hashlib,json,os,re,subprocess
from contextlib import contextmanager
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
PACKAGE='com.ureader.prototype'

def valid_frontend_path(relative):
    return (bool(re.fullmatch(r'[A-Za-z0-9_+./!() \-]+',relative))
            and not relative.startswith('/') and all(p not in ('','..','.') for p in relative.split('/')))

def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases',required=True,type=Path)
    parser.add_argument('--run-id',required=True)
    parser.add_argument('--rollback-apk',type=Path,help='Shared private backup; must match the installed app before every batch')
    parser.add_argument('--kokoro-model-dir',type=Path,help='Isolated ONNX inference probe; not a product voice activation')
    parser.add_argument('--kokoro-installed-bundle-dir',type=Path,help='Isolated fixture of the real trusted bundle resolver; never the product database')
    parser.add_argument('--kokoro-frontend-dir',type=Path,help='Verified installed espeak-ng-data for isolated parity testing')
    args=parser.parse_args()
    if args.kokoro_installed_bundle_dir:
        if args.kokoro_model_dir:raise ValueError('Choose one Kokoro probe mode')
        args.kokoro_model_dir=args.kokoro_installed_bundle_dir
    if not re.fullmatch(r'french-quality-[a-z0-9-]{1,60}',args.run_id):raise ValueError('Run ID')
    cases=args.cases.resolve()
    private=(ROOT/'validation/reader/private').resolve()
    if not cases.is_relative_to(private) or cases.stat().st_size>1048576:raise ValueError('Private bounded input required')
    corpus=json.loads(cases.read_text(encoding='utf-8'))
    if args.kokoro_model_dir:
        models=args.kokoro_model_dir.resolve()
        if not models.is_relative_to(private):raise ValueError('Private model directory required')
        pins=corpus['files']
        required={'kokoro.onnx','siwis.f32','vocab.json'}
        if args.kokoro_installed_bundle_dir:required|={'tokenizer.json','espeak-data.zip'}
        if {f['relativePath'] for f in pins}!=required or len(pins)!=len(required):raise ValueError('Probe model files')
        for entry in pins:
            model=models/entry['relativePath']
            if model.stat().st_size!=entry['byteSize'] or model.stat().st_size>512*1024*1024:raise ValueError('Probe model size')
            with model.open('rb') as stream:
                if hashlib.file_digest(stream,'sha256').hexdigest()!=entry['sha256']:raise ValueError('Probe model integrity')
    if args.kokoro_frontend_dir:
        frontend=args.kokoro_frontend_dir.resolve()
        if not args.kokoro_model_dir or not frontend.is_relative_to((ROOT/'validation/private').resolve()) or frontend.name!='espeak-ng-data':raise ValueError('Private frontend source required')
    ids=[row['id'] for row in corpus['cases']]
    if not 1<=len(ids)<=32 or len(set(ids))!=len(ids) or not all(re.fullmatch(r'[a-z-]+-[0-9]{1,2}',i) for i in ids):raise ValueError('Case IDs')
    app=ROOT/'build/app/outputs/apk/debug/app-debug.apk'
    test=ROOT/'build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
    if not app.is_file() or not test.is_file():raise ValueError('Build normal and instrumentation APKs first')
    output=private/args.run_id;output.mkdir(exist_ok=False)
    adb=str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe')
    devices=subprocess.check_output([adb,'devices'],text=True)
    serials=[line.split()[0] for line in devices.splitlines() if line.endswith('\tdevice')]
    if len(serials)!=1:raise ValueError('Exactly one authorized device required')
    base=[adb,'-s',serials[0]]
    def command(*words,timeout=180):return subprocess.check_output(base+list(words),stderr=subprocess.STDOUT,timeout=timeout)
    def installed():
        path=command('shell','pm','path',PACKAGE).decode().strip().removeprefix('package:')
        if not path.startswith('/data/app/') or '\n' in path:raise ValueError('Installed APK path')
        return path
    def sha(path):
        with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
    original=args.rollback_apk.resolve() if args.rollback_apk else output/'original.apk'
    if not original.is_relative_to(private):raise ValueError('Private rollback required')
    if original.exists():
        if command('shell','sha256sum',installed()).decode().split()[0]!=sha(original):raise ValueError('Rollback differs from installed app')
    else:
        original.parent.mkdir(parents=True,exist_ok=True)
        command('pull',installed(),str(original))
        if command('shell','sha256sum',installed()).decode().split()[0]!=sha(original):raise ValueError('Rollback backup hash')
    # Windows adb shell may canonicalize CRLF on stdin. Send explicit UTF-8/LF
    # JSON serialization and hash those exact bytes; text values remain escaped.
    payload=cases.read_bytes().replace(b'\r\n',b'\n')
    if json.loads(payload)!=corpus:raise ValueError('Transfer serialization changed case values')
    transferred=output/'transfer-cases.json';transferred.write_bytes(payload)
    report={'status':'failed','appRestored':False,'audioPlaybackRequested':False,'listening':'not_evaluated',
        'inputSha256':sha(transferred),'originalApkSha256':sha(original),'captureScriptSha256':sha(Path(__file__))}
    success=False
    remote='files/'+args.run_id
    @contextmanager
    def stage_binary(source,name):
        # Windows adb shell stdin stops at byte 0x1a; use adb's binary sync
        # protocol for ONNX and tar data, then copy into this isolated UID.
        if not re.fullmatch(r'[A-Za-z0-9_.-]+',name):raise ValueError('Staged filename')
        temporary='/data/local/tmp/ureader-'+args.run_id+'-'+name
        try:
            command('push',str(source),temporary,timeout=180)
            command('shell','chmod','0644',temporary)
            yield temporary
        finally:
            command('shell','rm','-f',temporary)
    try:
        report['stage']='installing_capture_apks'
        command('shell','am','force-stop',PACKAGE)
        # Shared-backup captures use the installed app unchanged. Reinstalling
        # it for every batch adds minutes and touches package state needlessly.
        if not args.rollback_apk or args.kokoro_model_dir:command('install','-r',str(app))
        test_path=command('shell','pm','path',PACKAGE+'.test').decode().strip().removeprefix('package:')
        test_matches=(test_path.startswith('/data/app/') and '\n' not in test_path and
            command('shell','sha256sum',test_path).decode().split()[0]==sha(test))
        if not test_matches:command('install','-r','-t',str(test))
        if args.kokoro_model_dir:
            report['stage']='native_contract_tests'
            prefix='com.ureader.prototype.speech.'
            selected=[prefix+'SpeechPluginTest#'+name for name in (
                'capabilitiesExposeTheLoadedVoiceInsteadOfEstelle', 'bundleCanBeReleasedAndLoadedAgain',
                'defaultBuildHasNoImplicitBundleAndRejectsInvalidMessages',
                'cancellationReturnsOriginalTokenWithoutLateCompletedEvent',
                'disposeWaitsForPendingLoadAndPreventsLateActivation')]
            selected += [prefix+'PocketSpeechEngineTest#'+name for name in (
                'cancelledLateOutputIsDeletedAndNextRequestRunsSerially',
                'disposeWaitsForInferenceAndIsIdempotent', 'backendFailureDoesNotPoisonWorker',
                'cleanupStillRunsWhenBackendCloseFails')]
            result=command('shell','am','instrument','-w','-r','-e','class',','.join(selected),
                PACKAGE+'.test/androidx.test.runner.AndroidJUnitRunner',timeout=180)
            (output/'native-contracts.log').write_bytes(result)
            if not re.search(rb'OK \(9 tests\)',result):raise ValueError('Native speech contracts failed')
            report['nativeContractTestsPassed']=9
        command('shell','run-as',PACKAGE,'mkdir',remote)
        report['stage']='transferring_cases'
        subprocess.run(base+['shell','-T','run-as',PACKAGE,'tee',remote+'/cases.json'],
            input=payload,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,check=True,timeout=30)
        if command('shell','run-as',PACKAGE,'sha256sum',remote+'/cases.json').decode().split()[0]!=sha(transferred):raise ValueError('Transfer hash')
        if args.kokoro_model_dir:
            for entry in pins:
                report['stage']='transferring_'+entry['relativePath']
                print('Transferring '+entry['relativePath'],flush=True)
                with stage_binary(models/entry['relativePath'],entry['relativePath']) as temporary:
                    command('shell','run-as',PACKAGE,'cp',temporary,remote+'/'+entry['relativePath'],timeout=180)
                if command('shell','run-as',PACKAGE,'sha256sum',remote+'/'+entry['relativePath']).decode().split()[0]!=entry['sha256']:raise ValueError('Probe transfer integrity')
        if args.kokoro_frontend_dir:
            report['stage']='transferring_frontend_data'
            import tarfile
            archive=output/'frontend.tar'
            inventory=[]
            uid=int(command('shell','run-as',PACKAGE,'id','-u').strip())
            gid=int(command('shell','run-as',PACKAGE,'id','-g').strip())
            with tarfile.open(archive,'w',format=tarfile.USTAR_FORMAT) as packed:
                for source in sorted(frontend.rglob('*')):
                    if source.is_symlink():raise ValueError('Frontend symlink rejected')
                    if not source.is_file():continue
                    relative=source.relative_to(frontend).as_posix()
                    if not valid_frontend_path(relative):raise ValueError('Frontend path rejected')
                    inventory.append({'path':relative,'byteSize':source.stat().st_size,'sha256':sha(source)})
                    if len(inventory)>2048 or sum(x['byteSize'] for x in inventory)>64*1024*1024:raise ValueError('Frontend data limit')
                    info=packed.gettarinfo(str(source),arcname='espeak-ng-data/'+relative)
                    info.uid=uid;info.gid=gid;info.uname='';info.gname='';info.mode=0o644;info.mtime=int(info.mtime)
                    with source.open('rb') as stream:packed.addfile(info,stream)
            (output/'frontend-inventory.json').write_text(json.dumps(inventory,indent=2)+'\n',encoding='utf-8')
            with stage_binary(archive,'frontend.tar') as temporary:
                command('shell','run-as',PACKAGE,'tar','xf',temporary,'-C',remote,timeout=180)
        print('Capturing native WAVs silently; product database is not opened by the test.',flush=True)
        report['stage']='instrumentation'
        capture_class=('KokoroBundleIntegrationTest' if args.kokoro_installed_bundle_dir else
                       'KokoroRuntimeCaptureTest' if args.kokoro_model_dir else 'FrenchQualityCaptureTest')
        result=command('shell','am','instrument','-w','-r','-e','class',
            'com.ureader.prototype.speech.'+capture_class,'-e','corpusDir',args.run_id,
            PACKAGE+'.test/androidx.test.runner.AndroidJUnitRunner',timeout=420)
        (output/'instrumentation.log').write_bytes(result)
        if args.kokoro_frontend_dir:
            parity=subprocess.run(base+['exec-out','run-as',PACKAGE,'cat',remote+'/frontend-parity.json'],capture_output=True,timeout=30)
            if parity.returncode==0:
                try:
                    parsed=json.loads(parity.stdout)
                    if not isinstance(parsed,dict) or 'differences' not in parsed:raise ValueError('Parity diagnostic shape')
                    (output/'frontend-parity.json').write_bytes(parity.stdout)
                except (ValueError,UnicodeDecodeError):
                    report['frontendParityDiagnostic']='unavailable'
        if not re.search(rb'OK \(1 test\)',result):raise ValueError('Native capture failed')
        raw=command('exec-out','run-as',PACKAGE,'cat',remote+'/native-report.json')
        native=json.loads(raw)
        if native['inputSha256']!=sha(transferred) or [c['id'] for c in native['cases']]!=ids:raise ValueError('Report mismatch')
        wavs=output/'native';wavs.mkdir()
        for row in native['cases']:
            if row['wav']!=row['id']+'.wav':raise ValueError('WAV path')
            data=command('exec-out','run-as',PACKAGE,'cat',remote+'/native/'+row['wav'],timeout=30)
            if len(data)>960044 or hashlib.sha256(data).hexdigest()!=row['sha256']:raise ValueError('WAV integrity')
            (wavs/row['wav']).write_bytes(data)
        (output/'native-report.json').write_bytes(raw)
        report.update(status='captured_listening_pending',segments=len(ids),nativeReport='native-report.json')
        success=True
    except Exception as error:
        report['failure']=type(error).__name__
        report['failureMessage']=str(error)[:1000]
        if isinstance(error,subprocess.CalledProcessError) and error.output:
            (output/'failure-command.log').write_bytes(error.output)
        print('Capture failed; original app will be restored.',flush=True)
    finally:
        restore=original if args.rollback_apk or not success else app
        try:
            command('shell','am','force-stop',PACKAGE)
            if command('shell','sha256sum',installed()).decode().split()[0]!=sha(restore):
                command('install','-r',str(restore))
            report['appRestored']=command('shell','sha256sum',installed()).decode().split()[0]==sha(restore)
            report['restoredApkSha256']=sha(restore)
            if report['appRestored']:command('shell','am','start','-n',PACKAGE+'/.MainActivity')
        except Exception as error:
            report['restorationFailure']=type(error).__name__
        finally:
            (output/'run-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))
    if not success or not report['appRestored']:raise SystemExit(1)

if __name__=='__main__':main()
