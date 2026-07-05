# Dubhe Core

Dubhe Core 是 Dubhe 的后端 API 最小骨架，当前提供：

- 健康检查。
- 系统状态体检，展示存储、认证、交易开关和新闻源配置是否就绪。
- 本地账号注册/登录、开发级设备注册、设备 Bearer token 认证与撤销、默认工作区、自选股、REST 增量事件和 WebSocket 实时同步链路。
- 开发期 MFA 占位码、账号角色、管理员角色分配、审计日志和风控管理接口权限门禁。
- 本地 SQLite 持久化存储，服务重启后保留账号、设备、工作区、自选股、分析、风控、纸面订单、模拟券商回报和纸面组合账户。
- SEC EDGAR / GDELT / Finnhub / Alpha Vantage / Fixture 新闻源聚合接口。
- 新闻事件中文分析占位链路。
- AI 分析师中文对话接口，可读取当前新闻、分析、策略草案和回测上下文；未配置模型时使用本地确定性安全兜底，配置 OpenAI-compatible 模型后优先调用真实模型，失败时自动回退，并把问答写入工作区快照和同步事件。
- 新闻分析生成策略草案与 deterministic replay 回测。
- 策略规格校验，以及保存 Blockly / 客户端生成的工作区策略草案并触发同步事件。
- 订单意图风控门禁。
- 人工审批请求与 kill switch。
- 纸面交易订单、模拟 paper broker 成交链路、纸面组合现金/持仓/权益入账。

当前版本可选接入 Finnhub / Alpha Vantage 授权新闻 API，但不内置商业合同、不接真实券商、不执行真实订单。所有交易相关请求必须先经过 `Risk Service`。

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

不会命令行的 Windows 用户也可以双击仓库根目录的 `Configure-Dubhe.cmd`，在打开的 `config\dubhe.local.env` 中启用 `DUBHE_CORE_DB_PATH`。

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

AI 分析师接口：

- `POST /v1/assistant/chat`：需要设备 Bearer token；只生成中文研究答复和安全提示，不创建订单、不连接真实券商。
- `GET /v1/assistant/turns`：需要设备 Bearer token；读取当前工作区最近 AI 分析师问答，供桌面端和移动端恢复对话。

可选模型路由环境变量：

```powershell
$env:DUBHE_LLM_MODEL="gpt-4.1-mini"
$env:DUBHE_LLM_API_KEY="..."
# 可选：本地 Ollama、vLLM、LiteLLM、OpenAI-compatible 代理网关等。
$env:DUBHE_LLM_BASE_URL="https://api.openai.com/v1"
```

未配置 `DUBHE_LLM_MODEL` 时，Core 会继续使用本地确定性安全兜底。配置官方 OpenAI `/v1` 地址时必须提供 `DUBHE_LLM_API_KEY`；本地无鉴权兼容服务可以只配置 `DUBHE_LLM_MODEL` 和 `DUBHE_LLM_BASE_URL`。模型输出会被限定为中文研究答复、下一步动作和安全提示，不会获得下单能力。

如果不想手动设置环境变量，可以双击仓库根目录的 `Configure-Dubhe.cmd`，在本机配置文件中启用同名配置项；Core 启动脚本会自动加载它。

管理员也可以通过桌面端或移动端的“系统状态 / 数据源配置”图形化编辑本机配置。底层接口为 `GET/PUT /v1/runtime/local-config`，需要设备 Bearer token 且仅限管理员；接口只返回脱敏状态，不回传真实 API key，更新动作会写入审计日志。

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

Windows 本地运行时也可以通过 `Configure-Dubhe.cmd` 填写这些 key。真实配置保存在 `config\dubhe.local.env`，该文件已被 Git 忽略；仓库只提交无密钥的 `config\dubhe.local.env.example` 模板。

图形化配置和 `Configure-Dubhe.cmd` 使用同一个 `config\dubhe.local.env` 文件。模型和新闻源 key 保存后会同步到当前 Core 进程；`DUBHE_CORE_DB_PATH` 这类启动期配置保存后需要重启 Core 才能生效。

配置体检接口：

```http
GET /v1/system/status
```

该接口只返回 `configured: true/false`、中文说明和适配器启用状态，不会返回任何 API key 或 User-Agent 原始值。桌面端可用它展示“数据源配置 / 系统状态”面板。

首次使用清单接口：

```http
GET /v1/onboarding/checklist
```

未登录时会提示创建/登录账号；携带设备 Bearer token 时会把工作区同步、纸面交易等步骤标为已就绪。该接口用于桌面端和移动端的中文小白引导，不执行任何写操作。

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
