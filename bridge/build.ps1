$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$platform = Join-Path $sdk 'platforms\android-36\android.jar'
$tools = Join-Path $sdk 'build-tools\35.0.0'
$aapt = Join-Path $tools 'aapt.exe'
$d8 = Join-Path $tools 'd8.bat'
$zipalign = Join-Path $tools 'zipalign.exe'
$apksigner = Join-Path $tools 'apksigner.bat'
$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'

Remove-Item -LiteralPath 'classes', 'dex' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'classes.dex', 'unsigned.apk', 'aligned.apk' -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path 'classes', 'dex' | Out-Null

& javac -source 8 -target 8 -classpath $platform -d classes `
  src\com\ucnacdx2\mitvhomebridge\MainActivity.java
& $d8 --lib $platform --min-api 21 --output dex `
  classes\com\ucnacdx2\mitvhomebridge\MainActivity.class
Copy-Item -LiteralPath 'dex\classes.dex' -Destination 'classes.dex'

& $aapt package -f -M AndroidManifest.xml -S res -I $platform -F unsigned.apk
& $aapt add unsigned.apk classes.dex
& $zipalign -f 4 unsigned.apk aligned.apk
& $apksigner sign --ks $keystore --ks-key-alias androiddebugkey `
  --ks-pass pass:android --key-pass pass:android `
  --out MiTVHomeBridge.apk aligned.apk
& $apksigner verify --verbose --print-certs MiTVHomeBridge.apk

Get-FileHash MiTVHomeBridge.apk -Algorithm SHA256
