param([ValidatePattern('^[a-z0-9-]+$')][string]$Attempt = '02')
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
$serial = '2291940c08037ece'
$package = 'com.ureader.prototype'
$normalApk = (Resolve-Path 'validation/reader/private/phase5-foundations-v3.apk').Path
$testApk = (Resolve-Path 'build/app/outputs/flutter-apk/app-debug.apk').Path
$reportPath = "validation/reader/reports/phase5-smoke-20261120-$Attempt.json"
if (Test-Path -LiteralPath $reportPath) { throw 'Fresh smoke report required.' }
$backupPath='validation/reader/private/alignment-smoke-stay-20261120.json'
$originalStay = if (Test-Path -LiteralPath $backupPath) { (Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json).value } else { (@(& $adbPath -s $serial shell settings get global stay_on_while_plugged_in) -join '').Trim() }
$forwardedPort = $null
$passed = $false
$restored = $false
$failure = $null
try {
  & $adbPath -s $serial shell settings put global stay_on_while_plugged_in 3
  & $adbPath -s $serial install -r $testApk *> "validation/reader/private/alignment-smoke-install-$Attempt.log"
  if ($LASTEXITCODE -ne 0) { throw 'Smoke APK installation failed.' }
  & $adbPath -s $serial shell am force-stop $package
  & $adbPath -s $serial shell am start -n "$package/.MainActivity" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Smoke launch failed.' }
  $deadline = [DateTime]::UtcNow.AddSeconds(45)
  $serviceMatch = $null
  do {
    $appProcessId = (@(& $adbPath -s $serial shell pidof $package) -join '').Trim()
    if ($appProcessId -match '^\d+$') {
      $engineLog = & $adbPath -s $serial logcat -d "--pid=$appProcessId" -s flutter
      $serviceMatch = [regex]::Match(($engineLog -join "`n"), 'http://127\.0\.0\.1:(\d+)/([^\s]+)')
      if ($serviceMatch.Success) { break }
    }
    Start-Sleep -Milliseconds 400
  } while ([DateTime]::UtcNow -lt $deadline)
  if (!$serviceMatch -or !$serviceMatch.Success) { throw 'VM service unavailable; no success inferred.' }
  $devicePort = $serviceMatch.Groups[1].Value
  $forwardedPort = (@(& $adbPath -s $serial forward tcp:0 "tcp:$devicePort") -join '').Trim()
  if ($LASTEXITCODE -ne 0 -or $forwardedPort -notmatch '^\d+$') { throw 'VM forwarding failed.' }
  $serviceUri = "http://127.0.0.1:${forwardedPort}/$($serviceMatch.Groups[2].Value)"
  & C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe C:/dev/flutter/bin/cache/flutter_tools.snapshot drive --no-pub -d $serial --driver=test_driver/integration_test.dart "--use-existing-app=$serviceUri" --keep-app-running *> "validation/reader/private/alignment-smoke-driver-$Attempt.log"
  if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "validation/reader/private/alignment-smoke-driver-$Attempt.log" -Pattern '^All tests passed\.$')) { throw 'Smoke driver failed.' }
  $passed = $true
} catch {
  $failure = $_.Exception.Message
} finally {
  if ($forwardedPort) { & $adbPath -s $serial forward --remove "tcp:$forwardedPort" }
  & $adbPath -s $serial shell am force-stop $package
  & $adbPath -s $serial install -r $normalApk *> "validation/reader/reports/phase5-smoke-normal-restored-20261120-$Attempt.log"
  $restored = $LASTEXITCODE -eq 0
  if ($originalStay -eq 'null') { & $adbPath -s $serial shell settings delete global stay_on_while_plugged_in | Out-Null }
  else { & $adbPath -s $serial shell settings put global stay_on_while_plugged_in $originalStay }
  if ($restored) { & $adbPath -s $serial shell am start -n "$package/.MainActivity" | Out-Null }
  [pscustomobject]@{passed=$passed;normalApkRestored=$restored;audioPlaybackRequested=$false;g1='not_evaluated';failure=$failure} | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding utf8
}
if (!$passed -or !$restored) { throw 'Smoke or restoration failed; inspect report.' }
