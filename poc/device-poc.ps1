param(
    [string]$Adb = 'adb',
    [string]$Serial = '192.168.10.100:5555',
    [switch]$Mutate,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'diagnostics')
)

$ErrorActionPreference = 'Stop'
$device = @('-s', $Serial)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Invoke-Adb([string[]]$Arguments) {
    & $Adb @device @Arguments
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $($Arguments -join ' ')" }
}

function Capture([string]$Name, [string[]]$Arguments) {
    $path = Join-Path $OutputDirectory $Name
    & $Adb @device @Arguments | Out-File -FilePath $path -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "capture failed: $($Arguments -join ' ')" }
}

Invoke-Adb @('wait-for-device')
Capture 'build-props.txt' @('shell', 'getprop')
Capture 'packages.txt' @('shell', 'pm', 'list', 'packages', '-f')
Capture 'home-resolution.txt' @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME')
Capture 'tvhome-dump.txt' @('shell', 'dumpsys', 'package', 'com.mitv.tvhome')
Capture 'fallback-dump.txt' @('shell', 'dumpsys', 'package', 'com.xiaomi.mitv.settings')
Capture 'upgrade-dump.txt' @('shell', 'dumpsys', 'package', 'com.xiaomi.mitv.upgrade')
Capture 'service-list.txt' @('shell', 'service', 'list')

if (-not $Mutate) {
    Write-Host 'Read-only inventory complete. Re-run with -Mutate only on the disposable test device.'
    exit 0
}

# Keep this script explicit and reversible. The Binder path is exercised by the
# bridge APK; shell commands below are only the root fallback control sample.
Invoke-Adb @('shell', 'su', '-c', 'pm enable --user 0 com.xiaomi.mitv.upgrade')
Invoke-Adb @('shell', 'su', '-c', 'pm enable --user 0 com.xiaomi.mitv.settings/com.xiaomi.mitv.settings.entry.FallbackHome')
Invoke-Adb @('shell', 'su', '-c', 'pm enable --user 0 com.mitv.tvhome/com.mitv.tvhome.MainActivityUserMode')
Capture 'baseline-after-restore.txt' @('shell', 'dumpsys', 'package', 'com.mitv.tvhome')

Write-Host 'Baseline restored. Install/run the bridge APK and capture logcat separately for Binder PoC results.'
