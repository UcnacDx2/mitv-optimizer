# MiTV Optimizer

面向已获取 Magisk root 的小米电视优化模块。当前实机目标为 `finch` / Android 14 / `OS3.0.115.0.UFFMATV`。

## 功能

- 合并并挂载电视广告域名 hosts。
- 将已安装的当贝桌面系统化，并设为首选 Home。
- 将当贝桌面中的系统设置入口指向电视已有的 `com.example.tvsettingslauncher`。
- 集成独立仓库 `mitv-home-bridge` 的 APK。目标 ROM 已通过 PoC 验证 `TvService` 临时 Root 链路可执行 PackageManager 操作；bridge 使用该路径并保留回退，同时在应用内完成第三方桌面安全闸。
- 禁用小米电视 OTA 更新包 `com.xiaomi.mitv.upgrade`。
- 禁用经 Manifest 与反编译代码确认的桌面广告组件。
- 单独禁用 `FallbackHome`；默认不禁用原厂 `MainActivityUserMode`。
- 保存变更前状态，卸载模块时按记录恢复。

## 安全设计

本项目允许并要求在构建产物中直接分发 bridge 和当贝桌面 APK。安装时优先使用
`artifacts/` 内置、已校验包名和签名摘要的 APK，形成 systemless system app；只有在
内置文件缺失时才从电视上已经安装的包中捕获对应 APK 作为兼容回退。缺少任一必需应用
时安装会中止。

`FallbackHome` 只有在系统实际解析到当贝 Home 后才会禁用。如果当贝 Home 不可用，安全闸会跳过所有 Home 组件变更并写入日志。

## 安装前置

构建时必须提供以下 APK 本体：

- `com.dangbei1.tvlauncher`
- `com.ucnacdx2.mitvhomebridge`

```powershell
.\scripts\build.ps1 -DangbeiApk .\path\com.dangbei1.tvlauncher.apk
```

构建机若有 `aapt.exe` 和 `apksigner.bat` 会执行实时元数据与签名校验；没有时使用项目
固定的包名、版本和已记录签名摘要，并仍生成 SHA-256 清单。

最终 ZIP 的 `artifacts/` 包含 bridge 和当贝桌面 APK，并生成 `SHA256SUMS` 与
`ARTIFACT-METADATA.tsv`。构建阶段会用 `aapt` 校验包名/版本字段，并用 `apksigner`
校验证书摘要；缺少或签名不完整的 APK 不会进入产物。

然后在 Magisk App 中安装 `mitv-optimizer-v0.1.0.zip` 并重启。

## 配置

功能开关位于 `options.conf`。默认仅禁用 `FallbackHome`，不禁用原厂主 Home。修改后重启生效。

### 无线 ADB

本模块不维护无线 ADB。需要开机持久化 ADB over TCP 时，建议单独安装并配置
[`Magisk-Remote-Adb`](https://github.com/Zhu-junwei/Magisk-Remote-Adb)，避免与本模块的
广告、OTA 和组件处理逻辑相互影响。

## 回滚

优先从 Magisk App 禁用模块并重启。确认电视恢复后再卸载。卸载脚本会恢复记录到的组件、OTA 包、广告设置和原 Home。

详见 [恢复说明](docs/RECOVERY.md) 和 [组件依据](docs/COMPONENTS.md)。

## Hosts 来源

合并列表包含：

- jdlingyu `ext_rules` hosts
- TG-Twilight `AWAvenue-Ads-Rule` hosts
- 项目中针对小米电视验证过的精选域名

过滤规则保留更新、登录、视频、天气等电视核心服务域名。第三方列表分别遵循其上游许可。

## 许可

脚本与文档采用 MIT License。第三方 hosts 数据和安装时捕获的应用 APK 不在该许可范围内。
