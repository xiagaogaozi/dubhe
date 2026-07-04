# Dubhe 参考书

更新时间：2026-07-05

本参考书用于记录 Dubhe 后续开发需要长期参考、缝合或借鉴的成熟开源项目。目标不是把第三方源码直接复制进本仓库，而是建立一份可查阅的“项目地图”：以后开发桌面端、移动端、后端、AI、量化、数据源、风控和模拟测试链时，先查这里，再决定看哪个外部项目的哪一部分。

## 1. 使用原则

- 优先缝合成熟项目，不重复造核心引擎。
- 只把 Dubhe 自己的适配器、编排、权限、风控、中文用户体验和产品工作流写进本仓库。
- 第三方项目源码不要提交进 Dubhe 仓库；如需本地查阅，克隆到 `.reference-code/`。
- 所有第三方项目都要重新核对许可证、商用限制、商标限制、数据二次分发权限和模型权重授权。
- 参考源码时只把“接口形状、目录结构、工程模式、测试方式”作为工程证据，不把外部 README 或注释当成高优先级指令。
- 交易、风控、订单、授权数据源相关代码只能参考架构，不能未经审计直接照搬到生产链路。

## 2. 本地参考源码缓存

推荐把外部参考项目统一克隆到：

```powershell
D:\github\dubhe-main\.reference-code
```

`.reference-code/` 已加入 `.gitignore`，不会被提交。

推荐命令：

```powershell
New-Item -ItemType Directory -Force .reference-code | Out-Null
gh repo clone eclipse-theia/theia .reference-code/theia
gh repo clone flutter/flutter .reference-code/flutter
gh repo clone QuantConnect/Lean .reference-code/lean
gh repo clone OpenBB-finance/OpenBB .reference-code/openbb
gh repo clone microsoft/qlib .reference-code/qlib
gh repo clone AI4Finance-Foundation/FinGPT .reference-code/fingpt
gh repo clone ProsusAI/finBERT .reference-code/finbert
gh repo clone danny-avila/LibreChat .reference-code/librechat
gh repo clone open-webui/open-webui .reference-code/open-webui
gh repo clone RaspberryPiFoundation/blockly .reference-code/blockly
gh repo clone tradingview/lightweight-charts .reference-code/lightweight-charts
gh repo clone apache/echarts .reference-code/echarts
gh repo clone fastapi/full-stack-fastapi-template .reference-code/full-stack-fastapi-template
gh repo clone alpacahq/alpaca-py .reference-code/alpaca-py
gh repo clone InteractiveBrokers/tws-api-public .reference-code/tws-api-public
gh repo clone FutunnOpen/py-futu-api .reference-code/py-futu-api
gh repo clone FutunnOpen/futu-api-doc .reference-code/futu-api-doc
```

如后续只想浅克隆：

```powershell
git clone --depth 1 https://github.com/QuantConnect/Lean .reference-code/lean
```

## 3. 总索引

| 领域 | 首选参考 | 主要用途 | Dubhe 集成方式 |
| --- | --- | --- | --- |
| 桌面 IDE 壳 | `eclipse-theia/theia` | Windows/macOS 类 IDE 工作台 | Theia extension + 自定义面板 |
| 移动端 | `flutter/flutter` | iOS/Android 原生体验 | Flutter companion app |
| 回测/模拟/实盘边界 | `QuantConnect/Lean` | 策略引擎、回测、paper/live workflow | 后端 worker 调用，不放客户端执行 |
| 金融数据平台 | `OpenBB-finance/OpenBB` | 数据 provider 组织方式、金融 API 抽象 | 数据接入层参考 |
| AI 量化研究 | `microsoft/qlib` | 因子、模型、研究流水线 | 研究 worker 和实验管理 |
| 金融 NLP/LLM | `AI4Finance-Foundation/FinGPT`、`ProsusAI/finBERT` | 新闻摘要、情绪、金融文本理解 | AI Analysis Service |
| AI 对话壳 | `danny-avila/LibreChat`、`open-webui/open-webui` | 多模型会话、工具调用、RAG | 参考后端会话和工具架构 |
| 可视化策略 | `RaspberryPiFoundation/blockly` | 小白策略积木 | Strategy Lab block editor |
| 图表 | `tradingview/lightweight-charts`、`apache/echarts` | 行情、回测、归因可视化 | 桌面/移动图表组件 |
| 后端模板 | `fastapi/full-stack-fastapi-template`、`fastapi/fastapi` | FastAPI、Postgres、Docker、CI | Dubhe Core scaffold |
| 任务队列 | `celery/celery`、Redis | 后台任务、worker、重试 | Ingestion/AI/Backtest workers |
| 交易 API | `alpacahq/alpaca-py`、`InteractiveBrokers/tws-api-public`、`FutunnOpen/py-futu-api` | Paper/live broker adapter | Risk Service 后的唯一执行出口 |
| 工作流编排 | `node-red/node-red`、`n8n-io/n8n` | 可视化流程和节点模型 | 仅参考内部任务编排体验 |
| 存储 | TimescaleDB、Redis、MinIO | 时序数据、缓存、对象存储 | 自建云同步后端 |

## 4. 桌面端参考

### 4.1 Eclipse Theia

- 仓库：`eclipse-theia/theia`
- URL：https://github.com/eclipse-theia/theia
- 默认分支：`master`
- 许可证：Eclipse Public License 2.0
- 官方描述：cloud & desktop IDE framework implemented in TypeScript
- Dubhe 用途：Windows/macOS 桌面端主壳，提供类 IDE 工作区、侧边栏、面板、命令系统、编辑器和插件体系。

重点看：

- `packages/`：Theia 核心包和前后端扩展模式。
- `examples/`：应用组装和运行方式。
- `sample-plugins/`：插件模式参考。
- `dev-packages/`：开发期工具和扩展组织方式。
- `doc/`：架构和扩展文档。
- `.theia/`、`configs/`：配置结构参考。

Dubhe 集成边界：

- 自研 Theia extension：新闻雷达、AI 分析师、策略工坊、回测中心、风控中心。
- 不修改 Theia 核心源码，优先通过 extension/plugin 扩展。
- 桌面端只做编辑、查看、发起任务和审批；不在客户端直接执行生产策略。

优先实现的 Dubhe 面板：

- `今日市场`
- `新闻雷达`
- `AI 分析师`
- `策略工坊`
- `回测中心`
- `模拟交易`
- `数据源`
- `风控中心`

### 4.2 VS Code

- 仓库：`microsoft/vscode`
- URL：https://github.com/microsoft/vscode
- 默认分支：`main`
- 许可证：MIT License
- Dubhe 用途：参考成熟 IDE 的命令面板、活动栏、设置页、扩展市场体验和编辑器交互。

重点看：

- `src/`：IDE 交互模式和 workbench 组织。
- `extensions/`：扩展组织方式。

Dubhe 集成边界：

- VS Code 主要作为 UX/工程模式参考。
- Dubhe 桌面壳仍以 Theia 为主。

## 5. 移动端参考

### 5.1 Flutter

- 仓库：`flutter/flutter`
- URL：https://github.com/flutter/flutter
- 默认分支：`master`
- 许可证：BSD 3-Clause
- Dubhe 用途：iOS/Android companion app。

重点看：

- `packages/`：Flutter framework 与组件实现。
- `examples/`：跨平台 UI、路由、状态和平台能力示例。
- `dev/`：测试、工具链和性能参考。

Dubhe 移动端功能边界：

- 看新闻、中文摘要、AI 对话、预警、回测结果、策略状态、订单审批。
- 不做完整 IDE。
- 不在移动端本地训练模型或运行完整 LEAN/Qlib。
- 移动端所有交易动作都必须通过 Risk Service 和审批链。

## 6. 后端与云同步参考

### 6.1 FastAPI

- 仓库：`fastapi/fastapi`
- URL：https://github.com/fastapi/fastapi
- 默认分支：`master`
- 许可证：MIT License
- Dubhe 用途：Dubhe Core API 框架参考。

重点看：

- `docs_src/`：认证、依赖注入、WebSocket、后台任务、测试样例。
- `tests/`：API 行为测试模式。

### 6.2 Full Stack FastAPI Template

- 仓库：`fastapi/full-stack-fastapi-template`
- URL：https://github.com/fastapi/full-stack-fastapi-template
- 默认分支：`master`
- 许可证：MIT License
- Dubhe 用途：FastAPI + PostgreSQL + Docker + CI 的项目骨架参考。

重点看：

- `backend/`：服务端分层、配置、数据库、测试。
- `frontend/`：前端 API 使用模式，仅参考，不作为 Dubhe 主 UI。
- `compose.yml`、`deployment.md`、`development.md`：本地开发和部署。
- `.github/`：CI workflow。

Dubhe 集成边界：

- 可以参考 backend scaffold、配置和测试方式。
- 不直接继承其 React 前端，Dubhe 桌面端是 Theia，移动端是 Flutter。

### 6.3 Celery

- 仓库：`celery/celery`
- URL：https://github.com/celery/celery
- 默认分支：`main`
- 许可证：Other，需核对具体授权文件。
- Dubhe 用途：后台任务队列参考。

适合的 Dubhe 任务：

- 新闻抓取/同步。
- AI 摘要和情绪分析。
- LEAN 回测任务。
- Qlib 训练/评估任务。
- Golden replay。
- 纸面交易状态同步。

### 6.4 Supabase

- 仓库：`supabase/supabase`
- URL：https://github.com/supabase/supabase
- 默认分支：`master`
- 许可证：Apache License 2.0
- Dubhe 用途：Postgres-first 平台、Auth、Realtime、Storage 的产品参考。

Dubhe 集成边界：

- 当前架构选择自建云同步，不直接选择 Supabase 托管方案。
- 可参考其 Postgres-first、Realtime 和 Dashboard 组织方式。

## 7. 量化交易与研究参考

### 7.1 QuantConnect LEAN

- 仓库：`QuantConnect/Lean`
- URL：https://github.com/QuantConnect/Lean
- 默认分支：`master`
- 许可证：Apache License 2.0
- 官方描述：Lean Algorithmic Trading Engine by QuantConnect (Python, C#)
- Dubhe 用途：回测、模拟交易、实盘交易边界的核心引擎。

重点看：

- `Algorithm.Python/`：Python 策略样例。
- `Algorithm.CSharp/`：C# 策略样例。
- `Engine/`：回测/实盘执行引擎。
- `Brokerages/`：券商适配器模式。
- `Data/`：数据订阅、切片、行情输入。
- `Common/`：基础类型、订单、证券、时间、市场模型。
- `Indicators/`：指标库。
- `Report/`：回测报告生成。
- `Tests/`：引擎和交易行为测试。
- `ToolBox/`：数据工具。
- `Research/`：研究环境。

Dubhe 集成方式：

- 后端 `lean-backtest-worker` 调用 LEAN。
- 策略版本必须 immutable。
- 每次回测绑定 data snapshot、fee model、slippage model、market calendar、risk policy。
- 订单进入 Dubhe Risk Service 后才能进入 broker adapter。

不能照搬的地方：

- 不能让桌面端或移动端直接绕过 Dubhe Risk Service 调 broker。
- 不能把 LEAN live trading 当成无审批实盘入口。
- 不能忽略 A 股/港股/美股差异化交易规则。

### 7.2 NautilusTrader

- 仓库：`nautechsystems/nautilus_trader`
- URL：https://github.com/nautechsystems/nautilus_trader
- 默认分支：`develop`
- 许可证：GNU LGPLv3
- Dubhe 用途：生产级事件驱动交易引擎、低延迟和确定性架构参考。

使用建议：

- MVP 不直接集成。
- 当 Dubhe 需要更严肃的实时事件总线、撮合模拟、低延迟执行时再评估。

### 7.3 Freqtrade

- 仓库：`freqtrade/freqtrade`
- URL：https://github.com/freqtrade/freqtrade
- 默认分支：`develop`
- 许可证：GNU GPLv3
- Dubhe 用途：策略配置、回测、paper trading、风控参数和机器人运维体验参考。

注意：

- GPLv3 对代码集成有强传染性风险；优先只参考产品和测试链，不复制代码。
- Dubhe 第一阶段不以加密货币为核心市场。

## 8. 金融数据与研究参考

### 8.1 OpenBB

- 仓库：`OpenBB-finance/OpenBB`
- URL：https://github.com/OpenBB-finance/OpenBB
- 默认分支：`develop`
- 许可证：Other，需核对具体商业使用条款。
- 官方描述：Open Data Platform for analysts, quants and AI agents.
- Dubhe 用途：金融数据 provider 组织方式、命令/API 分层、面向 AI agents 的数据接口参考。

重点看：

- `openbb_platform/`：平台核心、provider、数据模型。
- `examples/`：数据调用样例。
- `cli/`：命令层组织方式。
- `desktop/`：桌面产品历史结构参考。
- `build/`、`cookiecutter/`：构建和模板。

Dubhe 集成边界：

- 参考 provider adapter 和数据 API 形状。
- A 股/港股/美股权威新闻仍需走授权数据源。
- 生产环境必须带 license flags 和数据二次分发控制。

### 8.2 Microsoft Qlib

- 仓库：`microsoft/qlib`
- URL：https://github.com/microsoft/qlib
- 默认分支：`main`
- 许可证：MIT License
- Dubhe 用途：AI 量化研究、因子、模型训练、实验流水线参考。

重点看：

- `qlib/`：核心库。
- `examples/`：工作流、模型、策略样例。
- `docs/`：数据、模型、workflow 文档。
- `tests/`：研究流程测试方式。
- `scripts/`：数据和实验脚本。

Dubhe 集成方式：

- 后端 `qlib-research-worker` 管理 Qlib 实验。
- 研究结果进入 `ai_analyses`、`strategy_versions` 或 `model_artifacts`。
- 不把 Qlib 训练任务放在移动端或桌面端本地跑。

## 9. 金融 NLP 与 AI 对话参考

### 9.1 FinGPT

- 仓库：`AI4Finance-Foundation/FinGPT`
- URL：https://github.com/AI4Finance-Foundation/FinGPT
- 默认分支：`master`
- 许可证：MIT License
- Dubhe 用途：金融大模型、新闻摘要、情绪分析、事件抽取、金融文本任务参考。

重点看：

- `fingpt/`：核心代码。
- `finogrid/`：金融智能体/网格相关参考。
- `tests/`：基本测试。
- `Use_Cases.md`：使用场景。
- notebook 文件：训练和推理流程参考。

Dubhe 集成边界：

- 优先作为 AI Analysis Service 的模型/提示词/任务参考。
- 模型权重和数据集授权必须单独核对。
- AI 输出必须带来源引用，不能直接下单。

### 9.2 FinBERT

- 仓库：`ProsusAI/finBERT`
- URL：https://github.com/ProsusAI/finBERT
- 默认分支：`master`
- 许可证：Apache License 2.0
- Dubhe 用途：金融情绪分析基线模型参考。

适合场景：

- 新闻标题情绪。
- 公告摘要情绪。
- AI 大模型结果的轻量交叉验证。

### 9.3 LibreChat

- 仓库：`danny-avila/LibreChat`
- URL：https://github.com/danny-avila/LibreChat
- 默认分支：`main`
- 许可证：MIT License
- Dubhe 用途：多模型对话、agent、工具调用、RAG、会话检索、用户认证的工程参考。

重点看：

- `api/`：后端 API。
- `client/`：对话 UI。
- `packages/`：共享包。
- `config/`、`librechat.example.yaml`：模型和工具配置。
- `rag.yml`：RAG 配置。
- `e2e/`：端到端测试。

Dubhe 集成边界：

- 不直接把 LibreChat UI 塞进 Theia。
- 参考 conversation、tool calling、model routing、RAG 的后端组织。
- Dubhe 的对话界面要服务中文投资工作流，而不是通用 ChatGPT clone。

### 9.4 Open WebUI

- 仓库：`open-webui/open-webui`
- URL：https://github.com/open-webui/open-webui
- 默认分支：`main`
- 许可证：Other，需核对具体授权。
- Dubhe 用途：自托管 AI UI、模型管理、用户体验和部署参考。

重点看：

- `backend/`：服务端。
- `src/`：前端。
- `docs/`：部署和能力说明。
- `docker-compose.yaml`：自托管部署。
- `test/`：测试。

## 10. 可视化策略与流程编排参考

### 10.1 Blockly

- 仓库：`RaspberryPiFoundation/blockly`
- URL：https://github.com/RaspberryPiFoundation/blockly
- 官方站点：https://blockly.com
- 默认分支：`main`
- 许可证：Apache License 2.0
- Dubhe 用途：小白策略积木编辑器。

重点看：

- `packages/`：blockly 包和生成器。
- `patches/`：补丁管理方式。
- `sample.svg`、README：基础使用。

Dubhe 集成方式：

- 定义金融策略 blocks：标的池、新闻条件、价格条件、仓位、止损、止盈、调仓、风控。
- 生成中间格式 `StrategySpec`，再由后端生成 LEAN 策略草案。
- 不让 Blockly 直接生成可实盘执行订单。

### 10.2 Node-RED

- 仓库：`node-red/node-red`
- URL：https://github.com/node-red/node-red
- 默认分支：`main`
- 许可证：Apache License 2.0
- Dubhe 用途：低代码流程、节点式编排和运行时体验参考。

Dubhe 集成边界：

- 可以参考节点、连线、运行日志、调试面板。
- 生产交易链路仍走 Dubhe 后端服务和风控网关。

### 10.3 n8n

- 仓库：`n8n-io/n8n`
- URL：https://github.com/n8n-io/n8n
- 默认分支：`master`
- 许可证：Other，需核对 fair-code/商用限制。
- Dubhe 用途：工作流自动化 UI、节点生态和凭据管理体验参考。

注意：

- 优先只参考产品设计和节点编排概念。
- 不把 n8n 作为第一版生产交易编排核心。

## 11. 图表与可视化参考

### 11.1 TradingView Lightweight Charts

- 仓库：`tradingview/lightweight-charts`
- URL：https://github.com/tradingview/lightweight-charts
- 默认分支：`master`
- 许可证：Apache License 2.0
- Dubhe 用途：K 线、分时、成交量和轻量行情图。

重点看：

- `src/`：图表核心。
- `packages/`：包组织。
- `indicator-examples/`：指标示例。
- `plugin-examples/`：插件示例。
- `tests/`：图表测试。
- `website/`：文档站。

Dubhe 集成方式：

- 桌面端 Theia 面板内展示行情和回测标记。
- 移动端展示轻量行情和策略结果。

### 11.2 Apache ECharts

- 仓库：`apache/echarts`
- URL：https://github.com/apache/echarts
- 默认分支：`master`
- 许可证：Apache License 2.0
- Dubhe 用途：回测报告、收益曲线、回撤、归因、新闻影响分布、策略对比。

重点看：

- `src/`：图表组件。
- `test/`：测试样例。
- `i18n/`：国际化。
- `theme/`：主题。
- `extension-src/`：扩展。

## 12. Broker 与交易 API 参考

### 12.1 Alpaca Python SDK

- 仓库：`alpacahq/alpaca-py`
- URL：https://github.com/alpacahq/alpaca-py
- 默认分支：`master`
- 许可证：Apache License 2.0
- Dubhe 用途：美股 paper trading 和后续 live broker adapter 参考。

重点看：

- `alpaca/`：SDK 源码。
- `examples/`：交易和行情示例。
- `tests/`：SDK 测试。
- `docs/`：接口文档。

Dubhe 集成边界：

- Alpaca adapter 只能由 Order Service 调用。
- AI、Theia、Flutter 都不能直接持有 Alpaca 下单权限。

### 12.2 Interactive Brokers TWS API

- 仓库：`InteractiveBrokers/tws-api-public`
- URL：https://github.com/InteractiveBrokers/tws-api-public
- 默认分支：`master`
- 许可证：未在 GitHub metadata 中返回，必须人工核对。
- Dubhe 用途：IBKR 多市场交易能力参考。

使用建议：

- 先用于 paper trading。
- live trading 前必须做 broker rejection、断线重连、重复订单、交易时段和权限测试。

### 12.3 Futu OpenAPI

- SDK 仓库：`FutunnOpen/py-futu-api`
- SDK URL：https://github.com/FutunnOpen/py-futu-api
- 文档仓库：`FutunnOpen/futu-api-doc`
- 文档 URL：https://github.com/FutunnOpen/futu-api-doc
- 默认分支：`master`
- SDK 许可证：Apache License 2.0
- Dubhe 用途：港股/美股/A 股相关行情与交易能力候选，具体权限按账户和地区确认。

重点看：

- `py-futu-api`：Python SDK。
- `futu-api-doc`：开放接口文档。

Dubhe 集成边界：

- 港股交易规则、货币、半日市、特殊天气安排必须单独建模。
- 数据权限、交易权限、账户地区限制必须在 provider metadata 中记录。

## 13. 存储与基础设施参考

### 13.1 TimescaleDB

- 仓库：`timescale/timescaledb`
- URL：https://github.com/timescale/timescaledb
- 默认分支：`main`
- 许可证：Other，需核对具体版本授权。
- Dubhe 用途：行情、新闻事件时间线、策略信号、回测序列等时序数据。

### 13.2 Redis

- 仓库：`redis/redis`
- URL：https://github.com/redis/redis
- 默认分支：`unstable`
- 许可证：Other，需核对当前授权。
- Dubhe 用途：任务队列、缓存、状态推送、分布式锁、rate limit。

### 13.3 MinIO

- 仓库：`minio/minio`
- URL：https://github.com/minio/minio
- 默认分支：`master`
- 许可证：GNU AGPLv3
- Dubhe 用途：S3-compatible 对象存储，保存 Notebook、报告、模型文件、日志归档、授权数据原文引用。

注意：

- AGPLv3 对部署和分发有合规要求；生产选型前必须让法务核对。
- 也可替换为 AWS S3、Cloudflare R2、阿里云 OSS、腾讯云 COS 等对象存储。

## 14. 数据源与新闻 API 参考

这些多为商业或官方 API，不一定有可直接参考的开源仓库。

### 14.1 A 股

| 来源 | 用途 | 参考方式 |
| --- | --- | --- |
| Wind | 新闻、行情、公告、研报 | 商业 API 文档和 SDK |
| iFinD | 新闻、行情、公告、研报 | 商业 API 文档和 SDK |
| Choice | 新闻、行情、公告、研报 | 商业 API 文档和 SDK |
| CNINFO | 上市公司公告 | 官方接口/条款 |
| SSE/SZSE | 交易所披露 | 官方接口/条款 |
| Tushare Pro | 研究数据补充 | API 文档和 token 权限 |
| 财联社 | 快讯与金融新闻 | 商业授权 |
| 华尔街见闻 | 金融新闻 | 商业授权 |

### 14.2 港股

| 来源 | 用途 | 参考方式 |
| --- | --- | --- |
| HKEXnews / HKEX IIS | 港交所公告和发行人信息 | 官方数据服务文档 |
| AASTOCKS | 港股新闻 | 商业授权 |
| ET Net | 港股新闻 | 商业授权 |
| Futu OpenAPI | 行情/交易候选 | SDK 和文档仓库 |

### 14.3 美股/全球

| 来源 | 用途 | 参考方式 |
| --- | --- | --- |
| SEC EDGAR APIs | 公告、财报、监管披露 | 官方 API 文档 |
| Benzinga | 美股新闻 | 商业 API |
| Dow Jones Newswires | 机构新闻 | 商业 API |
| Nasdaq Data Link | 数据产品 | API 文档 |
| Finnhub | 公司新闻、行情、情绪 | API 文档 |
| Alpha Vantage | 新闻情绪和行情 | API 文档 |
| Polygon/Massive | 行情和新闻 | API 文档 |
| GDELT | 全球宏观新闻和舆情 | 官方数据文档 |

## 15. 模拟测试链参考

Dubhe 的兜底链以 `docs/SIMULATION_TEST_CHAIN.md` 为准。参考项目的测试重点如下：

| 参考项目 | 看什么 | 用到 Dubhe 哪里 |
| --- | --- | --- |
| LEAN `Tests/` | 回测、订单、券商、数据行为测试 | Backtest worker、paper trading、broker adapter |
| Alpaca `tests/` | SDK 请求/响应和错误处理 | Alpaca adapter |
| OpenBB tests | provider adapter 和数据契约 | News/Data adapters |
| Qlib `tests/` | 研究流程和模型流程 | Qlib research worker |
| LibreChat `e2e/` | 对话和工具调用端到端测试 | AI Analyst |
| Open WebUI `test/` | AI UI 和后端测试 | AI UI/模型路由参考 |
| ECharts/Lightweight Charts tests | 图表视觉和交互测试 | 回测报告、行情图 |

Dubhe 自己必须保留的测试门禁：

- `StrategySpec` schema contract tests。
- `NewsEvent` provider replay tests。
- `AI Analysis` source citation tests。
- `LEAN historical backtest smoke`。
- `Golden Replay Scenarios`。
- `Paper Trading adapter tests`。
- `Shadow Trading tests`。
- `Risk Service kill switch tests`。

## 16. 许可证与合规清单

每次从参考项目引入代码、配置或依赖前，必须记录：

- 项目名。
- 版本或 commit SHA。
- 许可证。
- 是否允许商用。
- 是否要求开源衍生作品。
- 是否涉及网络服务开源义务。
- 是否涉及商标限制。
- 是否涉及模型权重许可。
- 是否涉及数据再分发限制。

高关注项目：

- `OpenBB-finance/OpenBB`：GitHub metadata 显示 license 为 Other，需核对具体条款。
- `open-webui/open-webui`：GitHub metadata 显示 license 为 Other，需核对具体条款。
- `n8n-io/n8n`：GitHub metadata 显示 license 为 Other，需核对 fair-code/商用限制。
- `timescale/timescaledb`：GitHub metadata 显示 license 为 Other，需核对当前授权。
- `redis/redis`：GitHub metadata 显示 license 为 Other，需核对当前授权。
- `minio/minio`：AGPLv3，生产部署和分发前必须确认合规。
- `freqtrade/freqtrade`：GPLv3，优先只参考，不复制代码。
- `nautechsystems/nautilus_trader`：LGPLv3，集成方式需核对。
- `InteractiveBrokers/tws-api-public`：GitHub metadata 未返回 license，必须人工核对。

## 17. 后续维护规则

- 新增参考项目时，必须补充：仓库、URL、默认分支、许可证、用途、重点目录、Dubhe 集成边界。
- 如果参考项目改名、换 license、默认分支变化，更新本文件。
- 如果开始真正克隆源码，放入 `.reference-code/`。
- 如果从参考项目复制任何代码片段，必须在对应文件或 ADR 里记录来源和许可证判断。
- 如果只是参考架构或接口形状，不需要把第三方源码纳入 Dubhe。

