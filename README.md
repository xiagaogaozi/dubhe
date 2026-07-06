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

- [Dubhe Core](services/core/README.md)：FastAPI 后端最小骨架，包含本地账号登录、角色分配、审计日志、设备同步、OpenAI-compatible AI 分析师中文对话与跨端问答同步、新闻分析、策略模板目录、策略草案、回测、风控审批、kill switch、纸面订单、模拟券商回报和纸面组合入账。
- [Dubhe Desktop](apps/desktop/README.md)：React + Vite 中文桌面工作台前端雏形，包含本地登录页、类 IDE 研究工作区、实时同步、审批/急停面板、账号权限、审计日志、纸面交易和纸面组合展示。
- [Dubhe Theia Desktop](apps/theia-desktop/README.md)：Eclipse Theia Desktop 正式壳骨架，包含 Electron target application package 和 Dubhe Theia extension；当前已接入可输入、可审计、可跨端恢复的中文 AI 分析师对话、Core 成熟策略模板货架和 Blockly 策略工坊，并通过本地 Theia build 和未签名 Windows setup/portable 包验证。
- [Dubhe Companion](apps/mobile/README.md)：Flutter iOS/Android 移动端源码骨架，包含本地账号登录、Core 地址保存、新闻雷达、中文 AI 影响分析、成熟策略模板、可同步 AI 分析师对话、策略草案、回测、纸面交易、纸面组合和审批操作入口；当前已生成 Android/iOS 平台工程，并通过本地 `flutter analyze`、`flutter test`、Android debug APK 和 release appbundle 构建验证。
- [Dubhe Core OpenAPI 合约](packages/contracts/openapi/dubhe-core.json)：桌面端、移动端和后续 SDK 的统一接口契约。
- [Dubhe Sync Backend](docs/SYNC_BACKEND.md)：自建云同步的设备注册、工作区快照、自选股和同步事件最小闭环。
- [Core API CI 模板](docs/ci/core.yml)：当前作为模板保存；激活时复制到 `.github/workflows/core.yml`。
- [Theia Desktop Packages CI 模板](docs/ci/theia-desktop.yml)：激活后 GitHub Actions 可在 `main` 变更或手动触发时构建 Windows setup/portable，以及 macOS arm64/x64 dmg/zip 未签名产物。
- [Mobile Companion Packages CI 模板](docs/ci/mobile.yml)：激活后 GitHub Actions 可生成 Android debug APK 与 iOS no-codesign app bundle。

快速启动：

不会命令行的 Windows 用户可以直接双击仓库根目录里的：

- `Start-Dubhe.cmd`：启动 Dubhe Core，并打开 Dubhe 桌面端。
- `Start-Dubhe-LAN.cmd`：重启 Dubhe Core 为局域网模式，并显示手机/平板可填写的 Core 地址。
- `Connect-Dubhe-Mobile.cmd`：重启局域网 Core，打开手机连接卡，显示 Core 地址、Android APK 路径，并在可用时生成二维码。
- `Build-Dubhe-User-Kit.cmd`：生成本机用户交付包，把 Windows/Android 安装包、中文向导、体检报告、SHA256 校验清单、安装包索引和本机双击入口集中到 `.dubhe-run\user-kits`。
- `Prepare-Dubhe-Delivery.cmd`：生成最新交付 ZIP，并把 ZIP 路径、大小和 SHA256 固定写入 `.dubhe-run\LATEST-DUBHE-DELIVERY.txt`。
- `Verify-Dubhe-Delivery.cmd`：验证最新交付 ZIP 的 SHA256、关键安装包、包内索引和逐文件校验清单。
- `Open-Dubhe-Install-Guide.cmd`：打开 Windows、macOS、iOS、Android 四端安装与连接总向导，自动显示本机安装包路径和构建缺口。
- `Open-Dubhe-Mobile-Guide.cmd`：打开手机安装与连接向导，自动显示本机 APK 路径和可填写的局域网 Core 地址。
- `Configure-Dubhe.cmd`：创建并打开本机配置文件，用来填写 AI 模型、新闻源和数据库路径等运行参数。
- `Setup-Dubhe-MFA.cmd`：生成本机 TOTP 动态验证码二维码和密钥，写入 `config\dubhe.local.env`，用于注册/登录时替代固定占位验证码。
- `Accept-Dubhe.cmd`：启动 Core 后跑本机完整验收，覆盖体检、主链路 smoke 和外部 AI/新闻源状态。
- `Verify-Dubhe-Audit.cmd`：验证本地 SQLite 审计日志哈希链是否完整，报告会写入 `.dubhe-run\audit-chain-verification.txt/json`。
- `Check-Dubhe.cmd`：只做本机体检，不启动服务。
- `Smoke-Dubhe.cmd`：跑新闻、AI、策略、回测、纸面交易和同步闭环主链路烟测。
- `Test-Dubhe-Services.cmd`：对已配置的 AI 模型、Finnhub、Alpha Vantage、SEC EDGAR 和 GDELT 做外部服务 live 体检。
- `Check-Dubhe-Production.cmd`：检查商业生产上线门禁，包括授权新闻、云同步、身份、审计、券商、签名和四端发布。
- `Export-Dubhe-Production-Pack.cmd`：导出中文生产上线补齐包，把阻断项、负责人、供应商/账号材料和下一步集中到 `.dubhe-run\production-pack`。
- `Stop-Dubhe-Core.cmd`：停止本机 Dubhe Core。

也可以把这些入口安装到桌面和开始菜单：

```powershell
cd D:\github\dubhe-main
.\scripts\install-windows-shortcuts.ps1
```

安装后会出现 `Start Dubhe`、`Start Dubhe LAN`、`Connect Dubhe Mobile`、`Build Dubhe User Kit`、`Prepare Dubhe Delivery`、`Verify Dubhe Delivery`、`Dubhe Mobile Guide`、`Dubhe Install Guide`、`Configure Dubhe`、`Setup Dubhe MFA`、`Accept Dubhe`、`Verify Dubhe Audit`、`Check Dubhe`、`Smoke Dubhe`、`Test Dubhe Services`、`Check Dubhe Production`、`Export Dubhe Production Pack`、`Stop Dubhe Core` 十八个快捷方式；双击入口和快捷方式安装脚本保持纯 ASCII，以避免 Windows PowerShell 5 在中文编码下解析失败。

第一次接入真实 AI 模型或授权新闻源时，建议先双击 `Configure-Dubhe.cmd`。它会用中文向导询问模型名、AI Key、新闻源 Key 和 SEC 联系方式；不知道的项目直接回车即可，真实 key 只会写入本机 `config/dubhe.local.env`。向导结束后仍会打开记事本，方便高级用户复查或手动编辑。保存后重新启动 Dubhe，`start-local-dubhe.ps1`、`services/core/scripts/run.ps1` 和体检脚本都会自动读取这个本地配置文件；真实 key 已加入 `.gitignore`，不会被提交。

默认本地 MFA 仍是固定占位验证码 `000000`，方便首次烟测。需要更接近真实登录时，双击 `Setup-Dubhe-MFA.cmd`，用 Microsoft Authenticator、Google Authenticator、1Password 等认证器 App 扫码，然后重启 Core；之后账号注册/登录会使用 6 位动态验证码。这个能力只是本机兜底，不等同于生产级 OIDC、正式 MFA、刷新令牌和集中身份审计。

如果要做券商沙盒 UAT，可以在 `Configure-Dubhe.cmd` 里把 `DUBHE_PAPER_BROKER` 设为 `alpaca`，并填写 Alpaca paper Key；默认仍是本地模拟 broker，不会发送真实订单。券商适配边界见 [Broker Adapters](docs/BROKER_ADAPTERS.md)。

管理员登录桌面端或移动端后，也可以在“系统状态 / 数据源配置”里直接保存本地运行配置。客户端只显示脱敏状态，真实 API key 不会从 Core 回传；保存后模型和新闻源配置会立即应用到当前 Core，数据库路径变更仍需重启 Core。

把这台电脑交给非技术用户试用前，可以双击 `Accept-Dubhe.cmd`。它会自动确保 Core 运行，依次跑本机体检、本地审计链验证、主链路 smoke 和外部 AI/新闻源状态检查，并把结果写入 `.dubhe-run\local-acceptance.txt` 和 `.dubhe-run\local-acceptance.json`。没有填写授权 key 时，验收会显示“需配置”，但不会把本地演示链路判为失败；需要强制外部服务全部通过时，可用命令行加 `-RequireExternalServices`。

需要单独检查审计日志是否被本机改写时，可以双击 `Verify-Dubhe-Audit.cmd`。它会调用 `/v1/audit/chain/verify` 校验每条审计记录的递增序号、上一条哈希和本条 SHA-256 摘要；如果当前账号没有管理员或风控管理员权限，会提示换有权限账号。这个能力是本地防篡改兜底，不等同于生产级 WORM、对象锁或外部不可变审计服务。

填写真实 AI 模型或授权新闻源 key 后，可以双击 `Test-Dubhe-Services.cmd` 做 live 外部服务体检。它会通过 Dubhe Core 对已配置服务发起最小请求，输出每个服务是 `OK`、`跳过` 还是 `失败`；live 检查可能产生极少量模型调用或供应商请求额度。

准备给真实用户或商业场景发布前，双击 `Check-Dubhe-Production.cmd`。它比本地体检和 smoke 更严格，会把授权新闻合同、A/HK/US/全球宏观数据覆盖、生产身份、云同步、不可篡改审计、真实券商、macOS/iOS 签名和商店发布列为门禁；当前阶段预期会失败，直到这些阻断项逐项补齐。

需要把这些阻断项交给商务、运维、后端、风控或发布负责人处理时，双击 `Export-Dubhe-Production-Pack.cmd`。它会生成 `.dubhe-run\production-pack`，其中包含 `production-action-plan.md`、`vendor-and-account-checklist.md`、`production-blockers.csv` 和原始 `production-readiness.json`，用于逐项补齐生产上线材料。

给这台电脑上的非技术用户试用时，可以双击 `Build-Dubhe-User-Kit.cmd`。它会生成 `.dubhe-run\user-kits\Dubhe-User-Kit-...`，复制当前 Windows setup/portable、Android APK/AAB、中文向导、手机连接卡、体检/验收报告，并生成指向当前仓库的“本机启动/配置/验收/手机连接/体检”双击入口；这仍是内测交付包，不等同于签名生产安装器。

准备把 ZIP 发出去前，先双击 `Prepare-Dubhe-Delivery.cmd`，再双击 `Verify-Dubhe-Delivery.cmd`。验证会重新计算 ZIP 的 SHA256，检查 Windows setup/portable、Android APK/AAB、安装包索引、校验清单和关键报告是否都在包内，并逐项验证 `CHECKSUMS-SHA256.txt` 里的文件哈希；报告会写入 `.dubhe-run\delivery-verification.txt/json`。

如果要验证“Windows / macOS / iOS / Android 四端安装包都已进入交付 ZIP”，请用命令行运行 `.\scripts\verify-delivery-pack.ps1 -RequireAllPlatforms`；当前 Windows 本机内测包默认只强制 Windows/Android，macOS/iOS 会作为提示项，直到 macOS runner 产物被下载并放入对应目录。

桌面端和移动端都会显示“首次使用清单”，把连接 Core、创建/登录账号、配置模型与新闻源、刷新新闻、AI 分析、跨端同步、纸面交易和实盘风控边界拆成可检查步骤，并提供可点击的下一步操作。

命令行启动方式：

```powershell
cd D:\github\dubhe-main
.\scripts\check-local-dubhe.ps1
.\scripts\run-local-acceptance.ps1
.\scripts\build-user-kit.ps1 -NoZip
.\scripts\prepare-delivery.ps1
.\scripts\verify-delivery-pack.ps1
.\scripts\verify-audit-chain.ps1
.\scripts\test-external-services.ps1 -Live
.\scripts\check-production-readiness.ps1
.\scripts\export-production-pack.ps1
.\scripts\start-local-dubhe.ps1 -RunCheck
.\scripts\smoke-core-workflow.ps1
```

`run-local-acceptance.ps1` 会自动启动 Core，然后串起本机体检、本地审计链验证、主链路 smoke 和外部服务状态检查，适合交给不会命令行的用户前做一次“这台电脑能不能用”的兜底验收；报告会写入 `.dubhe-run\local-acceptance.txt` 和 `.dubhe-run\local-acceptance.json`。

`build-user-kit.ps1` 默认生成的 ZIP 会排除 Windows 已解包目录 `win-unpacked`，优先分发 setup/portable、Android APK/AAB、说明、报告和校验清单；未压缩的用户包目录里仍保留 `win-unpacked`，方便本机兜底试运行。确实需要把已解包目录也压进 ZIP 时，可加 `-IncludeUnpackedInZip`。

`prepare-delivery.ps1` 会调用同一个用户包构建器，生成最新交付 ZIP，并把固定摘要写到 `.dubhe-run\LATEST-DUBHE-DELIVERY.txt` 和 `.dubhe-run\latest-delivery.json`；双击 `Prepare-Dubhe-Delivery.cmd` 等价于给非技术交付前做一次“生成最终安装包路径和校验值”的收口。

`verify-delivery-pack.ps1` 会读取 `.dubhe-run\latest-delivery.json`，验证 ZIP 文件存在、大小和 SHA256 与摘要一致，检查关键安装包和说明文件，并按 `CHECKSUMS-SHA256.txt` 逐个重新计算包内文件哈希；失败时返回非零退出码，适合交付前兜底。

`verify-delivery-pack.ps1 -RequireAllPlatforms` 会额外要求 ZIP 内包含 `05-macOS` 里的 `.dmg/.zip` 和 `06-iOS` 里的 `Runner.app/.ipa`，用于最终四端交付门禁。

`check-local-dubhe.ps1` 会用中文检查 Core、桌面端、移动端工具链、新闻源配置、纸面/实盘交易开关、本地审计链和本地安装包状态；它会列出 Windows setup/portable、Android APK/AAB 以及 macOS/iOS 的构建缺口，只读取环境，不会修改系统。`start-local-dubhe.ps1 -RunCheck` 会先启动 Core，再输出同一份体检结果，然后打开已打包的 Dubhe 桌面端；如果没有打包产物，会回退到 Theia 开发启动。

`verify-audit-chain.ps1` 会读取 `/v1/audit/chain/verify`，验证本地 SQLite 审计日志的序号和 SHA-256 哈希链；验证失败会返回非零退出码，并把报告写入 `.dubhe-run\audit-chain-verification.txt` 和 `.dubhe-run\audit-chain-verification.json`。

`test-external-services.ps1 -Live` 会读取 `/v1/system/external-checks?live=true`，验证 AI 模型、Finnhub、Alpha Vantage、SEC EDGAR、GDELT 和 Alpaca paper 券商沙盒的连接状态；未配置的服务会显示跳过，不会泄露任何 key。

`check-production-readiness.ps1` 会读取 `/v1/system/production-readiness`，输出生产门禁项；只要还有阻断项就返回非零退出码，后续可以直接接入 CI 或发布流程。

`export-production-pack.ps1` 会读取同一份生产门禁，生成中文行动计划、供应商/账号清单、CSV 表格和 JSON 原始证据。它的作用是推动补齐生产缺口，不代表生产门禁已通过。

`build-user-kit.ps1` 会把当前可用安装产物和中文说明集中到 `.dubhe-run\user-kits`，并生成 `manifest.json` 记录文件大小和 SHA256。默认会同时生成 zip；开发验证时可加 `-NoZip` 避免压缩大文件。

`smoke-core-workflow.ps1` 会在已运行的 Core 上执行主链路烟测：注册本地账号、读取首次使用清单、刷新 fixture 新闻、生成中文分析、询问 AI 分析师、生成策略草案、运行 deterministic replay 回测、提交 1 股纸面订单、验证组合入账和工作区同步。报告会写入 `.dubhe-run\smoke-core-workflow.json`；不会连接真实券商或发送真实订单。

桌面端右侧“主链路烟测”和移动端“系统状态”都会读取 `/v1/system/smoke-report`，让用户直接看到最近一次 smoke 是否通过。

四端安装包路径和缺口可以先双击 `Open-Dubhe-Install-Guide.cmd` 查看；它会生成 `.dubhe-run\install-guide.txt`，把 Windows setup/portable、Android APK/AAB、macOS/iOS 待构建项和局域网 Core 地址放在同一份中文说明里。手机真机优先双击 `Connect-Dubhe-Mobile.cmd`，它会重启局域网 Core、复制首选 Core 地址，并打开 `.dubhe-run\mobile-connect.html` 手机连接卡；能生成二维码时，手机可直接扫码，不能生成时也会显示可手动填写的 `http://192.168.x.x:8000` 地址。如果 Windows 防火墙弹窗出现，请允许专用网络访问。只想看文字版步骤时，再双击 `Open-Dubhe-Mobile-Guide.cmd`。Android 模拟器仍可使用 `http://10.0.2.2:8000`。

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
