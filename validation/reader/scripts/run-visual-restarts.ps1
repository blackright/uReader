param(
  [Parameter(Mandatory=$true)][ValidateRange(0,7)][int]$OriginalStayAwake,
  [ValidateRange(0,5)][int]$StartStep = 0
)
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
$serial = '2291940c08037ece'
$package = 'com.ureader.prototype'
$dartPath = 'C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe'
$flutterTools = 'C:/dev/flutter/bin/cache/flutter_tools.snapshot'
$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$reportRoot = Join-Path $workspaceRoot 'validation/reader/reports/visual-restarts-20261119'
$gateApk = Join-Path $workspaceRoot 'validation/reader/private/immersive-resume-gate.apk'
$normalApk = Join-Path $workspaceRoot 'validation/reader/private/immersive-reader-normal-v3.apk'
if ((Test-Path -LiteralPath $reportRoot) -and $StartStep -eq 0) { throw 'Campaign report already exists; evidence will not be overwritten.' }
if (!(Test-Path -LiteralPath $reportRoot) -and $StartStep -ne 0) { throw 'Cannot resume missing campaign.' }
if (!(Test-Path -LiteralPath $gateApk) -or !(Test-Path -LiteralPath $normalApk)) { throw 'Required APK missing.' }
if (!(Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Path $reportRoot | Out-Null }
$forwardedPort = $null
$processIds = [System.Collections.Generic.HashSet[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()
if ($StartStep -gt 0) {
  $prior = @(Get-Content -LiteralPath (Join-Path $reportRoot 'progress.json') -Raw | ConvertFrom-Json)
  if ($prior.Count -ne $StartStep) { throw 'Resume step does not match validated evidence.' }
  foreach ($row in $prior) {
    $results.Add($row)
    $null = $processIds.Add([string]$row.pid)
  }
}
Push-Location $workspaceRoot
try {
  & $adbPath -s $serial shell settings put global stay_on_while_plugged_in 3
  if ($LASTEXITCODE -ne 0) { throw 'Cannot set temporary screen setting.' }
  & $adbPath -s $serial install -r $gateApk
  if ($LASTEXITCODE -ne 0) { throw 'Resume test APK installation failed.' }
  for ($step = $StartStep; $step -le 5; $step++) {
    & $adbPath -s $serial shell am force-stop $package
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stop test app.' }
    & $adbPath -s $serial shell am start -n "$package/.MainActivity" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot start test app.' }
    $devicePid = ''
    $serviceMatch = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
      $devicePid = (@(& $adbPath -s $serial shell pidof $package) -join '').Trim()
      if ($devicePid -match '^\d+$') {
        $engineLog = & $adbPath -s $serial logcat -d "--pid=$devicePid" -s flutter
        $serviceMatch = [regex]::Match(($engineLog -join "`n"), 'http://127\.0\.0\.1:(\d+)/([^\s]+)')
        if ($serviceMatch.Success) { break }
      }
      Start-Sleep -Milliseconds 400
    } while ([DateTime]::UtcNow -lt $deadline)
    if (!$serviceMatch -or !$serviceMatch.Success) { throw "VM service unavailable at step $step." }
    if (!$processIds.Add($devicePid)) { throw 'Android PID reused during campaign; new-process proof unavailable.' }
    $devicePort = $serviceMatch.Groups[1].Value
    $tokenPath = $serviceMatch.Groups[2].Value
    $forwardedPort = (@(& $adbPath -s $serial forward tcp:0 "tcp:$devicePort") -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $forwardedPort -notmatch '^\d+$') { throw 'Cannot forward VM service.' }
    $serviceUri = "http://127.0.0.1:${forwardedPort}/$tokenPath"
    $stepLog = Join-Path $reportRoot "step-$step.log"
    if (Test-Path -LiteralPath $stepLog) { throw "Step $step log already exists; preserve it." }
    & $dartPath $flutterTools drive --no-pub -d $serial --driver=test_driver/integration_test.dart "--use-existing-app=$serviceUri" --keep-app-running *> $stepLog
    $driverExit = $LASTEXITCODE
    & $adbPath -s $serial forward --remove "tcp:$forwardedPort"
    $forwardedPort = $null
    if ($driverExit -ne 0 -or !(Select-String -LiteralPath $stepLog -Pattern '^All tests passed\.$')) { throw "Driver failed at step $step; inspect its log." }
    $responsePath = Join-Path $workspaceRoot 'build/integration_response_data.json'
    $response = Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json
    if ($response.resume.restoresValidated -ne $step -or [string]$response.resume.pid -ne $devicePid -or $response.resume.paged -ne $true) { throw 'Fresh response does not match step/PID/paged reader.' }
    Copy-Item -LiteralPath $responsePath -Destination (Join-Path $reportRoot "step-$step.json")
    $results.Add([pscustomobject]@{step=$step;pid=$devicePid;restoresValidated=$response.resume.restoresValidated;passed=$true})
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportRoot 'progress.json') -Encoding utf8
    Write-Output "Step $step passed; PID $devicePid; restores validated: $step"
  }
}
catch {
  Write-Output ('Campaign error: ' + $_.Exception.Message)
  Write-Output $_.ScriptStackTrace
  throw
}
finally {
  if ($forwardedPort) { & $adbPath -s $serial forward --remove "tcp:$forwardedPort" }
  & $adbPath -s $serial shell am force-stop $package
  & $adbPath -s $serial install -r $normalApk
  $restoreExit = $LASTEXITCODE
  if ($restoreExit -eq 0) { & $adbPath -s $serial shell am start -n "$package/.MainActivity" }
  & $adbPath -s $serial shell settings put global stay_on_while_plugged_in $OriginalStayAwake
  Pop-Location
  if ($restoreExit -ne 0) { throw 'Normal APK restoration failed; do not claim restored.' }
}
