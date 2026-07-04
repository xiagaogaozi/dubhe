# Dubhe Core

Dubhe Core 是 Dubhe 的后端 API 最小骨架，当前提供：

- 健康检查。
- 本地账号注册/登录、开发级设备注册、设备 Bearer token 认证与撤销、默认工作区、自选股、REST 增量事件和 WebSocket 实时同步链路。
- 开发期 MFA 占位码、账号角色、管理员角色分配、审计日志和风控管理接口权限门禁。
- 本地 SQLite 持久化存储，服务重启后保留账号、设备、工作区、自选股、分析、风控、纸面订单、模拟券商回报和纸面组合账户。
- SEC EDGAR / GDELT / Finnhub / Alpha Vantage / Fixture 新闻源聚合接口。
- 新闻事件中文分析占位链路。
- 新闻分析生成策略草案与 deterministic replay 回测。
- 策略规格校验。
- 订单意图风控门禁。
- 人工审批请求与 kill switch。
- 纸面交易订单、模拟 paper broker 成交链路、纸面组合现金/持仓/权益入账。

当前版本不接真实授权新闻 API、不接真实券商、不执行真实订单。所有交易相关请求必须先经过 `Risk Service`。

同步接口说明见 [Dubhe Sync Backend](../../docs/SYNC_BACKEND.md)。
数据源说明见 [Data Sources](../../docs/DATA_SOURCES.md)。

## 本地数据

默认数据库路径：

```text
services/core/data/dubhe-core.sqlite
```

可通过环境变量覆盖：

```powershell
$env:DUBHE_CORE_DB_PATH="D:\dubhe-data\dubhe-core.sqlite"
```

`data/` 已加入忽略规则，不会提交本地运行数据。

## 本地认证与权限

当前 Core 提供两套开发期入口：

- `POST /v1/auth/accounts/register`：创建或接管本地账号，返回设备会话。
- `POST /v1/auth/login`：账号密码登录，返回设备会话。
- `POST /v1/auth/devices/register`：保留给本地演示和旧客户端的开发入口，会创建/复用开发级设备会话。

默认 MFA 验证码是：

```text
000000
```

可通过环境变量覆盖：

```powershell
$env:DUBHE_LOCAL_MFA_CODE="123456"
```

角色：

- `admin`：管理员，可访问审批列表、审批/拒绝请求、查看和切换 kill switch、查看账号列表、分配角色、查看审计日志。
- `risk_manager`：风控管理员，可访问风控管理接口和审计日志。
- `user`：普通用户，可做研究、回测、纸面交易，但不能管理审批和 kill switch。

管理接口：

- `GET /v1/admin/users`：管理员查看用户列表。
- `POST /v1/admin/users/{user_id}/role`：管理员调整用户角色，不能移除最后一个管理员。
- `GET /v1/audit/logs`：管理员和风控管理员查看最近审计日志。

纸面组合接口：

- `GET /v1/simulation/paper-portfolio/{account_id}`：查看纸面账户现金、权益、持仓、均价和未实现盈亏。

纸面卖出会先校验当前持仓；空仓或超持仓卖出会被拦截，不会生成模拟券商回报，也不会写出负持仓。

生产版必须替换为正式 OIDC/企业身份、真实 MFA、刷新令牌、密码策略、不可篡改审计存储和更完整的管理员 UI。当前 PBKDF2 密码哈希、本地 MFA 和 SQLite 审计日志只用于最小可运行链路。

## 授权新闻源配置

`/v1/news/feed?live=true` 会自动尝试已配置的授权新闻源。当前支持：

```powershell
$env:FINNHUB_API_KEY="..."
$env:ALPHA_VANTAGE_API_KEY="..."
$env:DUBHE_SEC_USER_AGENT="Dubhe/0.1 your-email@example.com"
```

未配置 key 时，对应 provider 会返回中文 `skipped` 状态，并自动回退到 SEC/GDELT 或本地 fixture，不会导致客户端崩溃。商业源的正文存储、二次展示和 AI 处理范围必须以供应商合同为准；Core 当前只标准化标题、来源、URL、时间、标的、事件类型和 license flags。

## 本地运行

```powershell
cd D:\github\dubhe-main\services\core
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
uvicorn dubhe_core.main:app --reload
```

或直接使用脚本：

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\setup.ps1
.\scripts\run.ps1
```

打开：

- API: http://127.0.0.1:8000
- OpenAPI: http://127.0.0.1:8000/docs

本地桌面端 CORS 已允许 `127.0.0.1` / `localhost` 的任意端口，方便 Theia Desktop、React/Vite 原型和后续本机调试壳连接 Core。

## 测试

```powershell
cd D:\github\dubhe-main\services\core
pytest
```

或：

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\test.ps1
```
