param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$BridgeApk = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\mitv-home-bridge.apk'),
    [string]$DangbeiApk,
    [string]$Aapt,
    [string]$ApkSigner,
    [switch]$Poc
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $env:TEMP ('mitv-optimizer-' + [guid]::NewGuid().ToString('N'))
$zipName = if ($Poc) { 'mitv-optimizer-poc.zip' } else { 'mitv-optimizer-v0.3.1.zip' }
$zip = Join-Path $OutputDirectory $zipName

if ([string]::IsNullOrWhiteSpace($Aapt)) {
    if ($env:ANDROID_BUILD_TOOLS) {
        $candidate = Join-Path $env:ANDROID_BUILD_TOOLS 'aapt.exe'
        if (Test-Path -LiteralPath $candidate) { $Aapt = $candidate }
    }
    if ([string]::IsNullOrWhiteSpace($Aapt)) {
        $command = Get-Command aapt.exe -ErrorAction SilentlyContinue
        if ($command) { $Aapt = $command.Source }
    }
}
if ([string]::IsNullOrWhiteSpace($ApkSigner)) {
    if ($env:ANDROID_BUILD_TOOLS) {
        $candidate = Join-Path $env:ANDROID_BUILD_TOOLS 'apksigner.bat'
        if (Test-Path -LiteralPath $candidate) { $ApkSigner = $candidate }
    }
    if ([string]::IsNullOrWhiteSpace($ApkSigner)) {
        $command = Get-Command apksigner.bat -ErrorAction SilentlyContinue
        if ($command) { $ApkSigner = $command.Source }
    }
}
$hasMetadataTools = (-not [string]::IsNullOrWhiteSpace($Aapt)) -and (-not [string]::IsNullOrWhiteSpace($ApkSigner)) -and (Test-Path -LiteralPath $Aapt) -and (Test-Path -LiteralPath $ApkSigner)

New-Item -ItemType Directory -Force -Path $stage, $OutputDirectory | Out-Null
try {
    # Only stage files that belong in a Magisk module. The repository also
    # contains PoC captures, decompiler output, and recovery installer files;
    # copying the whole tree makes an invalid/oversized module ZIP.
    $moduleFiles = @(
        'module.prop', 'customize.sh', 'service.sh', 'action.sh',
        'uninstall.sh', 'options.conf', 'components-ad.txt', 'system.prop'
    )
    foreach ($name in $moduleFiles) {
        $source = Join-Path $projectRoot $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) -Force
        }
    }
    if ($Poc) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'poc\customize-poc.sh') `
            -Destination (Join-Path $stage 'customize.sh') -Force
    }
    foreach ($directory in @('system')) {
        if ($Poc) { continue }
        $source = Join-Path $projectRoot $directory
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $stage $directory) -Recurse -Force
        }
    }

    # These scripts run under the device's busybox/mksh, where a CR before the
    # newline makes `case ... in` and `for ... do` unparseable and silently
    # kills the whole service. A Windows checkout with core.autocrlf=true would
    # otherwise ship exactly that, so normalize what actually gets zipped.
    $textExtensions = @('.sh', '.prop', '.conf', '.txt')
    Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
        ($textExtensions -contains $_.Extension.ToLowerInvariant()) -or ($_.Name -eq 'hosts')
    } | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n").Replace("`r", "`n")
        [System.IO.File]::WriteAllText($_.FullName, $text)
    }

    $artifactInputs = if ($Poc) { @() } else { @(
        @{ Name = 'mitv-home-bridge.apk'; Path = $BridgeApk },
        @{ Name = 'com.dangbei1.tvlauncherx.apk'; Path = $DangbeiApk }
    ) }
    $artifactDir = Join-Path $stage 'artifacts'
    New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
    $manifestLines = New-Object System.Collections.Generic.List[string]
    $metadataLines = New-Object System.Collections.Generic.List[string]
    foreach ($artifact in $artifactInputs) {
        if ([string]::IsNullOrWhiteSpace($artifact.Path) -or -not (Test-Path -LiteralPath $artifact.Path)) {
            throw "Missing required APK input: $($artifact.Name). Pass -$($artifact.Name -replace '\.apk$','') or provide the file."
        }
        # The APK is already included under system/. Keep only manifests here
        # so each release does not ship both a system APK and a duplicate copy.
        $sourcePath = $artifact.Path
        $hash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $manifestLines.Add("$($artifact.Name)`t$hash")

        if ($hasMetadataTools) {
            $badging = @(& $Aapt dump badging $sourcePath 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "aapt metadata validation failed: $($artifact.Name)" }
            $packageLine = $badging | Where-Object { $_ -match "^package: name='([^']+)' versionCode='([^']*)' versionName='([^']*)'" } | Select-Object -First 1
            if (-not $packageLine -or $packageLine -notmatch "^package: name='([^']+)' versionCode='([^']*)' versionName='([^']*)'") {
                throw "Could not read package metadata: $($artifact.Name)"
            }
            $packageName = $Matches[1]
            $versionCode = $Matches[2]
            $versionName = $Matches[3]
        } else {
            $packageName = switch ($artifact.Name) {
                'mitv-home-bridge.apk' { 'com.ucnacdx2.mitvhomebridge' }
                'com.dangbei1.tvlauncherx.apk' { 'com.dangbei1.tvlauncherx' }
            }
            $versionCode = switch ($artifact.Name) {
                'mitv-home-bridge.apk' { '5' }
                'com.dangbei1.tvlauncherx.apk' { '83' }
            }
            $versionName = switch ($artifact.Name) {
                'mitv-home-bridge.apk' { '0.3.2' }
                'com.dangbei1.tvlauncherx.apk' { '3.3.6' }
            }
            Write-Warning "Android Build Tools unavailable; using pinned metadata for $($artifact.Name)."
        }
        $expectedPackage = switch ($artifact.Name) {
            'mitv-home-bridge.apk' { 'com.ucnacdx2.mitvhomebridge' }
            'com.dangbei1.tvlauncherx.apk' { 'com.dangbei1.tvlauncherx' }
        }
        if ($packageName -ne $expectedPackage) {
            throw "$($artifact.Name) has package $packageName; expected $expectedPackage"
        }

        if ($hasMetadataTools) {
            $certOutput = @(& $ApkSigner verify --verbose --print-certs $sourcePath 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "APK signature validation failed: $($artifact.Name)`n$($certOutput -join "`n")" }
            $certificate = $certOutput | Where-Object { $_ -match 'certificate SHA-256 digest:' } | Select-Object -First 1
            if (-not $certificate -or $certificate -notmatch 'certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)') {
                throw "No signer certificate digest found: $($artifact.Name)"
            }
            $signerSha256 = ($Matches[1] -replace ':','').ToLowerInvariant()
        } else {
            $signerSha256 = switch ($artifact.Name) {
                'mitv-home-bridge.apk' { '40e41572eef92a86eed5b9afffd4ccd4a7e6e86de34c3b6d2fa614f60cbe7d8c' }
                'com.dangbei1.tvlauncherx.apk' { '40e41572eef92a86eed5b9afffd4ccd4a7e6e86de34c3b6d2fa614f60cbe7d8c' }
            }
        }
        $Matches = @{}
        $metadataLines.Add("$($artifact.Name)`tpackage=$packageName`tversionCode=$versionCode`tversionName=$versionName`tsignerSha256=$signerSha256`tsha256=$hash")
    }
    $manifestLines | Set-Content -LiteralPath (Join-Path $artifactDir 'SHA256SUMS') -Encoding ascii
    $metadataLines | Set-Content -LiteralPath (Join-Path $artifactDir 'ARTIFACT-METADATA.tsv') -Encoding ascii

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
