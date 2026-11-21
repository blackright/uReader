param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,40}$')]
    [string]$RunId = '01',
    [ValidateSet('fr-01-p1', 'fr-04-p1', 'fr-05-p1')]
    [string]$PassageId = 'fr-01-p1',
    [switch]$ReproducedBundle
)

$ErrorActionPreference = 'Stop'
$prototypeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$referencePython = Join-Path $prototypeRoot 'validation/private/reference-venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $referencePython)) {
    throw 'Environnement de référence absent. Suivre validation/reference-officielle.md ; aucun téléchargement automatique.'
}

Push-Location $prototypeRoot
try {
    $candidateArguments = if ($ReproducedBundle) {
        @('--onnx-directory', 'validation/private/repro-bundle-01',
          '--audit-lock', 'validation/private/repro-bundle-01/audit-lock.json')
    } else { @('--onnx-directory', 'validation/private/models/fr-6l') }
    & $referencePython -B validation/scripts/official-reference.py `
        --directory validation/private/reference-fr `
        @candidateArguments --passage-id $PassageId `
        --wav "validation/reference-audio/fr-official-reference-$RunId.wav" `
        --report "validation/reports/g0/official-reference-$RunId.json"
    if ($LASTEXITCODE -ne 0) {
        throw 'La référence officielle a échoué ; aucune conclusion positive ni activation.'
    }
} finally {
    Pop-Location
}
