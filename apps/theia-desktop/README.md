# Dubhe Theia Desktop

Dubhe Theia Desktop 是 Windows / macOS 桌面端的正式 IDE 壳方向。当前 `apps/desktop` 仍是 React + Vite 原型；本目录开始落地用户选定的 Eclipse Theia Desktop 方案。

## 当前内容

- `app/`：Theia Electron application package，固定 Theia `1.73.1`。
- `packages/dubhe-theia-extension/`：Dubhe 自研 Theia extension。
- 默认打开 `Dubhe` 主视图，作为新闻雷达、AI 分析师、策略工坊、回测中心、纸面组合和风控中心的入口。
- 当前主视图会链接到现有 React/Vite 原型和 Dubhe Core API 文档，后续面板逐步从原型迁移到 Theia extension。
- 当前暂不启用 `@theia/plugin-ext` / `@theia/plugin-ext-vscode`。这些扩展会拉入 Windows native 证书模块 `@vscode/windows-ca-certs`，本机缺少 Visual Studio Spectre-mitigated libraries 时会阻断构建；后续需要 VS Code 插件兼容时再单独处理。

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

已验证命令：

```powershell
yarn install --ignore-engines --network-timeout 600000
yarn build
```

`yarn build` 会生成 `app/lib/`、`app/src-gen/` 和 `app/gen-esbuild*.mjs`，这些都是可再生构建产物，已加入 `.gitignore`。

## 打包目标

```powershell
yarn package:electron
```

该命令会先执行 Theia build，再通过 `electron-builder --dir` 生成未签名目录包。Windows 本地验证产物位于 `app/dist/win-unpacked/Dubhe.exe`。

Windows 安装器目标：

```powershell
yarn dist:windows
```

该命令当前会生成：

- `app/dist/Dubhe-0.1.0-win-x64-setup.exe`
- `app/dist/Dubhe-0.1.0-win-x64-portable.exe`
- `app/dist/win-unpacked/Dubhe.exe`

macOS 安装器目标：

```powershell
yarn dist:mac
```

国内网络如果下载 Electron 或 electron-builder 辅助二进制超时，可以在当前 PowerShell 会话里临时设置镜像后再执行打包命令：

```powershell
$env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
$env:ELECTRON_BUILDER_BINARIES_MIRROR = 'https://npmmirror.com/mirrors/electron-builder-binaries/'
```

当前已经能生成未签名 Windows `.exe` 安装器和便携版；仍未完成 Windows `.msi`、macOS `.dmg/.pkg` 实机验证、正式签名、图标、自动更新、安装器元数据和发布流水线。`dist:mac` 需要在 macOS 构建机上执行。

## 后续迁移顺序

1. 新闻雷达：把 `apps/desktop` 中新闻列表和中文分析卡迁入 Theia widget。
2. AI 分析师：接入可审计的会话和工具调用，不让 AI 直接触碰 broker。
3. 策略工坊：接 Blockly/模板和 Theia 编辑器。
4. 回测中心：接 LEAN worker 任务进度和报告。
5. 纸面组合与订单：接 Core 纸面账本、模拟券商回报和同步事件。
6. 风控中心：接审批、kill switch、角色门禁和审计日志。
