# Dubhe

Dubhe 是一套面向只会中文的非技术投资用户的 AI 投资研究与量化交易工作台。它将类 IDE 桌面工作区、移动端伴随应用、授权金融新闻 API、AI 分析、策略回测、模拟交易和受控实盘流程组合在一起，让不会编程、不会量化的用户也能通过中文自然语言完成新闻分析、策略制作、回测验证和交易审批。

本仓库从计划书和集成蓝图开始。项目策略是尽量缝合成熟开源系统，将自研代码限制在数据适配、任务编排、用户体验、权限控制和风控边界上，降低从零实现核心量化、AI 和交易系统带来的 bug 风险。

## 产品形态

- 桌面端：Windows 和 macOS，基于 Eclipse Theia Desktop。
- 移动端：iOS 和 Android，基于 Flutter。
- 云端同步：自建后端，使用 PostgreSQL/TimescaleDB、Redis、S3/MinIO、WebSocket、REST/gRPC、APNs 和 FCM。
- 量化引擎：QuantConnect LEAN。
- 金融数据层：OpenBB 加授权市场/新闻数据供应商。
- AI 研究层：Qlib、FinGPT/FinBERT 和 OpenAI-compatible / 本地 LLM tool-calling。
- 小白策略制作：Blockly 可视化策略积木，高级代码编辑保留在桌面工作区。

## 核心文档

- [完整计划书](docs/PROJECT_PLAN.md)
- [模拟测试兜底链](docs/SIMULATION_TEST_CHAIN.md)
- [总体架构](docs/ARCHITECTURE.md)
- [数据源规划](docs/DATA_SOURCES.md)
- [参考书](docs/REFERENCE_BOOK.md)
- [ADR-0001：产品架构决策](docs/adr/0001-product-architecture.md)

## 当前可运行模块

- [Dubhe Core](services/core/README.md)：FastAPI 后端最小骨架，包含本地账号登录、角色分配、审计日志、设备同步、OpenAI-compatible AI 分析师中文对话与跨端问答同步、新闻分析、策略草案、回测、风控审批、kill switch、纸面订单、模拟券商回报和纸面组合入账。
- [Dubhe Desktop](apps/desktop/README.md)：React + Vite 中文桌面工作台前端雏形，包含本地登录页、类 IDE 研究工作区、实时同步、审批/急停面板、账号权限、审计日志、纸面交易和纸面组合展示。
- [Dubhe Theia Desktop](apps/theia-desktop/README.md)：Eclipse Theia Desktop 正式壳骨架，包含 Electron target application package 和 Dubhe Theia extension；当前已接入可输入、可审计、可跨端恢复的中文 AI 分析师对话，并通过本地 Theia build 和未签名 Windows setup/portable 包验证。
- [Dubhe Companion](apps/mobile/README.md)：Flutter iOS/Android 移动端源码骨架，包含本地账号登录、Core 地址保存、新闻雷达、中文 AI 影响分析、可同步 AI 分析师对话、策略草案、回测、纸面交易、纸面组合和审批操作入口；当前已生成 Android/iOS 平台工程，并通过本地 `flutter analyze`、`flutter test`、Android debug APK 和 release appbundle 构建验证。
- [Dubhe Core OpenAPI 合约](packages/contracts/openapi/dubhe-core.json)：桌面端、移动端和后续 SDK 的统一接口契约。
- [Dubhe Sync Backend](docs/SYNC_BACKEND.md)：自建云同步的设备注册、工作区快照、自选股和同步事件最小闭环。
- [Core API CI 模板](docs/ci/core.yml)：当前作为模板保存；激活时复制到 `.github/workflows/core.yml`。
- [Theia Desktop Packages CI 模板](docs/ci/theia-desktop.yml)：激活后 GitHub Actions 可在 `main` 变更或手动触发时构建 Windows setup/portable，以及 macOS arm64/x64 dmg/zip 未签名产物。
- [Mobile Companion Packages CI 模板](docs/ci/mobile.yml)：激活后 GitHub Actions 可生成 Android debug APK 与 iOS no-codesign app bundle。

快速启动：

不会命令行的 Windows 用户可以直接双击仓库根目录里的：

- `Start-Dubhe.cmd`：启动 Dubhe Core，并打开 Dubhe 桌面端。
- `Configure-Dubhe.cmd`：创建并打开本机配置文件，用来填写 AI 模型、新闻源和数据库路径等运行参数。
- `Check-Dubhe.cmd`：只做本机体检，不启动服务。
- `Stop-Dubhe-Core.cmd`：停止本机 Dubhe Core。

也可以把这些入口安装到桌面和开始菜单：

```powershell
cd D:\github\dubhe-main
.\scripts\install-windows-shortcuts.ps1
```

安装后会出现 `Start Dubhe`、`Configure Dubhe`、`Check Dubhe`、`Stop Dubhe Core` 四个快捷方式；脚本源码保持纯 ASCII，以避免 Windows PowerShell 5 在中文编码下解析失败。

第一次接入真实 AI 模型或授权新闻源时，建议先双击 `Configure-Dubhe.cmd`。它会从 `config/dubhe.local.env.example` 创建只保存在本机的 `config/dubhe.local.env`，用记事本打开后，把需要启用的行前面的 `# ` 删除并填写自己的 key。保存后重新启动 Dubhe，`start-local-dubhe.ps1`、`services/core/scripts/run.ps1` 和体检脚本都会自动读取这个本地配置文件；真实 key 已加入 `.gitignore`，不会被提交。

管理员登录桌面端或移动端后，也可以在“系统状态 / 数据源配置”里直接保存本地运行配置。客户端只显示脱敏状态，真实 API key 不会从 Core 回传；保存后模型和新闻源配置会立即应用到当前 Core，数据库路径变更仍需重启 Core。

桌面端和移动端都会显示“首次使用清单”，把连接 Core、创建/登录账号、配置模型与新闻源、刷新新闻、AI 分析、跨端同步、纸面交易和实盘风控边界拆成可检查步骤，并给出下一步操作。

命令行启动方式：

```powershell
cd D:\github\dubhe-main
.\scripts\check-local-dubhe.ps1
.\scripts\start-local-dubhe.ps1 -RunCheck
```

`check-local-dubhe.ps1` 会用中文检查 Core、桌面端、移动端工具链、新闻源配置、纸面/实盘交易开关和本地安装包状态；它只读取环境，不会修改系统。`start-local-dubhe.ps1 -RunCheck` 会先启动 Core，再输出同一份体检结果，然后打开已打包的 Dubhe 桌面端；如果没有打包产物，会回退到 Theia 开发启动。

如果体检提示 `/v1/system/status` 不可用，通常是旧 Core 进程还占着 8000 端口。可以显式重启 Core：

```powershell
cd D:\github\dubhe-main
.\scripts\start-local-dubhe.ps1 -RestartCore -RunCheck
```

如果 8000 端口被其他程序占用且脚本无法确认它是 Dubhe Core，可以改用备用端口：

```powershell
cd D:\github\dubhe-main
.\scripts\start-local-dubhe.ps1 -CorePort 8001 -RunCheck
```

此时在桌面端左侧“Core 连接”里把地址改为 `http://127.0.0.1:8001` 并保存。

只停止某个端口上的 Dubhe Core：

```powershell
cd D:\github\dubhe-main
.\scripts\start-local-dubhe.ps1 -CorePort 8001 -StopCoreOnly
```

开发期手动启动 Core：

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\setup.ps1
.\scripts\run.ps1
```

手动指定端口：

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\run.ps1 -Port 8001
```

Windows 本地一键启动（先启动 Core，再打开 Theia 桌面壳；如果没有打包产物，会回退到 Theia 开发启动）：

```powershell
cd D:\github\dubhe-main
.\scripts\start-local-dubhe.ps1
```

本地运行日志会写入：

```text
D:\github\dubhe-main\.dubhe-run\
```

测试：

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\test.ps1
```

移动端源码检查需要先安装 Flutter SDK：

```powershell
cd D:\github\dubhe-main\apps\mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8000
```

Theia Desktop 壳需要 Node LTS 与 Yarn 1：

```powershell
cd D:\github\dubhe-main\apps\theia-desktop
corepack enable
corepack prepare yarn@1.22.22 --activate
yarn install
yarn build
yarn start
```

如果本机 Node 不带 `corepack`，先执行 `npm install --global yarn@1.22.22`。

## 安全原则

AI 可以分析、解释、起草和提出建议，但不能直接发起实盘订单。所有实盘订单都必须经过确定性风控检查、审计日志记录和用户可控的审批规则。
