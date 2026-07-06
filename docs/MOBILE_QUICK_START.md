# Dubhe 手机安装与连接向导

这个向导给不会命令行的中文用户使用。双击仓库根目录的 `Open-Dubhe-Mobile-Guide.cmd` 时，Dubhe 会把本文件里的占位符替换成你这台电脑上的真实地址和安装包路径，并用记事本打开一份临时说明。

## 这台电脑检测到的信息

- 手机登录页可填写的 Core 地址候选：`{{LAN_CORE_URLS}}`
- Android 调试安装包路径：`{{ANDROID_APK_PATH}}`
- 手机扫码连接入口：`{{CONNECT_MOBILE_CMD}}`
- 手机局域网启动入口：`{{START_LAN_CMD}}`
- 本机体检入口：`{{CHECK_CMD}}`
- 手机连接卡 HTML：`{{MOBILE_CONNECT_HTML}}`
- 手机连接卡文本：`{{MOBILE_CONNECT_TEXT}}`
- 手机连接二维码：`{{MOBILE_CONNECT_QR}}`
- 移动端开发说明：`{{MOBILE_README}}`

如果地址候选显示 `(no LAN IPv4 address detected)`，说明电脑当前没有检测到可用的局域网 IPv4 地址。请先让电脑和手机连接到同一个 Wi-Fi 或有线局域网，再重新打开本向导。

## Android 真机

1. 在电脑上双击 `Connect-Dubhe-Mobile.cmd`。
2. 如果 Windows 防火墙弹窗出现，允许专用网络访问。
3. 浏览器会打开手机连接卡；能看到二维码时直接扫码，不能扫码时把连接卡里的 `http://192.168.x.x:8000` 填到手机登录页的 “Core 地址”。
4. 在手机登录页点击 “检查连接”。成功后地址会保存。
5. 安装上方 APK 路径里的 `app-debug.apk`，然后注册或登录本地账号。

第一次使用真实 AI 或授权新闻源时，先在电脑上双击 `Configure-Dubhe.cmd`，按中文向导填写 key；不知道的项目直接回车即可。需要动态登录验证码时，再双击 `Setup-Dubhe-MFA.cmd`，用认证器 App 扫码。保存后重新启动 Dubhe Core，再回到手机端同步状态。

如果 APK 路径后面显示 `(not built yet)`，说明这台电脑还没有生成 Android 调试包。开发者可以在 `apps/mobile` 下执行：

```powershell
flutter build apk --debug --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8000
```

## Android 模拟器

Android 模拟器通常不能直接访问电脑的 `127.0.0.1`。登录页点击 “Android 模拟器”，地址会自动填成：

```text
http://10.0.2.2:8000
```

然后点击 “检查连接”，成功后再登录。

## iOS 模拟器

iOS 模拟器通常可以使用本机地址。登录页点击 “本机 / iOS 模拟器”，地址会自动填成：

```text
http://127.0.0.1:8000
```

真机 iPhone 仍然需要使用局域网地址，也就是上方的 `http://192.168.x.x:8000`。

## 常见问题

- 检查连接失败：先重新双击 `Connect-Dubhe-Mobile.cmd`，确认 Core 已经用局域网模式启动，并优先使用连接卡显示的第一个地址。
- 地址填了但手机打不开：确认手机和电脑在同一个 Wi-Fi，且 Windows 防火墙允许专用网络访问。
- 登录后没有新闻或 AI：先双击 `Configure-Dubhe.cmd` 填写授权新闻源和 AI 模型 key，或在客户端 “系统状态 / 数据源配置” 中填写。
- 登录验证码不想继续用固定占位码：在电脑上双击 `Setup-Dubhe-MFA.cmd`，扫码后重启 Core。
- 想确认整套链路是否可用：优先双击 `Accept-Dubhe.cmd` 跑本机完整验收；只想单独验证主链路时，再双击 `Smoke-Dubhe.cmd`。
