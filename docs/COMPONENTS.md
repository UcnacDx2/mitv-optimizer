# 组件依据

以下组件来自 `com.mitv.tvhome` Manifest，并由反编译类名、调用路径或广告事件字段交叉确认：

| 组件 | 类型 | 依据 |
|---|---|---|
| `ads.floatad.FloatAdActivity` | Activity | 悬浮广告展示与播放事件 |
| `ads.wakeupad.WakeUpAdActivity` | Activity | 唤醒广告展示 |
| `receiver.PushDialogReceiver` | Receiver | 推送弹窗与推送页面 |
| `ads.pushad.PushAdReceiver` | Receiver | 拉取并展示 push ad |
| `ads.utils.AdEventTracker` | Receiver | 广告播放、展示和 alarm 事件记录 |
| `ads.alarmcare.AlarmCareReceiver` | Receiver | 位于 `ads.alarmcare`，触发 outside_ad 请求/展示，不是普通闹钟 |
| `snapup.ui.SnapUpActivity` | Activity | 抢购、商品库存与购买二维码界面 |
| `com.xiaomi.ad.internal.server.AdReceiver` | Receiver | 小米广告 SDK Receiver |

Home 组件分开处理：

- `com.xiaomi.mitv.settings.entry.FallbackHome`：默认禁用，但受第三方 Home 安全闸保护。
- `com.mitv.tvhome.MainActivityUserMode`：默认保留；只有显式设置 `DISABLE_FACTORY_HOME=1` 才处理。

OTA 单独通过包级状态控制：`com.xiaomi.mitv.upgrade`。
