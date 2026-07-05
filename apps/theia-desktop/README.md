# Dubhe Theia Desktop

Dubhe Theia Desktop 是 Windows / macOS 桌面端的正式 IDE 壳方向。当前 `apps/desktop` 仍是 React + Vite 原型；本目录开始落地用户选定的 Eclipse Theia Desktop 方案。

## 当前内容

- `app/`：Theia Electron application package，固定 Theia `1.73.1`。
- `packages/dubhe-theia-extension/`：Dubhe 自研 Theia extension。
- 默认打开 `Dubhe` 主视图，当前已经是中文 IDE 式工作台，包含活动栏、自选列表、新闻雷达、AI 分析师、策略草案、回测报告、纸面组合、审批中心和任务日志区域。
- 当前主视图已经接入 Dubhe Core：可配置 Core 地址、检查健康状态、创建/登录本地账号、查看工作区同步快照、订阅 WebSocket 实时同步事件、刷新新闻源、触发中文分析、通过右侧 AI 分析师对话讨论新闻/策略/回测、使用 Blockly 策略工坊生成并校验策略规格、本机保存策略模板、保存和载入工作区策略草案、运行 deterministic replay 回测、提交纸面交易、读取纸面组合、生成实盘审批演示、查看待审批请求、通过/拒绝审批、切换 kill switch，并浏览最近审计日志。
- 主视图仍保留现有 React/Vite 原型和 Dubhe Core API 文档入口；后续会继续接入 LEAN worker、策略编辑器文件落盘和更完整的策略模板库。
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
yarn --cwd packages/dubhe-theia-extension build
yarn build
```

本地 Core 默认地址为 `http://127.0.0.1:8000`。如果 Core 运行在其他端口，可直接在 Theia 左侧“Core 连接”里修改并保存。

`yarn build` 会生成 `app/lib/`、`app/src-gen/` 和 `app/gen-esbuild*.mjs`，这些都是可再生构建产物，已加入 `.gitignore`。

## 打包目标

Windows 图标资源位于 `app/resources/`，如需重新生成图标：

```powershell
.\scripts\generate-icons.ps1
```

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

CI 会拆开执行以下两个命令：

```powershell
yarn dist:mac:arm64
yarn dist:mac:x64
```

国内网络如果下载 Electron 或 electron-builder 辅助二进制超时，可以在当前 PowerShell 会话里临时设置镜像后再执行打包命令：

```powershell
$env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
$env:ELECTRON_BUILDER_BINARIES_MIRROR = 'https://npmmirror.com/mirrors/electron-builder-binaries/'
```

当前已经能生成未签名 Windows `.exe` 安装器和便携版；仍未完成 Windows `.msi`、macOS `.dmg/.pkg` 实机验证、正式签名、图标、自动更新、安装器元数据和发布流水线。`dist:mac` 需要在 macOS 构建机上执行。

## GitHub Actions

`docs/ci/theia-desktop.yml` 是桌面端打包流水线模板。将它复制到 `.github/workflows/theia-desktop.yml` 后，会在 `main` 分支相关文件变更或手动触发时构建桌面端安装产物：

- Windows：`Dubhe-*-win-x64-setup.exe`、`Dubhe-*-win-x64-portable.exe`。
- macOS arm64：`dmg` 和 `zip`。
- macOS x64：`dmg` 和 `zip`。

当前 CI 产物保留 14 天，后续接入正式发布流水线后再上传到 GitHub Releases。

## 后续迁移顺序

1. 新闻雷达：把 `apps/desktop` 中新闻列表和中文分析卡迁入 Theia widget。
2. AI 分析师：已接入可审计的中文研究对话；后续替换为 OpenAI-compatible / FinGPT 模型路由和更完整工具调用。
3. 策略工坊：已接 Blockly/模板和 Core 规格校验；后续补 Theia 编辑器文件落盘。
4. 回测中心：接 LEAN worker 任务进度和报告。
5. 纸面组合与订单：接 Core 纸面账本、模拟券商回报和同步事件。
6. 风控中心：继续补齐审批筛选、实时同步和更完整的风控策略配置。
