# MiTV Optimizer

面向已获取 Magisk root 的小米电视优化模块。当前实机目标为 `finch` / Android 14 / `OS3.0.115.0.UFFMATV`。

## 功能

- 合并并挂载电视广告域名 hosts。
- 将已安装的当贝桌面系统化，并设为首选 Home。
- 将 Android TV 设置入口系统化。
- 将 MiTV Home Bridge 系统化。原厂小米桌面的入口受 `com.mitv.tvhome.permission.HOME_STATE` 签名权限保护，因此第三方签名即使成为系统应用也不能直接调用；桥接应用会在没有该签名权限时自动通过 Root 启动原厂桌面。
- 禁用小米电视 OTA 更新包 `com.xiaomi.mitv.upgrade`。
- 禁用经 Manifest 与反编译代码确认的桌面广告组件。
- 单独禁用 `FallbackHome`；默认不禁用原厂 `MainActivityUserMode`。
- 保存变更前状态，卸载模块时按记录恢复。

## 安全设计

模块不会分发当贝或小米的闭源 APK。安装时从电视上已经安装的包中复制 APK，形成 systemless system app。缺少任一必需应用时安装会中止。

`FallbackHome` 只有在系统实际解析到当贝 Home 后才会禁用。如果当贝 Home 不可用，安全闸会跳过所有 Home 组件变更并写入日志。

## 安装前置

先安装以下应用：

- `com.dangbei1.tvlauncher`
- `com.example.tvsettingslauncher`
- `com.ucnacdx2.mitvhomebridge`

然后在 Magisk App 中安装 `mitv-optimizer-v0.1.0.zip` 并重启。

## 配置

功能开关位于 `options.conf`。默认仅禁用 `FallbackHome`，不禁用原厂主 Home。修改后重启生效。

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
