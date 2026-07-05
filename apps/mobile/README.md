# Dubhe Companion

Dubhe Companion 是 Dubhe 的 iOS / Android 移动端壳。当前目标是让中文用户在手机上完成登录、查看新闻雷达、触发中文 AI 影响分析、生成策略草案、运行回测、提交纸面交易、查看纸面组合和处理风控审批。

## 当前能力

- 复用 Dubhe Core 本地账号登录和开发期 MFA。
- 保存用户最近使用的 Core 地址，方便真机、模拟器和局域网环境复用。
- 查看 `/v1/workspaces/{workspace_id}/snapshot` 工作区快照、服务器同步序号和最近同步事件。
- 订阅 `/v1/workspaces/{workspace_id}/sync-events/ws` WebSocket 实时同步推送，收到纸面组合、审批、风控或急停事件后自动刷新对应面板。
- 拉取 `/v1/news/feed` 新闻源。
- 调用 `/v1/news/analyze` 生成中文影响分析。
- 调用 `/v1/strategy/drafts/from-analysis` 生成策略草案。
- 调用 `/v1/backtests/replay` 运行 deterministic replay 回测。
- 调用 `/v1/simulation/paper-orders` 提交纸面买入验证。
- 查看 `/v1/simulation/paper-portfolio/{account_id}` 纸面组合。
- 管理员或风控管理员可查看 `/v1/approvals`，并调用通过/拒绝接口。
- 管理员或风控管理员可查看 `/v1/risk/kill-switch`，并在移动端启用或解除急停开关。
- 管理员或风控管理员可通过 `/v1/risk/evaluate` 生成实盘审批演示；该入口只创建审批请求，不连接真实券商或发送真实订单。
- 管理员或风控管理员可查看 `/v1/audit/logs` 最近审计日志，追踪急停、审批和风控评估记录。

## 平台工程

本仓库已经提交 Android / iOS 平台工程。当前本机已验证 Flutter `3.44.4` / Dart `3.12.2`、Android SDK `36.0.0`、Temurin JDK `17.0.19` 下的 `flutter analyze`、`flutter test` 与 Android debug APK 构建。

首次拉取后，在本目录执行：

```powershell
cd D:\github\dubhe-main\apps\mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8000
```

Android 模拟器连接本机 Core 时通常使用：

```powershell
flutter run --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8000
```

iOS 模拟器连接本机 Core 时可使用：

```powershell
flutter run --dart-define=DUBHE_CORE_URL=http://127.0.0.1:8000
```

真机需要把 `DUBHE_CORE_URL` 改成局域网或公网可访问的 Dubhe Core 地址；用户也可以在登录页直接修改 Core 地址，成功进入后会自动保存。

## 安装包命令

Android：

```powershell
flutter build apk --debug --dart-define=DUBHE_CORE_URL=https://your-core.example.com
flutter build appbundle --release --dart-define=DUBHE_CORE_URL=https://your-core.example.com
```

默认没有 `android/key.properties` 时，release 构建会继续使用 debug key 作为本地烟测兜底，不可用于正式分发。准备正式 Android 包时，在 `apps/mobile/android` 下复制 `key.properties.example` 为 `key.properties`，把 `storeFile` 指向本地 keystore，并填入真实 `storePassword`、`keyPassword` 和 `keyAlias`；`key.properties`、`*.jks`、`*.keystore` 已在 `.gitignore` 中排除。

Android 工程禁用了 Kotlin incremental build，以避免 Windows 上 Pub cache 与仓库位于不同盘符时 `shared_preferences_android` 增量缓存路径 relativize 失败。

本机开发调试包已验证输出到：

```text
D:\github\dubhe-main\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

iOS 需要在 macOS + Xcode 环境执行：

```bash
flutter build ios --release --dart-define=DUBHE_CORE_URL=https://your-core.example.com
```

当前仍不是最终 App Store / TestFlight / 企业签名包。后续还需要补齐正式 Bundle ID、签名、图标、权限声明、推送通知、离线缓存和生产身份系统。

## GitHub Actions

`docs/ci/mobile.yml` 是移动端打包流水线模板。将它复制到 `.github/workflows/mobile.yml` 后，可以手动触发或在 `main` 分支移动端文件变更时构建：

- Android debug APK：`build/app/outputs/flutter-apk/app-debug.apk`。
- Android release appbundle：配置签名 secrets 后输出 `build/app/outputs/bundle/release/app-release.aab`。
- iOS no-codesign app bundle：`build/ios/iphoneos/Runner.app`。

工作流会运行 `flutter pub get`、`flutter test` 和对应构建命令。Android release appbundle 需要在仓库 secrets 中提供 `ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD` 和 `ANDROID_KEY_ALIAS`。正式发布前仍需要接入 iOS Apple Developer 签名、正式图标和商店元数据。

本机当前 `flutter doctor -v` 已识别 Android 工具链且所有 Android licenses 已接受。剩余提示为 Flutter/Dart 未加入全局 `PATH`，以及 `maven.google.com` 网络检查偶发超时；本地 Android debug APK 构建已通过。iOS 构建仍需要 macOS + Xcode。
