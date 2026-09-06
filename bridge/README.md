# MiTV Home Bridge

小米电视原厂桌面与第三方桌面之间的轻量桥接应用。

## 行为

- 从 `com.mitv.tvhome` 打开本应用：
  - 尝试通过 PackageManager Binder service call 禁用
    `com.mitv.tvhome/.MainActivityUserMode`；
  - 同时禁用 `com.xiaomi.mitv.settings/.entry.FallbackHome`；
  - Binder 权限不足或 ROM 不兼容时，再请求 `su` 执行同样的组件操作。
- 从其他入口打开本应用：
  - 重新启用 `com.mitv.tvhome/.MainActivityUserMode`；
  - 不改动 `FallbackHome`；
  - 随后启动原厂小米桌面。`HOME_STATE` 签名权限不可用时使用 Root 启动。

入口判断优先使用 `getCallingPackage()`，并使用 Android activity referrer
(`android-app://com.mitv.tvhome`) 作为普通 `startActivity()` 场景的主要判断依据。

## 为什么不写死 `service call package` 编号

`IPackageManager` 的 Binder transaction 编号会随 Android 版本变化。应用运行时从
ROM 自带的 `android.content.pm.IPackageManager$Stub` 读取
`TRANSACTION_setComponentEnabledSetting`，再直接调用 `package` Binder service。
如果 ROM 的 hidden API 策略阻止这一方式，会自动进入 Root fallback，不会尝试猜测编号。

## 构建

Windows：

```powershell
.\build.ps1
```

Linux（仓库/CI 环境）：

```sh
chmod +x build.sh
./build.sh
```

产物为 `MiTVHomeBridge.apk`。

仓库中提供的预编译 APK 使用 CI/构建环境的 debug key 签名。如果设备上已有由另一把
debug key 签名的旧版，请先卸载旧版，或在自己的电脑上运行 `build.ps1` 使用原来的
`~/.android/debug.keystore` 重新签名后再覆盖安装。
