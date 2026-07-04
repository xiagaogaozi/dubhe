# Dubhe Core

Dubhe Core 是 Dubhe 的后端 API 最小骨架，当前提供：

- 健康检查。
- 设备注册、设备 Bearer token 认证与撤销、默认工作区、自选股、REST 增量事件和 WebSocket 实时同步链路。
- 本地 SQLite 持久化存储，服务重启后保留账号、设备、工作区、自选股、分析、风控和纸面订单。
- SEC EDGAR / GDELT / Fixture 新闻源聚合接口。
- 新闻事件中文分析占位链路。
- 新闻分析生成策略草案与 deterministic replay 回测。
- 策略规格校验。
- 订单意图风控门禁。
- 人工审批请求与 kill switch。
- 纸面交易订单占位链路。

当前版本不接真实新闻 API、不接真实券商、不执行真实订单。所有交易相关请求必须先经过 `Risk Service`。

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
