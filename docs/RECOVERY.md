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

## 只禁用、不卸载：安装器限制的两项要手动恢复

在 Magisk App 中禁用模块，和上面那条写 `disable` 文件的路径，都**只停止继续应用，不回滚已经
写入的值**。负责回滚的 `uninstall.sh` 只在卸载模块时执行，所以走完这两条路径后
`system/pi_config` 与 `com.android.packageinstaller` 的 `WRITE_SETTINGS` appop 仍是改过的状态，
安装器限制继续生效——这一点在界面和日志里都看不出来。

原值记在模块的状态目录里，**卸载时该目录会被删除，所以要回滚请在卸载前操作**：

- `/data/adb/mitv-optimizer/settings.tsv`，每行 `命名空间|键|值`；原本没有这一项时值记作 `__NULL__`
- `/data/adb/mitv-optimizer/appops.tsv`，每行 `包名|操作|模式`；原本是默认值时模式记作 `default`

按记录手动恢复：

```sh
# pi_config（值为 __NULL__ 时改用 settings delete system pi_config）
su -c 'settings put system pi_config "<settings.tsv 里的值>"'

# 安装器 appop（模式为 default 时同样用 delete）
su -c 'cmd appops set --user 0 com.android.packageinstaller WRITE_SETTINGS allow'
```

这两条都必须有 root：该 appop 属于别的包，`settings` / `cmd` 加 `--user 0` 还需要额外权限，
普通 adb shell 改不动。正常卸载模块时 `uninstall.sh` 会读这两个文件自动回滚，不需要手动做。

## 第三方桌面异常但系统仍运行

先恢复两个 Home 组件，再禁用模块。不要先删除整个 Magisk 数据目录。

模块的变更前状态和运行日志位于 `/data/adb/mitv-optimizer/`；卸载完成后该临时状态目录会被删除。
