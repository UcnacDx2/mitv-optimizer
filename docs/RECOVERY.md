# 恢复说明

## Android 和 Magisk 正常可用

1. 在 Magisk App 中禁用 `MiTV Optimizer`。
2. 重启，确认桌面和设置入口正常。
3. 再从 Magisk App 卸载模块并重启。

## 只有 ADB root 可用

```sh
su -c 'touch /data/adb/modules/mitv-optimizer/disable'
su -c 'pm enable --user 0 com.xiaomi.mitv.settings/com.xiaomi.mitv.settings.entry.FallbackHome'
su -c 'pm enable --user 0 com.mitv.tvhome/com.mitv.tvhome.MainActivityUserMode'
su -c reboot
```

## 第三方桌面异常但系统仍运行

先恢复两个 Home 组件，再禁用模块。不要先删除整个 Magisk 数据目录。

模块的变更前状态和运行日志位于 `/data/adb/mitv-optimizer/`；卸载完成后该临时状态目录会被删除。
