[CmdletBinding()]
param(
    [string]$AdbPath = 'adb',
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$ExpectedTextId,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$ExpectedPassageId,
    [string]$ReportDirectory = (Join-Path $PSScriptRoot '../reports/us4')
)
$ErrorActionPreference = 'Stop'
# Run once for each of five distinct passages already heard on the phone.
# Never uninstall, clear app data or modify the database. Python preserves binary
# stdout from adb; PowerShell redirection must not transcode the SQLite bytes.
$probe = @'
import subprocess,sqlite3,json,time,re,sys
adb,expected_text,expected_passage=sys.argv[1:4]
def shell(*args):
    return subprocess.check_output([adb,'-d','shell',*args],timeout=20).decode(errors='replace')
def positions():
    raw=subprocess.check_output([adb,'-d','exec-out','run-as','com.ureader.prototype','cat','files/ureader-prototype/prototype.sqlite'],timeout=20)
    db=sqlite3.connect(':memory:');db.deserialize(raw)
    result=[dict(zip(['textId','mode','version','passageId','offset','revision'],r)) for r in db.execute('SELECT text_id,mode,corpus_version,passage_id,offset_utf16,revision FROM positions ORDER BY text_id,mode')]
    db.close();return result
before=positions()
assert any(r['textId']==expected_text and r['mode']=='audio' and r['passageId']==expected_passage for r in before),'Expected passage has not been durably played'
shell('am','force-stop','com.ureader.prototype')
stopped=positions()
shell('am','start','-n','com.ureader.prototype/.MainActivity')
shell('rm','-f','/data/local/tmp/ureader-resume-ui.xml')
ready=False
for _ in range(15):
    time.sleep(1)
    windows=shell('dumpsys','window')
    if 'mDreamingLockscreen=true' in windows:raise RuntimeError('Unlock the phone; a hidden launch is not proof of resume')
    try:
        shell('uiautomator','dump','/data/local/tmp/ureader-resume-ui.xml')
        xml=shell('cat','/data/local/tmp/ureader-resume-ui.xml')
    except subprocess.CalledProcessError:
        continue # Cold start may not expose an accessibility root yet.
    if 'com.ureader.prototype' in xml and ('Lire le paragraphe' in xml or 'couter ici' in xml):
        ready=True;break
assert ready,'Reader did not restore a text visibly'
after=positions();assert before==stopped==after,'Opening the app changed a durable position'
lines=shell('dumpsys','media_session').splitlines()
for i,line in enumerate(lines):
    if line.strip()=='package=com.ureader.prototype':
        block='\n'.join(lines[i:i+18]);assert 'active=true' not in block,'Unexpected active audio session'
assert 'isForeground=true' not in shell('dumpsys','activity','services','com.ureader.prototype'),'Unexpected foreground playback'
print(json.dumps({'status':'passed','textId':expected_text,'passageId':expected_passage,'positionsUnchanged':True,'readerVisible':True,'noAutoplay':True,'positions':after,'scope':'one_real_process_restart; repeat for five distinct heard passages'}))
'@
$result = & python -c $probe $AdbPath $ExpectedTextId $ExpectedPassageId
if ($LASTEXITCODE -ne 0) { throw 'Resume check failed; no pass report written.' }
$parsed = $result | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$reportPath = Join-Path $ReportDirectory ('resume-' + [guid]::NewGuid().ToString('N') + '.json')
$parsed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Output $reportPath
