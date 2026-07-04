# Dubhe Desktop

Dubhe Desktop 是面向中文投资用户的桌面工作台前端雏形。当前版本使用 React + Vite，实现了类 IDE 的投资分析工作台布局，并接入 `Dubhe Core` 的最小 API：

- `/v1/news/analyze`
- `/v1/risk/evaluate`
- `/v1/simulation/paper-orders`

## 启动前端

```powershell
cd D:\github\dubhe-main\apps\desktop
npm install
npm run dev
```

前端默认连接：

```text
http://127.0.0.1:8000
```

如需指定 Core API：

```powershell
$env:VITE_DUBHE_CORE_URL="http://127.0.0.1:8000"
npm run dev
```

## 同时启动后端

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\run.ps1
```

## 当前边界

- 这是桌面端 UI 基础，不是最终 Theia Desktop 打包成品。
- 所有实盘交易仍然禁用。
- AI 分析、风控和纸面交易使用 Dubhe Core 的最小确定性链路。
