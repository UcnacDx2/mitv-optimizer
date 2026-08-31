param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $env:TEMP ('mitv-optimizer-' + [guid]::NewGuid().ToString('N'))
$zip = Join-Path $OutputDirectory 'mitv-optimizer-v0.1.0.zip'

New-Item -ItemType Directory -Force -Path $stage, $OutputDirectory | Out-Null
try {
    Get-ChildItem -LiteralPath $projectRoot -Force |
        Where-Object {
            $_.Name -notin @('.git', 'dist') -and
            $_.Extension -notin @('.db', '.sqlite', '.sqlite3')
        } |
        Copy-Item -Destination $stage -Recurse -Force

    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force
    }
    $entries = Get-ChildItem -LiteralPath $stage -Force | Select-Object -ExpandProperty Name
    & tar.exe -a -cf $zip -C $stage @entries
    if ($LASTEXITCODE -ne 0) {
        throw "tar.exe failed with exit code $LASTEXITCODE"
    }
    Get-FileHash -LiteralPath $zip -Algorithm SHA256
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
