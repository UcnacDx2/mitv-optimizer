# MiTV Optimizer

面向已获取 Magisk root 的小米电视优化模块。当前实机目标为 `finch` / Android 14 / `OS3.0.115.0.UFFMATV`。

## 功能

- 合并并挂载电视广告域名 hosts。
- 把当贝桌面 APK 放到 `system/app/`，使其成为系统应用。**模块不设置首选 Home**；选桌面要打开 bridge 应用自己完成。
- 集成独立仓库 `mitv-home-bridge` 的 APK。目标 ROM 已通过 PoC 验证 `TvService` 临时 Root 链路可执行 PackageManager 操作；bridge 使用该路径并保留回退，同时在应用内完成第三方桌面安全闸。
- 禁用小米电视 OTA 更新包 `com.xiaomi.mitv.upgrade`。
- 解除安装器限制：拒绝 `com.android.packageinstaller` 的 `WRITE_SETTINGS` appop，并清空 / 重写 `system/pi_config`，使安装器无法再按厂商白名单拦截安装。
- 禁用经 Manifest 与反编译代码确认的桌面广告组件。
- 不主动禁用任何 Home。`FallbackHome` 的禁用由 bridge 应用在确认第三方桌面可用后执行；模块只在 HOME 解析失败时把它重新启用。
- 开机后检测 HOME 解析：若某一时刻没有任何可解析的 Home（例如所选的第三方桌面缺失或已被禁用而原厂 Home 又处于禁用），自动重新启用 `FallbackHome`，避免电视停在无桌面状态。
- 开机后检测开机是否完成：若 `sys.boot_completed` 在 120 秒内始终未置位，且原厂桌面确实处于被禁用状态，则重新启用原厂桌面组件。本 ROM 在原厂桌面与 `FallbackHome` 同时被禁用时会卡在开机动画，此时第三方桌面即使仍可解析也救不回开机。
- 保存变更前状态，卸载模块时按记录恢复。

## 安全设计

构建产物直接携带 bridge 和当贝桌面 APK，放在 `system/app/`，由 Magisk 以 systemless 方式挂载成系统应用——不是安装时从电视上抓包。构建阶段会用 `aapt` 校验包名与版本、用 `apksigner` 校验签名摘要，任一 APK 缺失或校验不过就中止构建。

`FallbackHome` 只有在系统实际解析到当贝 Home 后才会禁用。如果当贝 Home 不可用，安全闸会跳过所有 Home 组件变更并写入日志。

开机守护有两个触发条件。其一，没有任何 Home 可解析时重新启用 `FallbackHome`；其二，
`sys.boot_completed` 超过 120 秒仍未置位、且原厂桌面确实处于被禁用状态时，重新启用原厂
桌面组件——本 ROM 在原厂桌面与 `FallbackHome` 同时被禁用时会卡在开机动画，此时第三方
桌面即使仍可解析也救不回开机。两处恢复都只“启用”，从不禁用任何组件，也只在各自的条
件成立时执行，因此不会影响正常开机的 Home；恢复也不改动首选桌面，所选第三方桌面仍是
HOME 的默认处理者。所有步骤都有次数上限、幂等，并在任一步失败时保留设备原有可启动状
态。可在 `options.conf` 设置 `DISABLE_BOOT_HOME_GUARD=1` 关闭。

## 安装前置

构建时必须提供以下 APK 本体：

- `com.dangbei1.tvlauncherx`
- `com.ucnacdx2.mitvhomebridge`

```powershell
.\scripts\build.ps1 -DangbeiApk .\path\com.dangbei1.tvlauncherx.apk
```

两个 APK 都放进 `system/app/`，**不要**放进 `system/priv-app/`。本 ROM 的
`ro.control_privapp_permissions=enforce` 会在开机扫描时校验 priv-app 的
`signature|privileged` 权限白名单，而这两个 APK 都是 debug key 重签的第三方应用、不在任何
白名单里，放进去会让 PackageManagerService 抛致命异常并卡在开机动画。放 `system/app/`
则只会静默丢掉那些特权权限，作为桌面需要的普通权限不受影响。

构建机若有 `aapt.exe` 和 `apksigner.bat` 会执行实时元数据与签名校验；没有时使用项目
固定的包名、版本和已记录签名摘要，并仍生成 SHA-256 清单。

最终 ZIP 的 `system/` 包含实际安装的 bridge 和当贝桌面 APK，`artifacts/` 只保留
`SHA256SUMS` 与 `ARTIFACT-METADATA.tsv`，避免 APK 在发布包中重复。构建阶段会用 `aapt` 校验包名/版本字段，并用 `apksigner`
校验证书摘要；缺少或签名不完整的 APK 不会进入产物。

然后在 Magisk App 中安装 `mitv-optimizer-v0.3.1.zip` 并重启。

## 配置

功能开关位于 `options.conf`。默认仅禁用 `FallbackHome`，不禁用原厂主 Home。修改后重启生效。

### 安装器限制

`DISABLE_INSTALLER_RESTRICTION=1`（默认开启）在开机后以 root 执行：拒掉
`com.android.packageinstaller` 的 `WRITE_SETTINGS` appop、删除并重写 `system/pi_config`、
最后 `force-stop` 安装器。若 `pi_config` 或 appop 被 ROM 拒绝写入，日志会记录实际回读值。

这一步由模块在开机时以 root 执行，不需要打开任何应用。集成在模块内的 bridge APK 也走同一
序列，但它只通过 `su`，且仅在用户主动打开它时运行；设备没有 su 时整段跳过。

### 无线 ADB

模块默认在开机后启用 ADB over TCP `5555`。它等待 Android Settings 服务可用后写入
`Global.adb_enabled=1`，设置 `sys.set_adb_disabled=1`，并保留 30 秒间隔的异常恢复检查。
可在 `options.conf` 中设置 `ENABLE_ADB=0` 关闭，或修改 `ADB_PORT`。

## 回滚

优先从 Magisk App 禁用模块并重启。确认电视恢复后再卸载。卸载脚本会恢复记录到的组件、OTA 包、广告设置、appop 模式和原 Home。

详见 [恢复说明](docs/RECOVERY.md) 和 [组件依据](docs/COMPONENTS.md)。

## Hosts 来源

合并列表包含：

- jdlingyu `ext_rules` hosts
- TG-Twilight `AWAvenue-Ads-Rule` hosts
- 项目中针对小米电视验证过的精选域名

过滤规则保留更新、登录、视频、天气等电视核心服务域名。第三方列表分别遵循其上游许可。

## 许可

脚本与文档采用 MIT License。第三方 hosts 数据和安装时捕获的应用 APK 不在该许可范围内。
