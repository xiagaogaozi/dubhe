# Dubhe Companion

Dubhe Companion 是 Dubhe 的 iOS / Android 移动端壳。当前目标是让中文用户在手机上完成登录、查看新闻雷达、触发中文 AI 影响分析、查看纸面组合和处理风控审批。

## 当前能力

- 复用 Dubhe Core 本地账号登录和开发期 MFA。
- 拉取 `/v1/news/feed` 新闻源。
- 调用 `/v1/news/analyze` 生成中文影响分析。
- 查看 `/v1/simulation/paper-portfolio/{account_id}` 纸面组合。
- 管理员或风控管理员可查看 `/v1/approvals`，并调用通过/拒绝接口。

## 平台工程

本仓库已经提交 Android / iOS 平台工程。当前本机已验证 Flutter `3.44.4` / Dart `3.12.2` 下的 `flutter analyze` 与 `flutter test`。

首次拉取后，在本目录执行：

```powershell
cd D:\github\dubhe-main\apps\mobile
flutter pub get
flutter analyze
flutter test
```

Android 模拟器连接本机 Core 时通常使用：

```powershell
flutter run --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8019
```

iOS 模拟器连接本机 Core 时可使用：

```powershell
flutter run --dart-define=DUBHE_CORE_URL=http://127.0.0.1:8019
```

真机需要把 `DUBHE_CORE_URL` 改成局域网或公网可访问的 Dubhe Core 地址。

## 安装包命令

Android：

```powershell
flutter build apk --debug --dart-define=DUBHE_CORE_URL=https://your-core.example.com
flutter build appbundle --release --dart-define=DUBHE_CORE_URL=https://your-core.example.com
```

iOS 需要在 macOS + Xcode 环境执行：

```bash
flutter build ios --release --dart-define=DUBHE_CORE_URL=https://your-core.example.com
```

当前仍不是最终 App Store / TestFlight / 企业签名包。后续还需要补齐正式 Bundle ID、签名、图标、权限声明、推送通知、离线缓存和生产身份系统。

## GitHub Actions

`docs/ci/mobile.yml` 是移动端打包流水线模板。将它复制到 `.github/workflows/mobile.yml` 后，可以手动触发或在 `main` 分支移动端文件变更时构建：

- Android debug APK：`build/app/outputs/flutter-apk/app-debug.apk`。
- iOS no-codesign app bundle：`build/ios/iphoneos/Runner.app`。

工作流会运行 `flutter pub get`、`flutter test` 和对应构建命令。正式发布前仍需要接入 Android release signing、iOS Apple Developer 签名、正式图标和商店元数据。

本机当前 `flutter doctor -v` 显示 Android SDK 尚未安装，因此 Android APK 仍需在 CI 或安装 Android Studio / Android SDK 后构建；iOS 构建需要 macOS + Xcode。
