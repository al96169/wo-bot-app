# wo-bot App

wo-bot 的 Flutter 移动客户端，目标平台为 Android 与 iOS。

## 当前阶段

第一阶段仅实现手机竖屏主界面：

- 启动时自动通过 mDNS 扫描 `_wobot._tcp.local`，支持刷新按钮与下拉刷新。
- “我的设备”和“局域网发现”分区展示；发现结果不会自动保存。
- 手动添加支持“保存”和“保存并连接”。
- 未绑定设备连接后进入服务端声明的绑定方式流程。
- 支持移除已保存设备。
- 个人页保留登录入口；登录后展示云端设备列表（设备名/在线状态/解绑），支持解绑设备。
- 正式 Logto Native App 参数准备完成前使用 wo-bot-account 自定义授权码流程（R00041，PKCE + wobot:// 深链回调）。

机器人主页、遥控、SSH 和其他功能不属于本阶段验收范围。

## 环境

- Flutter 3.38.2（D:\Flutter\flutter，含版本文件 hack）
- Dart 3.10
- Android applicationId：当前仍为 `com.example.wo_bot`，正式发布前待确认
- iOS Bundle ID：由 Xcode 的 `PRODUCT_BUNDLE_IDENTIFIER` 管理，正式发布前待确认

## 验证

```powershell
flutter analyze
flutter test
```

当前测试包含设备主页、手动添加双操作、绑定状态机、发现设备显式保存规则、云端设备获取/解绑、个人页登录态。

## Logto

正式登录暂缓。App 已实现 wo-bot-account 自定义授权码流程（PKCE + `wobot://auth/callback` 深链），服务地址：
- 授权页：`https://user.wo-bot.com/app-new-bind`
- 设备 API：`https://api.wo-bot.com`（`/api/oauth/*`、`/api/devices`）

原生 App 使用 Authorization Code + PKCE，不应内置 Client Secret。正式发布前需确认 `client_id=wo-bot-app` 在 wo-bot-account 中的注册情况。
