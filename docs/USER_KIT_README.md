# Dubhe 本机用户交付包

生成时间：`{{GENERATED_AT}}`

这个交付包用于这台电脑上的内部体验和给非技术用户试用。它把当前已经生成的 Windows / Android 安装包、中文安装向导、体检报告和双击入口集中到一个目录里。

## 最快使用顺序

1. 双击 `00-Start-Dubhe-This-PC.cmd`，启动 Dubhe Core 和桌面端。
2. 第一次使用真实 AI 或新闻源时，双击 `01-Configure-Dubhe-This-PC.cmd` 填写 key。
3. 双击 `02-Check-Dubhe-This-PC.cmd` 做本机体检。
4. 需要手机连接时，双击 `03-Start-Dubhe-LAN-This-PC.cmd`，再看 `03-Guides\mobile-quick-start.txt`。
5. 填完 key 后，双击 `04-Test-Services-This-PC.cmd` 检查 AI 和新闻源连接。
6. 真正准备商业发布前，双击 `05-Check-Production-This-PC.cmd` 查看生产门禁。

## 这个包里的内容

- Windows 安装包目录：`01-Windows`
- Android 安装包目录：`02-Android`
- 中文向导目录：`03-Guides`
- 体检报告目录：`04-Checks`
- 双击入口：`00-Start-Dubhe-This-PC.cmd` 等文件

## 重要说明

- 当前仓库路径：`{{REPO_ROOT}}`
- 本机 Core 地址：`{{CORE_URL}}`
- 手机 Core 地址候选：`{{LAN_CORE_URLS}}`
- 这个交付包里的双击入口会调用上面的仓库路径。不要删除或移动该仓库，否则这些入口会失效。
- Windows 和 Android 当前可以本机体验；macOS / iOS 仍需要 macOS runner、Apple 签名、公证和商店发布资料。
- 真实生产上线前必须让 `Check-Dubhe-Production.cmd` 通过。当前本地演示能力不等于商业生产可用。

## 已检测到的安装产物

- Windows setup：`{{WINDOWS_SETUP}}`
- Windows portable：`{{WINDOWS_PORTABLE}}`
- Windows 已解包桌面程序：`{{WINDOWS_UNPACKED_EXE}}`
- Android debug APK：`{{ANDROID_APK}}`
- Android release AAB：`{{ANDROID_AAB}}`
