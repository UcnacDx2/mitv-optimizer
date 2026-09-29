param(
    [string]$Adb = 'adb',
    [string]$Serial = '192.168.10.100:5555',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'diagnostics')
)

$ErrorActionPreference = 'Stop'
$device = @('-s', $Serial)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$paths = & $Adb @device shell pm path com.android.packageinstaller 2>$null
if (-not $paths) {
    $paths = & $Adb @device shell pm path com.google.android.packageinstaller 2>$null
}
if (-not $paths) { throw 'Could not identify the default package installer package' }

$apkLines = $paths | Where-Object { $_ -match '^package:' }
foreach ($line in $apkLines) {
    $remote = $line -replace '^package:', ''
    $name = Split-Path $remote -Leaf
    $local = Join-Path $OutputDirectory $name
    & $Adb @device pull $remote $local
    if ($LASTEXITCODE -ne 0) { throw "adb pull failed for $remote" }
}

& $Adb @device shell dumpsys package ($paths[0] -replace '^package:.*/', '') |
    Out-File (Join-Path $OutputDirectory 'installer-dumpsys.txt') -Encoding utf8
& $Adb @device shell pm list packages -f | Select-String -Pattern 'installer|package' |
    Out-File (Join-Path $OutputDirectory 'installer-package-inventory.txt') -Encoding utf8

Write-Host "APK/Dex inputs captured in $OutputDirectory. Use dexdump, jadx, or apktool for static analysis; do not disable components before identifying a low-risk candidate."
