# Dubhe

Dubhe 是一套面向只会中文的非技术投资用户的 AI 投资研究与量化交易工作台。它将类 IDE 桌面工作区、移动端伴随应用、授权金融新闻 API、AI 分析、策略回测、模拟交易和受控实盘流程组合在一起，让不会编程、不会量化的用户也能通过中文自然语言完成新闻分析、策略制作、回测验证和交易审批。

本仓库从计划书和集成蓝图开始。项目策略是尽量缝合成熟开源系统，将自研代码限制在数据适配、任务编排、用户体验、权限控制和风控边界上，降低从零实现核心量化、AI 和交易系统带来的 bug 风险。

## 产品形态

- 桌面端：Windows 和 macOS，基于 Eclipse Theia Desktop。
- 移动端：iOS 和 Android，基于 Flutter。
- 云端同步：自建后端，使用 PostgreSQL/TimescaleDB、Redis、S3/MinIO、WebSocket、REST/gRPC、APNs 和 FCM。
- 量化引擎：QuantConnect LEAN。
- 金融数据层：OpenBB 加授权市场/新闻数据供应商。
- AI 研究层：Qlib、FinGPT/FinBERT 和 LLM tool-calling。
- 小白策略制作：Blockly 可视化策略积木，高级代码编辑保留在桌面工作区。

## 核心文档

- [完整计划书](docs/PROJECT_PLAN.md)
- [模拟测试兜底链](docs/SIMULATION_TEST_CHAIN.md)
- [总体架构](docs/ARCHITECTURE.md)
- [数据源规划](docs/DATA_SOURCES.md)
- [参考书](docs/REFERENCE_BOOK.md)
- [ADR-0001：产品架构决策](docs/adr/0001-product-architecture.md)

## 当前可运行模块

- [Dubhe Core](services/core/README.md)：FastAPI 后端最小骨架，包含本地账号登录、角色分配、审计日志、设备同步、新闻分析、策略草案、回测、风控审批、kill switch、纸面订单、模拟券商回报和纸面组合入账。
- [Dubhe Desktop](apps/desktop/README.md)：React + Vite 中文桌面工作台前端雏形，包含本地登录页、类 IDE 研究工作区、实时同步、审批/急停面板、账号权限、审计日志、纸面交易和纸面组合展示。
- [Dubhe Theia Desktop](apps/theia-desktop/README.md)：Eclipse Theia Desktop 正式壳骨架，包含 Electron target application package 和 Dubhe Theia extension；当前已通过本地 Theia build 和未签名 Windows setup/portable 包验证，会承载并逐步替换 React/Vite 原型。
- [Dubhe Companion](apps/mobile/README.md)：Flutter iOS/Android 移动端源码骨架，包含本地账号登录、新闻雷达、中文 AI 影响分析、纸面组合和审批操作入口；当前已生成 Android/iOS 平台工程，并通过本地 `flutter analyze`、`flutter test` 和 Android debug APK 构建验证。
- [Dubhe Core OpenAPI 合约](packages/contracts/openapi/dubhe-core.json)：桌面端、移动端和后续 SDK 的统一接口契约。
- [Dubhe Sync Backend](docs/SYNC_BACKEND.md)：自建云同步的设备注册、工作区快照、自选股和同步事件最小闭环。
- [Core API CI 模板](docs/ci/core.yml)：当前作为模板保存；激活时复制到 `.github/workflows/core.yml`。
- [Theia Desktop Packages CI 模板](docs/ci/theia-desktop.yml)：激活后 GitHub Actions 可在 `main` 变更或手动触发时构建 Windows setup/portable，以及 macOS arm64/x64 dmg/zip 未签名产物。
- [Mobile Companion Packages CI 模板](docs/ci/mobile.yml)：激活后 GitHub Actions 可生成 Android debug APK 与 iOS no-codesign app bundle。

快速启动：

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\setup.ps1
.\scripts\run.ps1
```

Windows 本地一键启动（先启动 Core，再打开 Theia 桌面壳；如果没有打包产物，会回退到 Theia 开发启动）：

```powershell
cd D:\github\dubhe-main
.\scripts\start-local-dubhe.ps1
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
flutter build apk --debug --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8019
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
