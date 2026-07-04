# Dubhe Sync Backend

Dubhe 采用自建云同步方案。当前实现是第一条最小可用同步链路，用于让 Windows、macOS、iOS、Android 客户端共享同一账号下的工作区、自选股和后续任务状态。

## 当前能力

- 本地账号注册/登录：客户端可调用 `POST /v1/auth/accounts/register` 和 `POST /v1/auth/login`，获得 `user_id`、`device_id`、`workspace_id`、`role` 和设备访问令牌。
- 开发级设备注册：旧客户端或本地演示可调用 `POST /v1/auth/devices/register`，获得同样的设备会话；该入口保留用于兼容，不是生产登录方案。
- 设备认证：私有同步与安全端点需要携带 `Authorization: Bearer <access_token>`，Core 只保存令牌哈希，不把明文令牌写入设备表。
- 设备撤销：客户端可调用 `POST /v1/auth/devices/current/revoke` 让当前设备 token 立即失效。
- 默认工作区：同一 `account_key` 会复用同一个工作区。
- 自选股同步：客户端可通过 `PUT /v1/workspaces/{workspace_id}/watchlist/{symbol}` 新增或更新自选股。
- 同步快照：客户端通过 `GET /v1/workspaces/{workspace_id}/snapshot` 获取工作区、自选股、分析、风控、纸面订单、纸面组合和同步事件。
- 增量事件：客户端通过 `GET /v1/workspaces/{workspace_id}/sync-events?since_sequence=N` 拉取指定序列之后的事件。
- 实时同步：客户端可通过 WebSocket 订阅 `sync_events`，用于桌面端、移动端即时更新审批、急停、自选股和后续任务状态。
- 角色门禁：审批列表、审批/拒绝、kill switch 和审计日志只允许 `admin` 或 `risk_manager` 访问；账号角色分配只允许 `admin` 访问；普通用户仍可做研究、回测和纸面交易。
- 本地持久化：Core 使用 SQLite 保存账号、设备、工作区、自选股、同步事件、AI 分析、风控判定、纸面订单、纸面组合和审计日志。

## 当前接口

### 本地账号注册

```http
POST /v1/auth/accounts/register
```

请求体：

```json
{
  "account_key": "local-demo",
  "account_name": "本地演示账户",
  "password": "Dubhe@2026",
  "mfa_code": "000000",
  "device_name": "Windows 设备",
  "platform": "windows"
}
```

返回的 `DeviceSession` 包含 `role`。全新数据库里的第一个正式账号默认为 `admin`，后续正式账号默认为 `user`。

### 本地账号登录

```http
POST /v1/auth/login
```

请求体：

```json
{
  "account_key": "local-demo",
  "password": "Dubhe@2026",
  "mfa_code": "000000",
  "device_name": "Windows 设备",
  "platform": "windows"
}
```

### 开发级设备注册

```http
POST /v1/auth/devices/register
```

该接口保留给本地演示和旧客户端。生产客户端应使用账号注册/登录接口。

`platform` 可选值：

- `windows`
- `macos`
- `ios`
- `android`

### 设备撤销

```http
POST /v1/auth/devices/current/revoke
Authorization: Bearer dubhe_dev_xxx
```

撤销后，同一个 token 再访问工作区快照、自选股、增量事件、审批或 kill switch 端点会返回 `401`。

### 风控管理权限

以下接口要求 `role` 为 `admin` 或 `risk_manager`：

```http
GET /v1/approvals
POST /v1/approvals/{approval_id}/approve
POST /v1/approvals/{approval_id}/reject
GET /v1/risk/kill-switch
POST /v1/risk/kill-switch
GET /v1/audit/logs
```

普通用户访问会返回 `403`。桌面端应展示为只读研究/回测/纸面交易状态，不应阻塞工作区加载。

### 管理员权限

以下接口要求 `role` 为 `admin`：

```http
GET /v1/admin/users
POST /v1/admin/users/{user_id}/role
```

角色调整请求体：

```json
{
  "role": "risk_manager",
  "reason_zh": "将该账号设为风控管理员。"
}
```

Core 会拒绝移除最后一个管理员。设备 token 每次鉴权都会读取用户当前角色，所以角色调整会在下一次 API 请求时生效。

### 工作区快照

```http
GET /v1/workspaces/{workspace_id}/snapshot?since_sequence=0
Authorization: Bearer dubhe_dev_xxx
```

返回：

- `workspace`
- `watchlist`
- `analyses`
- `risk_decisions`
- `paper_orders`
- `broker_orders`
- `paper_portfolios`
- `events`
- `server_sequence`

### 纸面组合

```http
GET /v1/simulation/paper-portfolio/demo_account
Authorization: Bearer dubhe_dev_xxx
```

返回纸面账户的：

- `cash_by_currency`
- `equity_by_currency`
- `realized_pnl_by_currency`
- `positions`

当前默认模拟现金为 `USD 100000`、`HKD 1000000`、`CNY 1000000`。模拟券商成交后，Core 会更新现金、持仓数量、持仓均价、持仓市值和未实现盈亏，并通过同步事件推送 `paper_portfolio`。纸面卖出会先校验当前持仓；空仓或超持仓卖出会被拦截，不会生成模拟券商回报，也不会写出负持仓。

### 自选股写入

```http
PUT /v1/workspaces/{workspace_id}/watchlist/NVDA
Authorization: Bearer dubhe_dev_xxx
```

请求体：

```json
{
  "symbol": "NVDA",
  "name": "英伟达",
  "market": "US",
  "notes_zh": "美股 AI 算力龙头"
}
```

### 实时同步 WebSocket

```text
ws://127.0.0.1:8000/v1/workspaces/{workspace_id}/sync-events/ws?access_token=dubhe_dev_xxx&since_sequence=10
```

连接语义：

- `access_token` 使用设备注册返回的 token。
- `since_sequence` 是客户端已处理的最后一个同步序列。
- 服务端会先补发 `since_sequence` 之后的事件，然后持续推送新事件。
- 单条消息格式与 `GET /v1/workspaces/{workspace_id}/sync-events` 返回的 `SyncEvent` 一致。
- token 无效、已撤销或不属于该工作区时，连接会被拒绝。

当前实现边界：

- SQLite 版本使用短间隔轮询读取新事件，后续 PostgreSQL/Redis 版本应替换为 pub/sub 或 notify/listen。
- 当前不做断线自动重放之外的消息确认；客户端重连时必须带上本地最后处理的 `server_sequence`。

## 安全边界

- 当前同步链路不授予实盘交易权限。
- 账号密码登录、PBKDF2 密码哈希、开发期 MFA 占位码、角色门禁、角色分配和 SQLite 审计日志已经打通最小链路，但仍不是生产身份系统。
- 设备会话返回的 `dubhe_dev_` 令牌已用于本地设备认证和撤销，但仍属于开发级令牌；生产版必须补齐正式 OIDC/企业身份、刷新令牌、真实 MFA、密码策略、角色分配 UI 和审计策略。
- 工作区快照、自选股写入、增量事件、WebSocket 实时同步、风控评估、风险决策列表、纸面订单、纸面组合、审批请求、kill switch、角色分配和审计日志端点已经要求设备 token；跨工作区 token 会被拒绝。
- AI 仍不能调用真实券商下单接口；交易必须经过 Risk Service。

## 本地数据库

默认数据库路径：

```text
services/core/data/dubhe-core.sqlite
```

可以用环境变量覆盖：

```powershell
$env:DUBHE_CORE_DB_PATH="D:\dubhe-data\dubhe-core.sqlite"
```

当前 SQLite 层是本地可用版本和后续 PostgreSQL schema 的过渡层。生产部署时仍应迁移到 PostgreSQL/TimescaleDB，并保留相同 API 契约。

## 下一步

- 将当前 SQLite schema 迁移到 PostgreSQL/TimescaleDB。
- 增加正式 OIDC/企业身份、刷新令牌、真实 MFA、不可篡改审计存储和更完整的管理员 UI。
- 将 WebSocket 内部实现迁移到 Redis/PostgreSQL pub/sub，减少 SQLite 轮询。
- 将移动端审批请求、回测进度、风控告警都纳入同一同步事件流。
