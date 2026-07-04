# Dubhe 完整计划书

## 0. 检索证据

- 已检索关键词：`dubhe`、`work`、`outputs`、`gh auth status`、`git --version`、`gh --version`、`Flutter`、`Tauri`、`React Native`、`Theia`、`LEAN`、`OpenBB`、`Qlib`、`FinGPT`、`GDELT`、`Wind`、`iFinD`、`Choice`、`HKEX`、`SEC EDGAR`、`Benzinga`、`Finnhub`。
- 已读取/核对来源：
  - 本地工作区 `C:\Users\ASUS\Documents\Codex\2026-07-04\wo`：仅有 `work/` 与 `outputs/`，没有既有产品代码。
  - `gh auth status`：本机 GitHub CLI 已登录，具备 `repo` 权限。
  - `gh repo view xiagaogaozi/dubhe`：用于确认改名后的远端仓库。
  - 官方文档/项目资料：Eclipse Theia、Flutter、QuantConnect LEAN、OpenBB、Microsoft Qlib、FinGPT、PostgreSQL/TimescaleDB、Redis、MinIO、GDELT、SEC EDGAR、HKEX、Benzinga、Finnhub、Alpha Vantage、Polygon/Massive、Wind、iFinD、Choice/Tushare 等。
- 已确认落点：
  - 产品路线：方案 A，即 Windows/macOS 用 Theia Desktop，iOS/Android 用 Flutter。
  - 同步路线：选项 1，即自建云同步后端。
  - 项目名：`Dubhe`。
  - 仓库名：`dubhe`。
  - 不设置其他本地化项目名。
- 未确认项：
  - 具体商业新闻 API 合同、价格、授权范围、二次分发权限：`需确认`，由商务/法务与数据供应商确认。
  - 第一批券商 API：`proposed default` 为 Alpaca Paper Trading + Interactive Brokers Paper Trading。
  - 生产级模型供应商：`proposed default` 为可插拔 OpenAI-compatible LLM endpoint，不在第一版绑定单一供应商。

## 1. 项目定位

`Dubhe` 是面向只会中文、不会编程、不会量化的投资用户的 AI 投资研究与量化交易工作台。

产品不是普通新闻软件，也不是给专业量化工程师使用的裸框架。它要把 A 股、港股、美股的权威金融新闻、公告、行情、AI 大数据分析、策略生成、回测、模拟盘和受控实盘交易串成一条可理解、可审计、可兜底的工作流。

核心原则：

- Chinese-first UI：默认界面语言为中文，外文新闻源必须提供中文翻译、中文摘要和原文对照。
- Beginner-first workflow：用户通过中文 AI 对话、按钮、模板和可视化策略块完成分析与策略制作。
- Mature-open-source-first：能缝合成熟开源项目就不自研核心引擎。
- Server-executed quant：复杂计算、策略运行、新闻处理、AI 分析和交易执行在云端后端完成。
- No direct AI trading：AI 只能提出建议和生成订单意图，不能绕过风控直接下单。

## 2. 产品命名

- 项目名：Dubhe
- 桌面端：Dubhe Desktop
- 移动端：Dubhe Companion
- 云端服务：Dubhe Core
- 仓库名：`dubhe`

命名含义：

- `Dubhe` 是北斗七星中天枢星的常用星名，适合作为全球市场导航、AI 投资分析和量化决策工作台的产品名。
- 命名只使用 `Dubhe`，不设置其他本地化项目名。

## 3. 目标用户

### 3.1 初级投资者

- 不会写代码。
- 不理解因子、回撤、滑点、风险敞口等专业概念。
- 需要 AI 用自然语言解释新闻、市场影响和策略结果。
- 默认只允许查看、模拟和审批，不允许自由修改生产策略底层代码。

### 3.2 半专业交易者

- 能理解简单策略条件。
- 希望通过策略模板和可视化积木构造交易逻辑。
- 需要回测、模拟盘、风控和移动端提醒。

### 3.3 专业研究员/管理员

- 可以使用 Theia 编辑器、Notebook、代码审查和配置管理。
- 可以管理数据源、权限、模型、策略运行环境和交易风控规则。

## 4. 范围

### 4.1 第一版必须做

- Windows/macOS 桌面安装包。
- iOS/Android 移动安装包。
- 自建云同步后端。
- 用户账号、设备登录、工作区同步。
- A 股、港股、美股新闻与公告接入框架。
- 新闻去重、翻译、摘要、情绪、影响标的映射。
- AI Analyst 对话面板。
- Theia 类 IDE 工作台。
- Flutter 移动端新闻、AI、预警、回测结果查看。
- LEAN 回测任务链。
- 模拟交易与纸面交易链。
- 审计日志、风控规则、订单审批。

### 4.2 第一版不做

- 不做纯网页版产品。
- 不做未经授权的新闻爬虫生产链路。
- 不允许 AI 绕过风控直接实盘下单。
- 不在 iOS/Android 本地运行完整 LEAN、Qlib 或大模型训练。
- 不在 MVP 阶段追求低延迟高频交易。
- 不把移动端做成完整 IDE；移动端是 companion app。

## 5. 总体架构

```text
-----------------------------+       +-----------------------------+
| Windows / macOS Desktop    |       | iOS / Android Mobile        |
| Eclipse Theia Desktop      |       | Flutter Companion           |
| AI Chat / Editor / Panels  |       | News / Alerts / Approvals   |
+--------------+--------------+       +--------------+--------------+
               |                                     |
               | REST/gRPC + WebSocket               |
               v                                     v
+-------------------------------------------------------------+
| Dubhe Core                                                  |
| Auth / Workspace / News / AI / Backtest / Risk / Orders     |
+-------------------+-------------------+---------------------+
                    |                   |
                    v                   v
       +---------------------+  +------------------------------+
       | Data Plane          |  | Execution Plane              |
       | Postgres/Timescale  |  | LEAN / Qlib / FinGPT         |
       | Redis / MinIO       |  | Paper Broker / Live Broker   |
       +---------------------+  +------------------------------+
                    |
                    v
       +----------------------------------------------+
       | Licensed Data Providers                      |
       | A-share / HK / US news, filings, market data |
       +----------------------------------------------+
```

## 6. 成熟项目缝合策略

| 能力 | 优先缝合项目 | 用法 | 自研边界 |
| --- | --- | --- | --- |
| 桌面 IDE 壳 | Eclipse Theia | Desktop workspace、panels、editor、commands | 写 Theia extensions 和产品面板 |
| 移动端 | Flutter | iOS/Android companion app | 写移动 UI、缓存、推送、审批 |
| AI 对话 | LibreChat / Open WebUI 思路 | 多模型、会话、工具调用参考 | 不直接嵌整个 UI，复用架构思想 |
| 回测/模拟/实盘 | QuantConnect LEAN | 策略引擎、回测、paper/live adapter | 写任务调度、结果展示、风控网关 |
| 金融数据 | OpenBB | 数据连接和研究接口 | 写 licensed provider adapters |
| AI 量化研究 | Microsoft Qlib | 因子、模型、研究实验 | 写任务包装和结果同步 |
| 金融 NLP | FinGPT / FinBERT | 摘要、情绪、事件抽取 | 写提示词、评估集、模型路由 |
| 可视化策略 | Blockly | 小白策略积木 | 写金融策略 block 和 LEAN 代码生成 |
| 工作流编排 | Node-RED / n8n | 内部任务编排参考 | 生产链路优先后端代码化 |
| 图表 | TradingView Lightweight Charts / ECharts | 行情、回测、归因图 | 写数据适配层 |
| 存储 | PostgreSQL + TimescaleDB | 业务数据与时序数据 | 写 schema、迁移、查询 API |
| 缓存/队列 | Redis | 任务状态、锁、缓存、pub/sub | 写 worker 协议 |
| 对象存储 | S3 / MinIO | Notebook、报告、模型、附件 | 写 signed URL 与权限 |

## 7. 客户端设计

### 7.1 桌面端：Dubhe Desktop

技术基座：

- Eclipse Theia Desktop。
- Monaco editor。
- Theia plugin/extension system。
- WebSocket task updates。
- Local encrypted token store，`proposed default`。

主界面：

```text
Activity Bar
  - 今日市场
  - 新闻雷达
  - AI 分析师
  - 策略工坊
  - 回测中心
  - 模拟交易
  - 数据源
  - 风控中心

Left Sidebar
  - 自选列表
  - 新闻筛选器
  - 策略项目
  - 回测记录

Center Workspace
  - 新闻原文标签页
  - AI 分析标签页
  - 可视化策略编辑器
  - 代码编辑器
  - Notebook/研究视图
  - 回测报告

Right Sidebar
  - AI 分析师对话
  - 上下文卡片
  - 下一步建议

Bottom Panel
  - 任务日志
  - 数据接入状态
  - 回测进度
  - 风控告警
```

小白用户体验规则：

- 所有技术结果都必须提供中文白话摘要。
- 所有 AI 结论都必须展示来源：新闻、公告、行情数据、模型信号或回测记录。
- 策略生成从中文自然语言和模板开始，而不是从空代码文件开始。
- 危险操作必须明确确认，并展示中文风险解释。
- 用户可以随时从 AI 摘要切换到原始来源。

### 7.2 移动端：Dubhe Companion

技术基座：

- Flutter for iOS and Android.
- SQLite local cache，`proposed default`。
- APNs/FCM push.
- REST/gRPC + WebSocket for sync.

主 Tab：

- 今日：全球市场简报、重点新闻、组合预警。
- 雷达：A 股/港股/美股新闻流、影响分、中文翻译。
- AI：结合新闻、自选股和回测上下文进行中文对话。
- 策略：运行中策略、回测结果、纸面交易订单。
- 审批：经过风控拦截的订单审批。
- 账户：设备、数据源状态、语言偏好、通知设置。

移动端不承担：

- 完整代码编辑。
- 完整 Notebook。
- 本地训练模型。
- 本地执行 LEAN 回测。

## 8. 后端模块

### 8.1 Auth & Workspace Service

职责：

- 用户注册、登录、MFA、设备管理。
- workspace、team、role、permission。
- API token、provider credential vault。
- 审计日志。

建议技术：

- FastAPI，`proposed default`。
- PostgreSQL。
- JWT + refresh token。
- OIDC/SAML 企业登录，后续阶段。

### 8.2 News Ingestion Service

职责：

- 接入 A 股、港股、美股新闻、公告、研报、监管披露。
- 统一为 `NewsEvent`。
- 去重、语言检测、翻译、实体识别、ticker 映射。
- 计算 freshness、source authority、market relevance。

核心数据契约：

```text
NewsEvent
  id
  provider
  provider_event_id
  source_name
  market_scope
  language
  title_original
  title_zh
  body_original_ref
  body_zh_ref
  published_at
  received_at
  url
  tickers
  entities
  event_type
  authority_score
  duplicate_group_id
  license_flags
```

### 8.3 AI Analysis Service

职责：

- 新闻摘要。
- 情绪分析。
- 事件影响分析。
- 相关标的解释。
- 策略草案生成。
- 回测结果解释。
- 中文输出优先；外文新闻、公告和财报必须提供中文摘要、中文解释和原文引用。

安全边界：

- AI 输出 `Analysis`、`StrategyDraft`、`OrderIntent`。
- AI 不输出直接 broker order。
- `OrderIntent` 必须进入 Risk Service。

### 8.4 Strategy Service

职责：

- 管理策略项目、版本、模板、参数。
- Blockly strategy blocks -> LEAN strategy code。
- Theia editor strategy code -> lint/test/package。
- 策略版本不可变，回测绑定固定版本。

核心数据契约：

```text
StrategyProject
StrategyVersion
StrategyTemplate
StrategyParameterSet
StrategyArtifact
```

### 8.5 Backtest & Simulation Service

职责：

- 调用 LEAN 执行历史回测。
- 运行 golden replay scenarios。
- 执行 paper trading。
- 保存指标、日志、图表、订单明细。
- 支持 shadow trading。

详见 `docs/SIMULATION_TEST_CHAIN.md`。

### 8.6 Risk & Order Service

职责：

- 接收 `OrderIntent`。
- 执行账户权限、市场状态、资金、仓位、风控规则检查。
- 生成 `RiskDecision`。
- 需要时请求用户审批。
- 对接 paper broker / live broker。
- 写入不可篡改审计日志，`proposed default` 为 append-only table + object storage export。

风控规则：

- max_order_notional。
- max_position_notional。
- max_daily_loss。
- max_symbol_exposure。
- max_sector_exposure。
- no_trade_window。
- news_confidence_threshold。
- market_open_check。
- limit-up/limit-down rules for A-share。
- short-selling eligibility。
- duplicate_order_guard。
- kill_switch。

## 9. 数据源计划

### 9.1 A 股

优先级：

1. Wind / iFinD / Choice：商业级金融新闻、公告、研报、行情。
2. CNINFO、SSE、SZSE：公告和监管披露。
3. Tushare Pro：研究型数据补充。
4. 财联社、华尔街见闻：商业授权后接入。

### 9.2 港股

优先级：

1. HKEXnews / HKEX Issuer Information feed Service：公告与发行人信息。
2. AASTOCKS / ET Net：商业财经新闻。
3. Futu OpenAPI：行情、账户和交易能力候选，新闻权限需确认。

### 9.3 美股/全球

优先级：

1. SEC EDGAR APIs：公告、财报、监管披露。
2. Benzinga / Dow Jones / Nasdaq Data Link：商业新闻。
3. Finnhub / Alpha Vantage / Polygon/Massive：新闻、情绪、行情补充。
4. GDELT：全球宏观新闻和舆情补充。

## 10. 同步与存储

选择：自建云同步。

```text
PostgreSQL / TimescaleDB
  users, workspaces, watchlists, strategies, news, analyses, backtests, orders

Redis
  task queue, locks, rate-limit counters, transient task status, pub/sub

S3 / MinIO
  notebooks, reports, model artifacts, raw licensed payload refs, logs exports

WebSocket
  news push, task progress, backtest progress, order state, risk alerts

REST/gRPC
  client APIs, worker APIs, data adapters

APNs / FCM
  mobile notifications and approval prompts
```

### 10.1 核心表草案

| Table | Purpose |
| --- | --- |
| `users` | 用户账号 |
| `devices` | Windows/macOS/iOS/Android 登录设备 |
| `workspaces` | 用户或团队工作区 |
| `watchlists` | 自选股列表 |
| `assets` | 股票、ETF、指数、期货等资产主数据 |
| `news_events` | 标准化新闻事件 |
| `news_event_assets` | 新闻与资产映射 |
| `ai_analyses` | AI 分析结果 |
| `strategy_projects` | 策略项目 |
| `strategy_versions` | 策略不可变版本 |
| `backtest_runs` | 回测运行记录 |
| `simulation_orders` | 模拟订单 |
| `paper_orders` | 纸面交易订单 |
| `order_intents` | AI 或策略生成的订单意图 |
| `risk_decisions` | 风控判定 |
| `approval_requests` | 用户审批 |
| `audit_logs` | 审计日志 |

## 11. 模拟测试兜底链

总原则：任何策略从 AI 生成到实盘执行，必须通过分层兜底链。

完整链路：

```text
AI strategy draft
  -> static validation
  -> unit/contract tests
  -> deterministic historical backtest
  -> golden replay scenarios
  -> paper trading
  -> shadow trading
  -> canary live trading
  -> full live trading with kill switch
```

准入标准：

- 没有通过静态校验，不能进入回测。
- 没有通过历史回测，不能进入 paper trading。
- 没有通过 paper trading，不能进入 shadow trading。
- 没有通过 shadow trading，不能进入 canary live。
- canary live 必须小资金、小仓位、短周期、强 kill switch。
- 第一版只交付到 paper trading 和 shadow trading，不默认开放 full live。

详见 `docs/SIMULATION_TEST_CHAIN.md`。

## 12. 实施阶段

### Phase 0：仓库与架构冻结

交付：

- 初始 GitHub private repository。
- README。
- Project Plan。
- Architecture。
- Simulation Test Chain。
- Data Sources。
- ADR-0001。

通过标准：

- 仓库可访问。
- 文档能解释产品边界、技术选型、测试链和第一版范围。

### Phase 1：后端基础设施

交付：

- FastAPI backend scaffold。
- PostgreSQL/TimescaleDB schema migration。
- Redis queue。
- MinIO local dev。
- Auth/device/workspace API。
- WebSocket task channel。

当前状态：

- 已完成 SQLite 版设备注册、设备 token 认证/撤销、工作区快照、增量同步事件和 WebSocket 同步事件流；生产版仍需迁移 PostgreSQL/Redis、正式登录/MFA 和权限模型。

通过标准：

- Windows/macOS/iOS/Android client mock can login and receive sync events。
- API contract tests pass。

### Phase 2：新闻与 AI 分析

交付：

- GDELT + SEC EDGAR + Finnhub/Benzinga adapter，按授权选择。
- `NewsEvent` normalization。
- Translation/summarization pipeline。
- AI Analyst tool-calling。
- News-to-ticker mapping。

通过标准：

- 输入一条 A/HK/US 新闻，系统能生成中文摘要、影响标的、置信度、来源链接。
- 去重、延迟、缺失字段场景有测试。

### Phase 3：桌面端与移动端壳

交付：

- Theia Desktop shell。
- AI Analyst panel。
- 新闻雷达面板。
- 策略工坊占位页。
- Flutter Companion shell。
- Push notification skeleton。

通过标准：

- Windows/macOS 能安装并打开桌面端。
- iOS/Android 能安装并登录移动端。
- 同一账号跨设备看到一致的新闻、分析、任务状态。

### Phase 4：策略与回测

交付：

- LEAN worker。
- Strategy project/version model。
- Strategy template。
- Blockly -> strategy draft pipeline。
- Backtest result parser。
- Backtest report UI。

通过标准：

- 用户通过 AI 生成一个策略草案。
- 系统执行静态校验。
- LEAN 回测完成。
- 桌面端和移动端都能查看结果。

### Phase 5：模拟盘与 shadow trading

交付：

- Paper broker adapter。
- Shadow trading mode。
- Risk service。
- Approval flow。
- Audit log。

通过标准：

- 订单意图通过风控后进入 paper broker。
- Shadow mode 不下单，只记录本应下单行为。
- 移动端可审批或拒绝高风险订单。

### Phase 6：受控实盘

交付：

- IBKR/Alpaca/Futu 等 broker adapter，按市场和许可确认。
- Canary live mode。
- Hard kill switch。
- Daily loss lock。
- Compliance export。

通过标准：

- 实盘功能默认关闭。
- 管理员启用后，策略仍必须通过全链路测试。
- 所有订单可追踪到 strategy version、risk decision、approval、broker response。

## 13. 验收标准

### 13.1 产品验收

- 非技术用户能通过 AI 对话完成新闻分析。
- 用户能从新闻影响分析跳转到相关股票、历史走势和回测建议。
- 用户能用模板/可视化块创建策略草案。
- 用户能看懂回测结果中的收益、回撤、胜率、风险解释。
- 用户能在移动端收到预警和审批请求。

### 13.2 工程验收

- 所有核心 API 有 contract tests。
- 所有外部 provider adapter 有 mock 和 replay tests。
- 所有策略升级都绑定不可变版本。
- 所有交易相关行为都有审计日志。
- CI 至少运行 lint、unit、contract、replay smoke tests。
- 生产环境禁止使用未授权数据源。

### 13.3 风控验收

- AI 不能直接调用 broker live order API。
- Risk Service 是订单执行的唯一入口。
- kill switch 可以在 5 秒内阻止新订单，`proposed default`。
- 单用户、单策略、单标的、单市场都有额度限制。
- 所有审批操作记录设备、IP、时间、订单内容和风险解释。

## 14. 主要风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 商业新闻 API 授权不足 | 无法生产上线 | 第一版使用授权明确的数据源；所有 provider 加 license flags |
| AI 幻觉 | 错误解释或错误策略 | 强制 source citation、tool-only facts、回测兜底、人工确认 |
| 跨市场规则复杂 | A/HK/US 行情和交易规则不一致 | market calendar、trading phase、limit rules 独立建模 |
| 移动端功能过重 | 开发成本高、体验差 | 移动端只做 companion app |
| 实盘交易风险 | 资金损失 | 默认禁用实盘、paper/shadow/canary 分层推进 |
| 供应商锁定 | 成本和合规风险 | provider adapter interface，多源可替换 |

## 15. 下一步工作

1. 创建 GitHub private repository。
2. 将本文档与模拟测试链推送到默认分支。
3. 创建 Phase 1 issue 列表。
4. 确定第一批数据源：`proposed default` 为 GDELT + SEC EDGAR + Finnhub/Benzinga。
5. 确定第一批交易环境：`proposed default` 为 Alpaca Paper Trading。
6. 决定后端语言：`proposed default` 为 Python FastAPI + Python workers。
7. 决定桌面端 Theia extension 开发方式。
8. 决定 Flutter 移动端状态管理和本地缓存方案。
