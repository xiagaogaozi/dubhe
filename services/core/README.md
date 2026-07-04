# Dubhe Core

Dubhe Core 是 Dubhe 的后端 API 最小骨架，当前提供：

- 健康检查。
- 新闻事件中文分析占位链路。
- 策略规格校验。
- 订单意图风控门禁。
- 纸面交易订单占位链路。

当前版本不接真实新闻 API、不接真实券商、不执行真实订单。所有交易相关请求必须先经过 `Risk Service`。

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
