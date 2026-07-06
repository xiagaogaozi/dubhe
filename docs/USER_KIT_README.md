# Dubhe 本机用户交付包

生成时间：`{{GENERATED_AT}}`

这个交付包用于这台电脑上的内部体验和给非技术用户试用。它把当前已经生成的 Windows / Android 安装包、中文安装向导、体检报告和双击入口集中到一个目录里。

## 最快使用顺序

1. 双击 `00-Start-Dubhe-This-PC.cmd`，启动 Dubhe Core 和桌面端。
2. 第一次使用真实 AI 或新闻源时，双击 `01-Configure-Dubhe-This-PC.cmd`，按中文向导填写 key；不知道的项目直接回车即可。
3. 需要动态登录验证码时，双击 `02-Setup-Dubhe-MFA-This-PC.cmd`，用认证器 App 扫码，然后重启 Dubhe Core。
4. 双击 `03-Accept-Dubhe-This-PC.cmd` 做本机完整验收。
5. 需要手机连接时，双击 `04-Connect-Dubhe-Mobile-This-PC.cmd`，扫码或填写连接卡里的 Core 地址。
6. 如需单独定位环境问题，双击 `05-Check-Dubhe-This-PC.cmd` 做本机体检。
7. 需要检查本地审计日志是否被改写时，双击 `06-Verify-Dubhe-Audit-This-PC.cmd`。
8. 只需要局域网启动日志时，双击 `07-Start-Dubhe-LAN-This-PC.cmd`。
9. 填完 key 后，双击 `08-Test-Services-This-PC.cmd` 检查 AI 和新闻源连接。
10. 真正准备商业发布前，双击 `09-Check-Production-This-PC.cmd` 查看生产门禁。
11. 需要把生产阻断项交给团队补齐时，双击 `10-Export-Production-Pack-This-PC.cmd`。
12. 需要单独重跑主链路时，双击 `11-Smoke-Dubhe-This-PC.cmd`。
13. 需要确认最新交付 ZIP 没有损坏或漏文件时，双击 `12-Verify-Dubhe-Delivery-This-PC.cmd`。
14. 下载 GitHub Actions 四端产物后，双击 `13-Import-Dubhe-CI-Artifacts-This-PC.cmd` 导入并重打交付包。
15. 需要查看当前是否能发行或还缺什么时，双击 `14-Export-Dubhe-Release-Evidence-This-PC.cmd`。
16. 需要给 GitHub CLI 补 workflow 权限时，双击 `15-Authorize-Dubhe-GitHub-Actions-This-PC.cmd`。
17. 需要启用 GitHub Actions 四端构建时，双击 `16-Activate-Dubhe-GitHub-Actions-This-PC.cmd`。

## 这个包里的内容

- Windows 安装包目录：`01-Windows`
- Android 安装包目录：`02-Android`
- 中文向导目录：`03-Guides`，其中 `mobile-connect.html` 是手机连接卡，`production-pack` 是生产上线补齐包。
- 体检报告目录：`04-Checks`
- macOS 安装包目录：`05-macOS`，下载 macOS CI 产物后会放入 `.dmg/.zip`。
- iOS 安装包目录：`06-iOS`，下载 iOS CI 产物后会放入 `Runner.app` 或 `.ipa`。
- 双击入口：`00-Start-Dubhe-This-PC.cmd` 等文件
- 安装包索引：`INSTALL-PACK-INDEX.html`，用表格列出 Windows / macOS / iOS / Android 产物、大小、哈希和缺失项。
- 校验清单：`CHECKSUMS-SHA256.txt`，用于确认主要安装文件、说明文件和报告没有损坏或被替换；Windows 已解包目录不逐文件展开，正式分发优先校验 setup/portable 安装文件。

## 重要说明

- 当前仓库路径：`{{REPO_ROOT}}`
- 本机 Core 地址：`{{CORE_URL}}`
- 手机 Core 地址候选：`{{LAN_CORE_URLS}}`
- 这个交付包里的双击入口会调用上面的仓库路径。不要删除或移动该仓库，否则这些入口会失效。
- Windows 和 Android 当前可以本机体验；macOS / iOS 仍需要 macOS runner、Apple 签名、公证和商店发布资料。
- 默认生成的 ZIP 不包含 `01-Windows\win-unpacked` 已解包目录，优先分发 setup 或 portable；完整目录版仍保留在未压缩的用户包文件夹里。
- 发出 ZIP 前建议先运行 `Verify-Dubhe-Delivery.cmd`，确认 ZIP 摘要、关键安装包和 `CHECKSUMS-SHA256.txt` 逐文件校验都通过。
- 真实生产上线前必须让 `Check-Dubhe-Production.cmd` 通过。当前本地演示能力不等于商业生产可用。
- 本地审计链验证只能证明当前 SQLite 审计记录的哈希链没有断裂，不等同于生产级 WORM、对象锁或外部不可变审计存储。

## 已检测到的安装产物

- Windows setup：`{{WINDOWS_SETUP}}`
- Windows portable：`{{WINDOWS_PORTABLE}}`
- Windows 已解包桌面程序：`{{WINDOWS_UNPACKED_EXE}}`
- Android debug APK：`{{ANDROID_APK}}`
- Android release AAB：`{{ANDROID_AAB}}`
- macOS DMG：`{{MACOS_DMG}}`
- macOS ZIP：`{{MACOS_ZIP}}`
- iOS no-codesign app bundle：`{{IOS_APP}}`
- iOS IPA：`{{IOS_IPA}}`
