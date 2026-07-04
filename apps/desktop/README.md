# Dubhe Desktop

Dubhe Desktop 是面向中文投资用户的桌面工作台前端雏形。当前版本使用 React + Vite，实现了类 IDE 的投资分析工作台布局，并接入 `Dubhe Core` 的最小 API：

- `/v1/auth/accounts/register`
- `/v1/auth/login`
- `/v1/auth/devices/current/revoke`
- `/v1/admin/users`
- `/v1/audit/logs`
- `/v1/workspaces/{workspace_id}/snapshot`
- `/v1/workspaces/{workspace_id}/sync-events/ws`
- `/v1/news/analyze`
- `/v1/risk/evaluate`
- `/v1/approvals`
- `/v1/risk/kill-switch`
- `/v1/simulation/paper-orders`

启动后会先显示中文登录页。默认演示账号字段为：

- 账号：`local-demo`
- 密码：`Dubhe@2026`
- 本地 MFA：`000000`

第一位正式注册用户会成为 `管理员`，可查看审批中心、kill switch、账号权限和审计日志；风控管理员可查看审批中心、kill switch 和审计日志；普通用户仍可进入工作台做新闻分析、回测和纸面交易，但不能操作风控管理按钮。

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

如果需要在 Windows 上做一次干净的端到端烟测，也可以直接启动 Vite 入口，避免嵌套 shell 吃掉环境变量：

```powershell
$env:VITE_DUBHE_CORE_URL="http://127.0.0.1:8017"
node .\node_modules\vite\bin\vite.js --host 127.0.0.1 --port 5173 --strictPort
```

## 同时启动后端

```powershell
cd D:\github\dubhe-main\services\core
.\scripts\run.ps1
```

## 当前边界

- 这是桌面端 UI 基础，不是最终 Theia Desktop 打包成品。
- 当前登录是本地开发链路，不是生产 OIDC/企业身份系统。
- 账号权限与审计日志已经可视化，但当前仍使用 Dubhe Core 的 SQLite 最小链路。
- 所有实盘交易仍然禁用。
- AI 分析、风控和纸面交易使用 Dubhe Core 的最小确定性链路。
