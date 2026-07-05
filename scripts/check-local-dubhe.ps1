param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function New-Check {
    param(
        [string]$Area,
        [string]$Name,
        [ValidateSet("ok", "warn", "fail")]
        [string]$Status,
        [string]$Message,
        [bool]$Blocking = $false
    )

    [pscustomobject]@{
        area = $Area
        name = $Name
        status = $Status
        blocking = $Blocking
        message = $Message
    }
}

function Add-Check {
    param([pscustomobject]$Check)
    $script:checks.Add($Check) | Out-Null
}

function Test-CommandAvailable {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Resolve-ToolCommand {
    param(
        [string]$Command,
        [string]$BundledPath
    )

    if ($BundledPath -and (Test-Path $BundledPath)) {
        return $BundledPath
    }
    if (Test-CommandAvailable $Command) {
        return $Command
    }
    return $null
}

function Resolve-NewestFile {
    param(
        [string]$Directory,
        [string]$Pattern
    )

    if (-not (Test-Path $Directory)) {
        return $null
    }
    $files = @(
        Get-ChildItem -Path $Directory -Filter $Pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    if ($files.Count -eq 0) {
        return $null
    }
    return $files[0].FullName
}

function Test-CoreHealth {
    param([string]$Url)

    try {
        $response = Invoke-RestMethod -Uri "$Url/health" -TimeoutSec 2
        return $response.status -eq "ok" -and $response.service -eq "dubhe-core"
    } catch {
        return $false
    }
}

function Get-LanCoreUrls {
    param([int]$Port)

    $preferredAddresses = @(
        Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            ForEach-Object { $_.IPv4Address.IPAddress } |
            Where-Object { $_ -and $_ -ne "127.0.0.1" -and $_ -notlike "169.254.*" } |
            Select-Object -Unique
    )
    $privatePreferredAddresses = @(
        $preferredAddresses |
            Where-Object { $_ -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' }
    )
    if ($privatePreferredAddresses.Count -gt 0) {
        return @($privatePreferredAddresses | ForEach-Object { "http://$($_):$Port" })
    }
    if ($preferredAddresses.Count -gt 0) {
        return @($preferredAddresses | ForEach-Object { "http://$($_):$Port" })
    }

    $addresses = @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -and
                $_.IPAddress -ne "127.0.0.1" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.AddressState -eq "Preferred"
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    )
    return @($addresses | ForEach-Object { "http://$($_):$Port" })
}

function Test-CoreLanListener {
    param([int]$Port)

    $listeners = @(
        Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LocalAddress -eq "0.0.0.0" -or
                $_.LocalAddress -eq "::" -or
                ($_.LocalAddress -ne "127.0.0.1" -and $_.LocalAddress -ne "::1")
            }
    )
    return $listeners.Count -gt 0
}

function Read-SystemStatus {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -Uri "$Url/v1/system/status" -TimeoutSec 3 -UseBasicParsing
        if ($response.RawContentStream) {
            $response.RawContentStream.Position = 0
            $memory = [System.IO.MemoryStream]::new()
            $response.RawContentStream.CopyTo($memory)
            $json = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
            return $json | ConvertFrom-Json
        }
        return $response.Content | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-CheckLine {
    param([pscustomobject]$Check)

    $label = switch ($Check.status) {
        "ok" { "[OK]" }
        "warn" { "[提示]" }
        "fail" { "[缺失]" }
    }
    Write-Host "$label $($Check.area) / $($Check.name)：$($Check.message)"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$configLoader = Join-Path $repoRoot "scripts\dubhe-config.ps1"
if (Test-Path $configLoader) {
    . $configLoader
    $loadedLocalConfigKeys = @(Import-DubheLocalConfig -RepoRoot $repoRoot -Quiet)
} else {
    $loadedLocalConfigKeys = @()
}
$coreRoot = Join-Path $repoRoot "services\core"
$theiaRoot = Join-Path $repoRoot "apps\theia-desktop"
$mobileRoot = Join-Path $repoRoot "apps\mobile"
$runRoot = Join-Path $repoRoot ".dubhe-run"
$startCmd = Join-Path $repoRoot "Start-Dubhe.cmd"
$startLanCmd = Join-Path $repoRoot "Start-Dubhe-LAN.cmd"
$installGuideCmd = Join-Path $repoRoot "Open-Dubhe-Install-Guide.cmd"
$mobileGuideCmd = Join-Path $repoRoot "Open-Dubhe-Mobile-Guide.cmd"
$checkCmd = Join-Path $repoRoot "Check-Dubhe.cmd"
$smokeCmd = Join-Path $repoRoot "Smoke-Dubhe.cmd"
$stopCmd = Join-Path $repoRoot "Stop-Dubhe-Core.cmd"
$configureCmd = Join-Path $repoRoot "Configure-Dubhe.cmd"
$localConfigPath = Join-Path $repoRoot "config\dubhe.local.env"
$localConfigExamplePath = Join-Path $repoRoot "config\dubhe.local.env.example"
$shortcutInstaller = Join-Path $repoRoot "scripts\install-windows-shortcuts.ps1"
$coreRunScript = Join-Path $coreRoot "scripts\run.ps1"
$coreTestScript = Join-Path $coreRoot "scripts\test.ps1"
$coreSmokeScript = Join-Path $repoRoot "scripts\smoke-core-workflow.ps1"
$desktopExe = Join-Path $theiaRoot "app\dist\win-unpacked\Dubhe.exe"
$desktopDist = Join-Path $theiaRoot "app\dist"
$windowsSetup = Resolve-NewestFile $desktopDist "Dubhe-*-win-x64-setup.exe"
$windowsPortable = Resolve-NewestFile $desktopDist "Dubhe-*-win-x64-portable.exe"
$mobileDebugApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
$mobileReleaseAab = Join-Path $mobileRoot "build\app\outputs\bundle\release\app-release.aab"
$nodeExe = Resolve-ToolCommand "node" (Join-Path $env:LOCALAPPDATA "DubheToolchains\node-v22.23.1-win-x64\node.exe")
$yarnCmd = Resolve-ToolCommand "yarn" (Join-Path $env:LOCALAPPDATA "DubheToolchains\node-v22.23.1-win-x64\yarn.cmd")
$flutterExe = Resolve-ToolCommand "flutter" (Join-Path $env:LOCALAPPDATA "DubheToolchains\flutter\bin\flutter.bat")
$jdkHome = Join-Path $env:LOCALAPPDATA "DubheToolchains\jdk-17"
$androidSdk = Join-Path $env:LOCALAPPDATA "DubheToolchains\android-sdk"
$corePort = ([System.Uri]$CoreUrl).Port
$lanCoreUrls = @(Get-LanCoreUrls -Port $corePort)

$checks = [System.Collections.Generic.List[object]]::new()

Add-Check (New-Check "仓库" "根目录" "ok" $repoRoot)
Add-Check (New-Check "Windows 入口" "双击启动" ($(if (Test-Path $startCmd) { "ok" } else { "warn" })) ($(if (Test-Path $startCmd) { $startCmd } else { "缺少 Start-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击手机局域网启动" ($(if (Test-Path $startLanCmd) { "ok" } else { "warn" })) ($(if (Test-Path $startLanCmd) { $startLanCmd } else { "缺少 Start-Dubhe-LAN.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击四端安装向导" ($(if (Test-Path $installGuideCmd) { "ok" } else { "warn" })) ($(if (Test-Path $installGuideCmd) { $installGuideCmd } else { "缺少 Open-Dubhe-Install-Guide.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击手机连接向导" ($(if (Test-Path $mobileGuideCmd) { "ok" } else { "warn" })) ($(if (Test-Path $mobileGuideCmd) { $mobileGuideCmd } else { "缺少 Open-Dubhe-Mobile-Guide.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击体检" ($(if (Test-Path $checkCmd) { "ok" } else { "warn" })) ($(if (Test-Path $checkCmd) { $checkCmd } else { "缺少 Check-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击烟测" ($(if (Test-Path $smokeCmd) { "ok" } else { "warn" })) ($(if (Test-Path $smokeCmd) { $smokeCmd } else { "缺少 Smoke-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击停止 Core" ($(if (Test-Path $stopCmd) { "ok" } else { "warn" })) ($(if (Test-Path $stopCmd) { $stopCmd } else { "缺少 Stop-Dubhe-Core.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击配置" ($(if (Test-Path $configureCmd) { "ok" } else { "warn" })) ($(if (Test-Path $configureCmd) { $configureCmd } else { "缺少 Configure-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "快捷方式安装器" ($(if (Test-Path $shortcutInstaller) { "ok" } else { "warn" })) ($(if (Test-Path $shortcutInstaller) { $shortcutInstaller } else { "缺少 scripts/install-windows-shortcuts.ps1。" })))
Add-Check (New-Check "本地配置" "配置模板" ($(if (Test-Path $localConfigExamplePath) { "ok" } else { "warn" })) ($(if (Test-Path $localConfigExamplePath) { $localConfigExamplePath } else { "缺少 config/dubhe.local.env.example。" })))
Add-Check (New-Check "本地配置" "配置文件" ($(if (Test-Path $localConfigPath) { "ok" } else { "warn" })) ($(if (Test-Path $localConfigPath) { "已加载 $($loadedLocalConfigKeys.Count) 项：$localConfigPath" } else { "尚未创建；可双击 Configure-Dubhe.cmd 创建并填写模型/新闻源 Key。" })))
Add-Check (New-Check "Core" "运行脚本" ($(if (Test-Path $coreRunScript) { "ok" } else { "fail" })) ($(if (Test-Path $coreRunScript) { $coreRunScript } else { "缺少 services/core/scripts/run.ps1。" })) (-not (Test-Path $coreRunScript)))
Add-Check (New-Check "Core" "测试脚本" ($(if (Test-Path $coreTestScript) { "ok" } else { "warn" })) ($(if (Test-Path $coreTestScript) { $coreTestScript } else { "缺少测试脚本，后续无法一键验证 Core。" })))
Add-Check (New-Check "Core" "主链路烟测" ($(if (Test-Path $coreSmokeScript) { "ok" } else { "warn" })) ($(if (Test-Path $coreSmokeScript) { $coreSmokeScript } else { "缺少 scripts/smoke-core-workflow.ps1。" })))

$venvPython = Join-Path $coreRoot ".venv\Scripts\python.exe"
if (Test-Path $venvPython) {
    Add-Check (New-Check "Core" "Python 虚拟环境" "ok" $venvPython)
} elseif (Test-CommandAvailable "python") {
    Add-Check (New-Check "Core" "Python 虚拟环境" "warn" "尚未创建 .venv；首次启动会自动创建并安装依赖。")
} else {
    Add-Check (New-Check "Core" "Python" "fail" "未找到 python，Core 无法启动。" $true)
}

$coreReady = Test-CoreHealth -Url $CoreUrl
Add-Check (New-Check "Core" "服务状态" ($(if ($coreReady) { "ok" } else { "warn" })) ($(if ($coreReady) { "Core 已在 $CoreUrl 运行。" } else { "Core 当前未运行；执行 scripts/start-local-dubhe.ps1 会自动启动。" })))

$systemStatus = $null
if ($coreReady) {
    $systemStatus = Read-SystemStatus -Url $CoreUrl
    if ($systemStatus) {
        Add-Check (New-Check "Core" "系统体检接口" "ok" "已读取 /v1/system/status，版本 $($systemStatus.version)。")
        Add-Check (New-Check "交易" "实盘开关" ($(if ($systemStatus.trading.live_trading_enabled) { "fail" } else { "ok" })) ($(if ($systemStatus.trading.live_trading_enabled) { "实盘交易已开启，请确认风控和审批已完成。" } else { "实盘交易关闭，纸面交易可用。" })) ([bool]$systemStatus.trading.live_trading_enabled))
        foreach ($item in $systemStatus.config_items) {
            Add-Check (New-Check "数据源配置" $item.label_zh ($(if ($item.configured) { "ok" } else { "warn" })) $item.message_zh)
        }
    } else {
        Add-Check (New-Check "Core" "系统体检接口" "warn" "Core 可用，但 /v1/system/status 暂未返回；如果刚更新代码，请重启 Core。")
    }
} else {
    $envItems = @(
        @{ key = "FINNHUB_API_KEY"; label = "Finnhub 授权新闻源 Key" },
        @{ key = "ALPHA_VANTAGE_API_KEY"; label = "Alpha Vantage 新闻情绪 Key" },
        @{ key = "DUBHE_SEC_USER_AGENT"; label = "SEC EDGAR User-Agent" }
    )
    foreach ($item in $envItems) {
        $configured = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($item.key))
        Add-Check (New-Check "数据源配置" $item.label ($(if ($configured) { "ok" } else { "warn" })) ($(if ($configured) { "当前 PowerShell 会话已配置 $($item.key)。" } else { "当前 PowerShell 会话未配置 $($item.key)；实时授权源会跳过或使用默认值。" })))
    }
}

$packagedDesktopReady = Test-Path $desktopExe

if ($nodeExe) {
    Add-Check (New-Check "桌面端" "Node.js" "ok" $nodeExe)
} else {
    Add-Check (New-Check "桌面端" "Node.js" "fail" "未找到 Node.js；Theia 开发启动和打包不可用。" (-not $packagedDesktopReady))
}

if ($yarnCmd) {
    Add-Check (New-Check "桌面端" "Yarn" "ok" $yarnCmd)
} else {
    Add-Check (New-Check "桌面端" "Yarn" "fail" "未找到 Yarn 1；Theia 开发启动和打包不可用。" (-not $packagedDesktopReady))
}

if ($packagedDesktopReady) {
    Add-Check (New-Check "桌面端" "Windows 桌面产物" "ok" $desktopExe)
} else {
    Add-Check (New-Check "桌面端" "Windows 桌面产物" "warn" "未找到已打包 Dubhe.exe；启动脚本会回退到 Theia 开发启动。")
}

if ($windowsSetup) {
    Add-Check (New-Check "安装包" "Windows setup" "ok" $windowsSetup)
} else {
    Add-Check (New-Check "安装包" "Windows setup" "warn" "尚未生成 Windows setup；可在 apps/theia-desktop 执行 yarn --cwd app electron-builder --win nsis。")
}

if ($windowsPortable) {
    Add-Check (New-Check "安装包" "Windows portable" "ok" $windowsPortable)
} else {
    Add-Check (New-Check "安装包" "Windows portable" "warn" "尚未生成 Windows portable；可在 apps/theia-desktop 执行 yarn --cwd app electron-builder --win portable。")
}

if (Test-Path (Join-Path $theiaRoot "node_modules")) {
    Add-Check (New-Check "桌面端" "依赖目录" "ok" "apps/theia-desktop/node_modules 已存在。")
} else {
    Add-Check (New-Check "桌面端" "依赖目录" "warn" "尚未安装 Theia 依赖；首次运行开发启动前需要 yarn install。")
}

if ($flutterExe) {
    Add-Check (New-Check "移动端" "Flutter" "ok" $flutterExe)
} else {
    Add-Check (New-Check "移动端" "Flutter" "warn" "未找到 Flutter；不会影响 Core/桌面端，但无法本机打 Android 包。")
}

if (Test-Path $jdkHome) {
    Add-Check (New-Check "移动端" "JDK 17" "ok" $jdkHome)
} else {
    Add-Check (New-Check "移动端" "JDK 17" "warn" "未找到本地 JDK 17 工具链；Android 构建可能不可用。")
}

if (Test-Path $androidSdk) {
    Add-Check (New-Check "移动端" "Android SDK" "ok" $androidSdk)
} else {
    Add-Check (New-Check "移动端" "Android SDK" "warn" "未找到本地 Android SDK；Android 构建可能不可用。")
}

if (Test-Path $mobileDebugApk) {
    Add-Check (New-Check "安装包" "Android debug APK" "ok" $mobileDebugApk)
} else {
    Add-Check (New-Check "安装包" "Android debug APK" "warn" "尚未生成 debug APK；可在 apps/mobile 执行 flutter build apk --debug。")
}

if (Test-Path $mobileReleaseAab) {
    Add-Check (New-Check "安装包" "Android release AAB" "ok" $mobileReleaseAab)
} else {
    Add-Check (New-Check "安装包" "Android release AAB" "warn" "尚未生成 release AAB；正式分发前还需要签名、图标和商店元数据。")
}

Add-Check (New-Check "安装包" "macOS / iOS" "warn" "当前 Windows 本机不能生成 macOS/iOS 包；请在 macOS runner 启用 docs/ci/theia-desktop.yml 和 docs/ci/mobile.yml。")

if ($lanCoreUrls.Count -eq 0) {
    Add-Check (New-Check "移动端" "手机连接地址" "warn" "未检测到可用局域网 IPv4 地址；真机需要电脑和手机在同一 Wi-Fi/局域网。")
} elseif ($coreReady -and (Test-CoreLanListener -Port $corePort)) {
    Add-Check (New-Check "移动端" "手机连接地址" "ok" "手机登录页 Core 地址可填：$($lanCoreUrls -join ' 或 ')")
} else {
    Add-Check (New-Check "移动端" "手机连接地址" "warn" "候选地址：$($lanCoreUrls -join ' 或 ')；当前 Core 未对局域网开放，真机连接请双击 Start-Dubhe-LAN.cmd。")
}

Add-Check (New-Check "日志" "本地运行目录" "ok" $runRoot)

$blockingCount = @($checks | Where-Object { $_.blocking }).Count
$warnCount = @($checks | Where-Object { $_.status -eq "warn" }).Count
$failCount = @($checks | Where-Object { $_.status -eq "fail" }).Count

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    core_url = $CoreUrl
    blocking_count = $blockingCount
    warning_count = $warnCount
    failure_count = $failCount
    checks = $checks
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Host "Dubhe 本机体检"
    Write-Host "Core 地址：$CoreUrl"
    Write-Host ""
    foreach ($check in $checks) {
        Write-CheckLine $check
    }
    Write-Host ""
    if ($blockingCount -gt 0) {
        Write-Host "结论：发现 $blockingCount 个阻断项，请先处理后再启动 Dubhe。"
    } elseif ($warnCount -gt 0 -or $failCount -gt 0) {
        Write-Host "结论：可以继续本地体验，但有 $warnCount 个提示项和 $failCount 个非阻断缺失项需要后续补齐。"
    } else {
        Write-Host "结论：本机环境已准备好。"
    }
}

if ($blockingCount -gt 0) {
    exit 1
}
