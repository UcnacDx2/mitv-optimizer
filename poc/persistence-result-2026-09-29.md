# TvService persistence probe

Target: `192.168.10.100` (`finch`, Android 14, `verifiedbootstate=orange`).

The script was invoked through `service call TvService 4400` and reported:

```text
uid=0(root) gid=0(root) context=u:r:misysdiagnose:s0
/vendor/bin/init.post-fs-data.sh: readable=0, writable=1
/dev/block/dm-9 on /vendor type erofs (...,ro,...)
/data/adb: Permission denied
```

Conclusion: TvService provides temporary root execution, but this SELinux domain
cannot write the vendor startup script and cannot access Magisk's `/data/adb`.
No startup-chain file, mount, AVB metadata, or Magisk state was modified.

## Recheck after module reboot

The same read-only probe was run again through `service call TvService 4400`
after reinstalling the optimizer module and rebooting. It again reported
`uid=0(root)`, `u:r:misysdiagnose:s0`, `verifiedbootstate=orange`, `/vendor`
mounted as read-only EROFS, a failed write test (`writable=1`), and SELinux
denial for `/data/adb`. This confirms that the temporary root does not provide
the persistence permissions needed for a boot-time Magisk mount on this device.
