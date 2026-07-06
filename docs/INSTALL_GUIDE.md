# Dubhe 四端安装与连接总向导

这个向导给只会中文、不会命令行的用户使用。双击仓库根目录的 `Open-Dubhe-Install-Guide.cmd` 时，Dubhe 会把本文件里的占位符替换成你这台电脑上的真实安装包路径、局域网地址和一键入口，并用记事本打开一份临时说明。

## 这台电脑检测到的信息

- Windows setup 安装包：`{{WINDOWS_SETUP_PATH}}`
- Windows portable 免安装包：`{{WINDOWS_PORTABLE_PATH}}`
- Windows 已解包桌面程序：`{{WINDOWS_UNPACKED_EXE_PATH}}`
- Android 调试 APK：`{{ANDROID_APK_PATH}}`
- Android release AAB：`{{ANDROID_AAB_PATH}}`
- macOS 桌面包：`{{MACOS_PACKAGE_PATH}}`
- iOS App 包：`{{IOS_APP_PATH}}`
- 手机/平板可填写的 Core 地址候选：`{{LAN_CORE_URLS}}`
- 普通启动入口：`{{START_CMD}}`
- 手机局域网启动入口：`{{START_LAN_CMD}}`
- 手机扫码连接入口：`{{CONNECT_MOBILE_CMD}}`
- 用户交付包入口：`{{USER_KIT_CMD}}`
- 手机专项向导入口：`{{MOBILE_GUIDE_CMD}}`
- 本机完整验收入口：`{{ACCEPT_CMD}}`
- 本机体检入口：`{{CHECK_CMD}}`
- 主链路烟测入口：`{{SMOKE_CMD}}`
- 外部服务体检入口：`{{SERVICE_CHECK_CMD}}`
- 生产就绪门禁入口：`{{PRODUCTION_CHECK_CMD}}`
- 生产上线补齐包入口：`{{PRODUCTION_PACK_CMD}}`
- 本机配置入口：`{{CONFIGURE_CMD}}`

## 怎么选安装方式

### Windows

1. 普通用户优先使用 `Windows setup 安装包`。
2. 没有安装权限时使用 `Windows portable 免安装包`。
3. 如果 setup/portable 生成失败，但 `Windows 已解包桌面程序` 可用，可以在 `win-unpacked` 目录里双击 `Dubhe.exe` 作为兜底体验。
4. 开发或本机体验时，也可以直接双击 `Start-Dubhe.cmd`，它会启动 Core 并打开桌面端。

如果 Windows 安装包显示 `(尚未生成)`，请先由开发者在 `apps/theia-desktop` 生成 setup/portable；本机体检会提示具体命令。

### Android

1. 测试体验优先安装 `Android 调试 APK`。
2. 正式分发使用 `Android release AAB`，但仍需要签名、包名、图标、隐私政策和商店资料。
3. 真机连接前优先双击 `Connect-Dubhe-Mobile.cmd`，扫码或填写连接卡里的 `http://192.168.x.x:8000` 地址；只需要局域网启动日志时再双击 `Start-Dubhe-LAN.cmd`。

Android 模拟器通常使用：

```text
http://10.0.2.2:8000
```

### macOS

当前 Windows 本机不能生成 macOS 安装包。需要在 macOS runner 或真实 Mac 上启用：

```text
{{CI_THEIA_TEMPLATE}}
```

生成未签名 dmg/zip 后，正式分发还需要 Apple Developer 账号、签名证书、公证、图标和更新渠道。

### iOS

当前 Windows 本机不能生成 iOS 安装包。需要在 macOS runner 或真实 Mac 上启用：

```text
{{CI_MOBILE_TEMPLATE}}
```

生成 no-codesign app bundle 只适合验证构建链路；真机/TestFlight/App Store 还需要 Bundle ID、Team ID、签名证书、Provisioning Profile、隐私清单和商店资料。

## 第一次使用顺序

1. 双击 `Configure-Dubhe.cmd`，按中文向导填写 AI 模型和授权新闻源 key；不知道的项目直接回车即可。
2. 需要动态登录验证码时，双击 `Setup-Dubhe-MFA.cmd`，用认证器 App 扫码；普通本地烟测可继续使用默认占位验证码。
3. 双击 `Start-Dubhe.cmd`，启动 Core 和桌面端。
4. 双击 `Accept-Dubhe.cmd` 跑本机完整验收，确认体检、新闻、AI、策略、回测、纸面交易和同步闭环可用。
5. 如需单独定位环境问题，双击 `Check-Dubhe.cmd`，确认安装包、配置和 Core 状态。
6. 填完真实 AI/新闻源 key 后，双击 `Test-Dubhe-Services.cmd` 做 live 外部服务体检。
7. 双击 `Check-Dubhe-Production.cmd` 查看商业生产上线阻断项。
8. 双击 `Export-Dubhe-Production-Pack.cmd` 导出阻断项、负责人和供应商/账号材料清单。
9. 需要把当前产物交给本机用户试用时，双击 `Build-Dubhe-User-Kit.cmd`。
10. 如果已经从 GitHub Actions 下载到 macOS/iOS/Android/Windows 构建产物，先放入 `.dubhe-run\ci-artifacts`，再双击 `Import-Dubhe-CI-Artifacts.cmd`。
11. 准备发出 ZIP 前，先双击 `Prepare-Dubhe-Delivery.cmd`，再双击 `Verify-Dubhe-Delivery.cmd`。
12. 需要给负责人或测试人员看当前交付状态时，双击 `Export-Dubhe-Release-Evidence.cmd`。
13. 桌面端登录本地账号，查看 “首次使用清单”。
14. 如需手机/平板，双击 `Connect-Dubhe-Mobile.cmd`，扫码或填写手机连接卡里的 Core 地址。
15. 需要单独重跑主链路时，双击 `Smoke-Dubhe.cmd`。

## 跨端数据互通

本地体验阶段，Windows 桌面端、Android 手机和模拟器通过同一个 Dubhe Core 同步数据；只要使用同一个账号，AI 对话、策略草案、回测结果、纸面组合和审批状态会通过工作区同步接口互相恢复。

生产阶段仍需要把 Core 部署为云同步服务，并补齐 OIDC/MFA、PostgreSQL/TimescaleDB、Redis、对象存储、推送、备份和审计策略。当前本地安装包只是体验和开发闭环，不代表已经满足真实商业发布。

## 重要边界

- 实盘交易默认关闭；AI 不能直接下真实订单。
- A 股、港股、美股权威新闻 API 需要签订授权合同并填写对应 key。
- 未签名安装包适合内部测试，不适合直接面向普通用户分发。
- 真实资金接入前必须完成券商适配、权限审批、风控限额、审计留痕和紧急停止流程。
