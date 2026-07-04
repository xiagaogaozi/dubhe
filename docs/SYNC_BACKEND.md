# Dubhe Sync Backend

Dubhe 采用自建云同步方案。当前实现是第一条最小可用同步链路，用于让 Windows、macOS、iOS、Android 客户端共享同一账号下的工作区、自选股和后续任务状态。

## 当前能力

- 设备注册：客户端启动后调用 `POST /v1/auth/devices/register`，获得 `user_id`、`device_id`、`workspace_id` 和设备访问令牌。
- 设备认证：私有同步与安全端点需要携带 `Authorization: Bearer <access_token>`，Core 只保存令牌哈希，不把明文令牌写入设备表。
- 设备撤销：客户端可调用 `POST /v1/auth/devices/current/revoke` 让当前设备 token 立即失效。
- 默认工作区：同一 `account_key` 会复用同一个工作区。
- 自选股同步：客户端可通过 `PUT /v1/workspaces/{workspace_id}/watchlist/{symbol}` 新增或更新自选股。
- 同步快照：客户端通过 `GET /v1/workspaces/{workspace_id}/snapshot` 获取工作区、自选股、分析、风控、纸面订单和同步事件。
- 增量事件：客户端通过 `GET /v1/workspaces/{workspace_id}/sync-events?since_sequence=N` 拉取指定序列之后的事件。
- 本地持久化：Core 使用 SQLite 保存账号、设备、工作区、自选股、同步事件、AI 分析、风控判定和纸面订单。

## 当前接口

### 设备注册

```http
POST /v1/auth/devices/register
```

请求体：

```json
{
  "account_key": "local-demo",
  "account_name": "本地演示账户",
  "device_name": "Windows 设备",
  "platform": "windows"
}
```

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
- `events`
- `server_sequence`

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

## 安全边界

- 当前同步链路不授予实盘交易权限。
- 设备注册返回的 `dubhe_dev_` 令牌已用于本地设备认证和撤销，但仍属于开发级令牌；生产版必须补齐正式登录、刷新令牌、MFA、权限分级和审计策略。
- 工作区快照、自选股写入、增量事件、审批请求和 kill switch 端点已经要求设备 Bearer token；跨工作区 token 会被拒绝。
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
- 增加正式登录、刷新令牌、MFA 和管理员权限模型。
- 增加 WebSocket 推送通道，减少客户端轮询。
- 将移动端审批请求、回测进度、风控告警都纳入同一同步事件流。
