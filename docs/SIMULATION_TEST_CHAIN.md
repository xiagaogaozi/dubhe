# 成熟模拟测试兜底链

## 1. 目标

本测试链用于防止 AI 分析错误、策略代码错误、数据源异常、市场规则遗漏、风控失效和 broker adapter bug 直接进入真实交易。

设计参考成熟量化平台常见流程：

- 历史回测：使用 QuantConnect LEAN 执行 deterministic backtest。
- 回归用例：维护固定数据、固定参数、固定预期的 golden replay scenarios。
- 纸面交易：使用 broker paper trading 或模拟撮合。
- Shadow trading：策略实时运行但不下单，仅记录本应发生的订单。
- Canary live：极小资金、极低额度、强风控的实盘验证。

## 2. 总链路

```text
Strategy idea
  -> AI explanation and draft
  -> StrategySpec validation
  -> Static code validation
  -> Unit tests
  -> Contract tests
  -> Historical backtest
  -> Golden replay scenarios
  -> Paper trading
  -> Shadow trading
  -> Canary live
  -> Guarded live
```

所有阶段都要产出机器可读结果，写入 `test_gate_results`，并关联：

- `strategy_project_id`
- `strategy_version_id`
- `data_snapshot_id`
- `model_version_id`
- `risk_policy_version_id`
- `run_id`

## 3. Gate 0：AI 输出约束

AI 只能生成：

- `Analysis`
- `StrategyDraft`
- `StrategySpec`
- `OrderIntent`
- `RiskExplanation`

AI 不能生成：

- 直接 broker order。
- 未经 schema 校验的策略代码。
- 无来源引用的事实结论。
- 绕过 Risk Service 的执行指令。

通过标准：

- AI 分析必须包含来源引用。
- 策略草案必须能转换成 `StrategySpec`。
- `OrderIntent` 必须进入 Risk Service。

## 4. Gate 1：StrategySpec 校验

`StrategySpec` 是小白策略、AI 策略和代码策略的共同中间格式。

必填字段：

```text
strategy_name
market_scope
asset_universe
entry_rules
exit_rules
risk_limits
timeframe
rebalance_rule
data_dependencies
broker_permissions
```

校验项：

- 市场范围合法：A-share、HK、US。
- 标的池存在。
- 入场/出场规则无空条件。
- 风控限制存在。
- 使用的数据源有 license。
- 不允许无限杠杆。
- 不允许未授权卖空。
- 不允许绕过交易时段。

失败处理：

- 返回人类可读解释。
- AI 可重新生成草案。
- 不进入代码生成和回测。

## 5. Gate 2：静态代码校验

适用于 Theia editor 或 AI 生成的 LEAN 策略代码。

检查项：

- 禁止网络请求，除非在 allowlist。
- 禁止读取本地敏感路径。
- 禁止调用 live broker SDK。
- 禁止动态执行未知字符串。
- 禁止修改全局运行器配置。
- 依赖必须来自 allowlist。
- 必须实现标准策略入口。

通过标准：

- 代码语法通过。
- 静态扫描通过。
- 生成 artifact hash。
- 绑定 immutable `strategy_version_id`。

## 6. Gate 3：单元测试与契约测试

单元测试覆盖：

- 指标计算。
- 规则触发。
- 参数边界。
- 仓位计算。
- 风控函数。

契约测试覆盖：

- `NewsEvent` schema。
- `MarketBar` schema。
- `StrategySpec` schema。
- `OrderIntent` schema。
- `RiskDecision` schema。
- provider adapter mock。
- broker adapter mock。

通过标准：

- 所有 critical tests 通过。
- adapter 在缺字段、重复消息、延迟消息、乱序消息下行为确定。

## 7. Gate 4：历史回测

引擎：QuantConnect LEAN。

输入：

- immutable strategy artifact。
- pinned data snapshot。
- pinned fee model。
- pinned slippage model。
- pinned market calendar。
- pinned risk policy。

输出：

- CAGR。
- total return。
- max drawdown。
- Sharpe。
- win rate。
- turnover。
- exposure。
- orders。
- fills。
- logs。
- chart series。

最低通过标准，`proposed default`：

- max drawdown <= configured threshold。
- no unknown fills。
- no negative cash unless margin enabled。
- no order outside market hours。
- no unlicensed data access。
- no runtime exception。

## 8. Gate 5：Golden Replay Scenarios

Golden replay 是本项目最重要的兜底层。它不追求覆盖所有历史，而是固定一批高风险场景，防止后续代码改动破坏关键行为。

### 8.1 A 股场景

- A 股涨停后策略继续追单。
- 跌停无法卖出。
- 午休时段订单生成。
- 停牌期间新闻触发订单。
- 北向资金新闻与 A 股 ticker 映射。
- 中文新闻翻译后实体识别错误。
- 同一公告被多家媒体重复报道。

### 8.2 港股场景

- 港股半日市。
- 台风/黑雨特殊交易安排，`需接入日历后确认`。
- HKEX 公告延迟处理。
- 港币计价和美元账户换汇。
- 腾讯/阿里等多市场或 ADR 映射。

### 8.3 美股场景

- SEC 8-K/10-Q/10-K 发布后影响分析。
- 盘前/盘后新闻触发策略。
- stock split 后历史价格调整。
- earnings surprise 新闻重复推送。
- market-wide circuit breaker。
- 新闻 API 延迟 15 分钟。

### 8.4 通用异常场景

- provider outage。
- Redis 重启。
- WebSocket 断线重连。
- broker rate limit。
- duplicate order intent。
- stale market data。
- missing quote。
- model timeout。
- AI 返回无引用结论。

每个 golden scenario 包含：

```text
scenario_id
market
input_news_events
input_market_bars
input_calendar
strategy_version
expected_order_intents
expected_risk_decisions
expected_user_visible_explanation
expected_no_live_order
```

通过标准：

- 结果与 expected fixtures 一致。
- 用户可见解释没有遗漏关键风险。
- 任何异常场景都不能进入 live order。

## 9. Gate 6：Paper Trading

目标：

- 验证实时行情、订单生成、风控、broker adapter、同步和 UI 状态。
- 不使用真实资金。

候选：

- Alpaca Paper Trading，优先用于美股 MVP。
- Interactive Brokers Paper Trading，用于多市场后续验证。
- Futu 模拟环境，若目标市场和权限确认。

检查项：

- order intent -> risk decision -> paper order -> broker response -> UI sync。
- 订单状态一致：new、accepted、partial_fill、filled、rejected、canceled。
- 手续费和滑点记录。
- 断线重连后不重复下单。
- 移动端审批延迟不会导致过期订单执行。

通过标准：

- 连续 N 个交易日无 critical incident，`proposed default` N=10。
- paper result 和 expected risk limits 一致。
- 所有 rejection 都有用户可读解释。

## 10. Gate 7：Shadow Trading

目标：

- 在真实实时数据环境中运行策略。
- 不向 broker 发送真实订单。
- 记录“如果实盘会发生什么”。

输出：

- shadow order intents。
- risk decisions。
- hypothetical fills。
- difference vs paper/live benchmark。
- missed opportunity report。
- false positive report。

通过标准：

- 连续 N 个交易日 shadow 运行稳定，`proposed default` N=20。
- 无重复订单。
- 无越权订单。
- 无交易时段外订单。
- 风控拒绝结果符合预期。

## 11. Gate 8：Canary Live

第一版默认不开放。开放前必须由管理员启用。

限制，`proposed default`：

- 单笔订单 <= 账户净值 0.5%。
- 单日总订单 <= 账户净值 2%。
- 单策略每日亏损达到 0.5% 后自动暂停。
- 仅允许高流动性标的。
- 禁止复杂衍生品。
- 禁止无审批订单。

通过标准：

- 每笔订单有完整审计链。
- kill switch 验证通过。
- broker rejection 处理正确。
- 移动端和桌面端状态一致。

## 12. Kill Switch

kill switch 必须能阻止：

- 新订单生成。
- 新订单发送。
- 未审批订单继续审批。
- 已排队但未发送的订单。

kill switch 不强制撤销已在 broker 成交或正在成交的订单；撤单策略由 broker adapter 和市场规则决定。

触发来源：

- 用户手动。
- 管理员手动。
- 风控规则。
- 系统异常。
- 数据源异常。
- broker outage。
- 策略异常。

## 13. CI 流水线

最小 CI：

```text
lint
unit tests
schema contract tests
adapter mock tests
golden replay smoke
docker build
```

完整 CI：

```text
lint
unit tests
schema contract tests
adapter mock tests
LEAN backtest smoke
golden replay full
API integration tests
desktop build smoke
mobile build smoke
security scan
license scan
```

## 14. 发布门禁

策略发布门禁：

- StrategySpec valid。
- static scan pass。
- unit/contract pass。
- historical backtest pass。
- golden replay pass。
- paper/shadow pass，按阶段要求。

产品发布门禁：

- 客户端能登录。
- 数据同步正常。
- NewsEvent pipeline 正常。
- AI analysis 有来源引用。
- 风控服务在线。
- kill switch 验证通过。

## 15. 失败分级

| Level | Meaning | Action |
| --- | --- | --- |
| P0 | 可能导致真实资金错误交易 | 停止 live/paper/shadow，启用 kill switch |
| P1 | 风控、订单、数据一致性错误 | 停止策略晋级，保留回测 |
| P2 | AI 解释或 UI 状态错误 | 阻止用户审批，允许重新分析 |
| P3 | 报告、翻译、非关键展示错误 | 标记降级，不影响核心测试 |

