# MiTV Optimizer v0.3.0

## Changes

- Integrates persistent wireless ADB into the module on TCP port `5555`.
- Waits for the Android Settings service before enabling `Global.adb_enabled`.
- Sets `sys.set_adb_disabled=1` and keeps a 30-second recovery check for firmware that resets `adbd`.
- Adds ADB status to the module action output and stops the watchdog during uninstall.
- Removes duplicate APK copies from the release ZIP; APKs remain under `system/`, while `artifacts/` contains manifests.

## Validation

- Tested on `finch` / Android 14 / `OS3.0.115.0.UFFMATV`.
- After reboot, `192.168.10.100:5555` reports `device`.
- `adb_enabled=1`, `persist.adb.tcp.port=5555`, and `service.adb.tcp.port=5555`.
