# Dubhe Companion

Dubhe Companion 是 Dubhe 的 iOS / Android 移动端壳。当前目标是让中文用户在手机上完成登录、查看新闻雷达、触发中文 AI 影响分析、生成策略草案、运行回测、提交纸面交易、查看纸面组合和处理风控审批。

## 当前能力

- 复用 Dubhe Core 本地账号登录和开发期 MFA。
- 登录页可一键填入 Android 模拟器、本机/iOS 模拟器和最近成功的 Core 地址，也可以从剪贴板填入局域网地址并先检查连接；成功后会保存地址，方便真机、模拟器和局域网环境复用。
- 查看 `/v1/workspaces/{workspace_id}/snapshot` 工作区快照、服务器同步序号、最近同步事件和已同步策略草案，并可一键使用同步策略进入回测/纸面验证。
- 订阅 `/v1/workspaces/{workspace_id}/sync-events/ws` WebSocket 实时同步推送；WebSocket 不可用时会降级轮询 `/v1/workspaces/{workspace_id}/sync-events`，收到纸面组合、审批、风控或急停事件后自动刷新对应面板。
- 拉取 `/v1/news/feed` 新闻源；“雷达”页可切换美股、港股、A 股和全球宏观，并提供 NVDA、0700.HK、600519.SH 等常用标的快捷刷新。
- 调用 `/v1/news/analyze` 生成中文影响分析。
- 调用 `/v1/strategy/drafts/from-analysis` 生成策略草案。
- 调用 `/v1/backtests/replay` 运行 deterministic replay 回测。
- 调用 `/v1/assistant/chat` 进行可审计的中文 AI 分析师对话，讨论当前新闻、分析、策略草案和回测结果；会显示真实模型或本地兜底状态，工作区同步快照会恢复最近问答。
- 调用 `/v1/simulation/paper-orders` 提交纸面买入验证。
- 查看 `/v1/simulation/paper-portfolio/{account_id}` 纸面组合。
- 管理员或风控管理员可查看 `/v1/approvals`，并调用通过/拒绝接口。
- 管理员或风控管理员可查看 `/v1/risk/kill-switch`，并在移动端启用或解除急停开关。
- 管理员或风控管理员可通过 `/v1/risk/evaluate` 生成实盘审批演示；该入口只创建审批请求，不连接真实券商或发送真实订单。
- 管理员或风控管理员可查看 `/v1/audit/logs` 最近审计日志，追踪急停、审批和风控评估记录。
- 管理员可在“系统状态”里读取和保存运行 Core 那台电脑上的本地配置，用于填写 AI 模型和授权新闻源 key；密钥只写入 Core 本机配置文件，不会从 Core 回传到手机端。
- “系统状态”会显示 `/v1/system/smoke-report` 最近一次主链路 smoke，通过手机就能确认账号、新闻、AI、策略、回测、纸面交易和同步是否跑通。
- “系统状态”会显示 Windows、Android、macOS 和 iOS 安装包状态，直接告诉用户哪些本机产物已经生成，哪些需要 macOS CI、签名或商店发布配置。
- “今日”页会显示 `/v1/onboarding/checklist` 首次使用清单，告诉用户从连接、登录、配置、新闻、AI、同步到纸面交易的下一步，并可一键切到对应页面或触发安全动作。

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

真机需要把 `DUBHE_CORE_URL` 改成局域网或公网可访问的 Dubhe Core 地址。Windows 用户可在仓库根目录先双击 `Open-Dubhe-Mobile-Guide.cmd` 查看手机安装与连接向导；连接前再双击 `Start-Dubhe-LAN.cmd`，它会重启 Core 为局域网模式，并在体检结果里显示类似 `http://192.168.x.x:8000` 的地址；把这个地址填到登录页“Core 地址”即可，成功进入后会自动保存。

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
