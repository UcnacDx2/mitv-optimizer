# Device PoC

These scripts target `192.168.10.100:5555`. The device must be a recoverable test unit.

`device-poc.ps1` captures package, Home, service, and component state. It is read-only by
default. `-Mutate` only restores known component/package states with root commands; it does
not claim that the Binder PoC succeeded.

The bridge APK is the PoC client for a ROM's package-operation chain: install it manually,
exercise both launch sources, then collect `logcat -s MiTVHomeBridge` and the before/after
`dumpsys package` output. Record the ROM build, which tier succeeded, the exception/permission
result, and reboot persistence before enabling any operation in a release build. On finch the
app-uid direct Binder tier is refused outright (`results-2026-09-29.md`), so the tiers to
verify are the TvService root script and the `su` fallback.

`analyze-installer.ps1` only extracts the real package installer APK and metadata. DEX review
must happen before selecting any component for a mutation PoC.
