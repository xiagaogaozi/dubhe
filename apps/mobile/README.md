# Dubhe Companion

Dubhe Companion 是 Dubhe 的 iOS / Android 移动端壳。当前目标是让中文用户在手机上完成登录、查看新闻雷达、触发中文 AI 影响分析、查看纸面组合和处理风控审批。

## 当前能力

- 复用 Dubhe Core 本地账号登录和开发期 MFA。
- 拉取 `/v1/news/feed` 新闻源。
- 调用 `/v1/news/analyze` 生成中文影响分析。
- 查看 `/v1/simulation/paper-portfolio/{account_id}` 纸面组合。
- 管理员或风控管理员可查看 `/v1/approvals`，并调用通过/拒绝接口。

## 生成平台工程

本仓库当前提交的是 Flutter 源码骨架。本机尚未安装 Flutter SDK 时，不能在这台机器上直接验证 `flutter test` 或生成安装包。

安装 Flutter 后，在本目录执行：

```powershell
cd D:\github\dubhe-main\apps\mobile
flutter create --platforms=ios,android --project-name dubhe_companion .
flutter pub get
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
