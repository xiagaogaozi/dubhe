# Dubhe Sync Backend

Dubhe 采用自建云同步方案。当前实现是第一条最小可用同步链路，用于让 Windows、macOS、iOS、Android 客户端共享同一账号下的工作区、自选股和后续任务状态。

## 当前能力

- 设备注册：客户端启动后调用 `POST /v1/auth/devices/register`，获得 `user_id`、`device_id`、`workspace_id` 和本地访问令牌。
- 默认工作区：同一 `account_key` 会复用同一个工作区。
- 自选股同步：客户端可通过 `PUT /v1/workspaces/{workspace_id}/watchlist/{symbol}` 新增或更新自选股。
- 同步快照：客户端通过 `GET /v1/workspaces/{workspace_id}/snapshot` 获取工作区、自选股、分析、风控、纸面订单和同步事件。
- 增量事件：客户端通过 `GET /v1/workspaces/{workspace_id}/sync-events?since_sequence=N` 拉取指定序列之后的事件。

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

### 工作区快照

```http
GET /v1/workspaces/{workspace_id}/snapshot?since_sequence=0
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
- 设备注册返回的 `local_` 令牌只用于本地开发占位，生产版必须替换为正式认证、刷新令牌、设备撤销和权限检查。
- AI 仍不能调用真实券商下单接口；交易必须经过 Risk Service。

## 下一步

- 将当前内存存储替换为 PostgreSQL/TimescaleDB schema。
- 给所有同步 API 加认证中间件。
- 增加 WebSocket 推送通道，减少客户端轮询。
- 将移动端审批请求、回测进度、风控告警都纳入同一同步事件流。
