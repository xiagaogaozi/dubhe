# Dubhe Theia Desktop

Dubhe Theia Desktop 是 Windows / macOS 桌面端的正式 IDE 壳方向。当前 `apps/desktop` 仍是 React + Vite 原型；本目录开始落地用户选定的 Eclipse Theia Desktop 方案。

## 当前内容

- `app/`：Theia Electron application package，固定 Theia `1.73.1`。
- `packages/dubhe-theia-extension/`：Dubhe 自研 Theia extension。
- 默认打开 `Dubhe` 主视图，作为新闻雷达、AI 分析师、策略工坊、回测中心、纸面组合和风控中心的入口。
- 当前主视图会链接到现有 React/Vite 原型和 Dubhe Core API 文档，后续面板逐步从原型迁移到 Theia extension。

## 本地构建

Theia 当前建议使用 Node LTS 和 Yarn 1。本机若使用 Node 25，可能需要切换到 Node 20/22 LTS 后再构建。

```powershell
cd D:\github\dubhe-main\apps\theia-desktop
corepack enable
corepack prepare yarn@1.22.22 --activate
yarn install
yarn build
yarn start
```

如果当前 Node 安装不带 `corepack`，先使用：

```powershell
npm install --global yarn@1.22.22
```

## 打包目标

```powershell
yarn package:electron
```

该命令目标是生成 Theia Electron desktop package。当前仍未完成 Windows `.exe/.msi` 和 macOS `.dmg/.pkg` 的正式签名、图标、自动更新、安装器元数据和发布流水线。

## 后续迁移顺序

1. 新闻雷达：把 `apps/desktop` 中新闻列表和中文分析卡迁入 Theia widget。
2. AI 分析师：接入可审计的会话和工具调用，不让 AI 直接触碰 broker。
3. 策略工坊：接 Blockly/模板和 Theia 编辑器。
4. 回测中心：接 LEAN worker 任务进度和报告。
5. 纸面组合与订单：接 Core 纸面账本、模拟券商回报和同步事件。
6. 风控中心：接审批、kill switch、角色门禁和审计日志。
