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

function Get-DubheCoreListeners {
    $processes = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*dubhe_core.main:app*" }
    )
    $processById = @{}
    foreach ($process in $processes) {
        $processById[[int]$process.ProcessId] = $process
    }
    $connections = @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $processById.ContainsKey([int]$_.OwningProcess) }
    )
    return @(
        $connections |
            Select-Object `
                @{ Name = "Port"; Expression = { [int]$_.LocalPort } },
                @{ Name = "Pid"; Expression = { [int]$_.OwningProcess } },
                @{ Name = "Address"; Expression = { $_.LocalAddress } } |
            Sort-Object Port, Pid -Unique
    )
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

function Read-AuditChainVerification {
    param(
        [string]$Url,
        [string]$ScriptPath
    )

    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -CoreUrl $Url -Json 2>&1
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        $text = (@($output | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "审计链验证未返回 JSON。"
        }
        $report = $text | ConvertFrom-Json
        return [pscustomobject]@{
            exit_code = $exitCode
            report = $report
        }
    } catch {
        return [pscustomobject]@{
            exit_code = 1
            report = $null
            error = $_.Exception.Message
        }
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
$connectMobileCmd = Join-Path $repoRoot "Connect-Dubhe-Mobile.cmd"
$userKitCmd = Join-Path $repoRoot "Build-Dubhe-User-Kit.cmd"
$deliveryCmd = Join-Path $repoRoot "Prepare-Dubhe-Delivery.cmd"
$deliveryVerifyCmd = Join-Path $repoRoot "Verify-Dubhe-Delivery.cmd"
$ciArtifactImportCmd = Join-Path $repoRoot "Import-Dubhe-CI-Artifacts.cmd"
$releaseEvidenceCmd = Join-Path $repoRoot "Export-Dubhe-Release-Evidence.cmd"
$githubActionsAuthorizeCmd = Join-Path $repoRoot "Authorize-Dubhe-GitHub-Actions.cmd"
$githubActionsCmd = Join-Path $repoRoot "Activate-Dubhe-GitHub-Actions.cmd"
$installGuideCmd = Join-Path $repoRoot "Open-Dubhe-Install-Guide.cmd"
$mobileGuideCmd = Join-Path $repoRoot "Open-Dubhe-Mobile-Guide.cmd"
$acceptCmd = Join-Path $repoRoot "Accept-Dubhe.cmd"
$auditVerifyCmd = Join-Path $repoRoot "Verify-Dubhe-Audit.cmd"
$checkCmd = Join-Path $repoRoot "Check-Dubhe.cmd"
$smokeCmd = Join-Path $repoRoot "Smoke-Dubhe.cmd"
$serviceCheckCmd = Join-Path $repoRoot "Test-Dubhe-Services.cmd"
$productionCheckCmd = Join-Path $repoRoot "Check-Dubhe-Production.cmd"
$productionPackCmd = Join-Path $repoRoot "Export-Dubhe-Production-Pack.cmd"
$stopCmd = Join-Path $repoRoot "Stop-Dubhe-Core.cmd"
$configureCmd = Join-Path $repoRoot "Configure-Dubhe.cmd"
$setupMfaCmd = Join-Path $repoRoot "Setup-Dubhe-MFA.cmd"
$localConfigPath = Join-Path $repoRoot "config\dubhe.local.env"
$localConfigExamplePath = Join-Path $repoRoot "config\dubhe.local.env.example"
$shortcutInstaller = Join-Path $repoRoot "scripts\install-windows-shortcuts.ps1"
$coreRunScript = Join-Path $coreRoot "scripts\run.ps1"
$coreTestScript = Join-Path $coreRoot "scripts\test.ps1"
$coreSmokeScript = Join-Path $repoRoot "scripts\smoke-core-workflow.ps1"
$localAcceptanceScript = Join-Path $repoRoot "scripts\run-local-acceptance.ps1"
$auditVerifyScript = Join-Path $repoRoot "scripts\verify-audit-chain.ps1"
$mobileConnectScript = Join-Path $repoRoot "scripts\show-mobile-connect.ps1"
$qrGeneratorScript = Join-Path $repoRoot "scripts\generate-qr-svg.py"
$productionPackScript = Join-Path $repoRoot "scripts\export-production-pack.ps1"
$deliveryVerifyScript = Join-Path $repoRoot "scripts\verify-delivery-pack.ps1"
$ciArtifactImportScript = Join-Path $repoRoot "scripts\import-ci-artifacts.ps1"
$releaseEvidenceScript = Join-Path $repoRoot "scripts\export-release-evidence.ps1"
$githubActionsAuthorizeScript = Join-Path $repoRoot "scripts\authorize-github-workflow-scope.ps1"
$githubActionsScript = Join-Path $repoRoot "scripts\activate-github-actions.ps1"
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
$coreListeners = @(Get-DubheCoreListeners)

$checks = [System.Collections.Generic.List[object]]::new()

Add-Check (New-Check "仓库" "根目录" "ok" $repoRoot)
Add-Check (New-Check "Windows 入口" "双击启动" ($(if (Test-Path $startCmd) { "ok" } else { "warn" })) ($(if (Test-Path $startCmd) { $startCmd } else { "缺少 Start-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击手机局域网启动" ($(if (Test-Path $startLanCmd) { "ok" } else { "warn" })) ($(if (Test-Path $startLanCmd) { $startLanCmd } else { "缺少 Start-Dubhe-LAN.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击手机扫码连接" ($(if (Test-Path $connectMobileCmd) { "ok" } else { "warn" })) ($(if (Test-Path $connectMobileCmd) { $connectMobileCmd } else { "缺少 Connect-Dubhe-Mobile.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击生成用户交付包" ($(if (Test-Path $userKitCmd) { "ok" } else { "warn" })) ($(if (Test-Path $userKitCmd) { $userKitCmd } else { "缺少 Build-Dubhe-User-Kit.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击生成最终交付 ZIP" ($(if (Test-Path $deliveryCmd) { "ok" } else { "warn" })) ($(if (Test-Path $deliveryCmd) { $deliveryCmd } else { "缺少 Prepare-Dubhe-Delivery.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击验证最终交付 ZIP" ($(if (Test-Path $deliveryVerifyCmd) { "ok" } else { "warn" })) ($(if (Test-Path $deliveryVerifyCmd) { $deliveryVerifyCmd } else { "缺少 Verify-Dubhe-Delivery.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击导入 CI 产物" ($(if (Test-Path $ciArtifactImportCmd) { "ok" } else { "warn" })) ($(if (Test-Path $ciArtifactImportCmd) { $ciArtifactImportCmd } else { "缺少 Import-Dubhe-CI-Artifacts.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击导出发行证据包" ($(if (Test-Path $releaseEvidenceCmd) { "ok" } else { "warn" })) ($(if (Test-Path $releaseEvidenceCmd) { $releaseEvidenceCmd } else { "缺少 Export-Dubhe-Release-Evidence.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击授权 GitHub Actions" ($(if (Test-Path $githubActionsAuthorizeCmd) { "ok" } else { "warn" })) ($(if (Test-Path $githubActionsAuthorizeCmd) { $githubActionsAuthorizeCmd } else { "缺少 Authorize-Dubhe-GitHub-Actions.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击激活 GitHub Actions" ($(if (Test-Path $githubActionsCmd) { "ok" } else { "warn" })) ($(if (Test-Path $githubActionsCmd) { $githubActionsCmd } else { "缺少 Activate-Dubhe-GitHub-Actions.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击四端安装向导" ($(if (Test-Path $installGuideCmd) { "ok" } else { "warn" })) ($(if (Test-Path $installGuideCmd) { $installGuideCmd } else { "缺少 Open-Dubhe-Install-Guide.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击手机连接向导" ($(if (Test-Path $mobileGuideCmd) { "ok" } else { "warn" })) ($(if (Test-Path $mobileGuideCmd) { $mobileGuideCmd } else { "缺少 Open-Dubhe-Mobile-Guide.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击本机完整验收" ($(if (Test-Path $acceptCmd) { "ok" } else { "warn" })) ($(if (Test-Path $acceptCmd) { $acceptCmd } else { "缺少 Accept-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击审计链验证" ($(if (Test-Path $auditVerifyCmd) { "ok" } else { "warn" })) ($(if (Test-Path $auditVerifyCmd) { $auditVerifyCmd } else { "缺少 Verify-Dubhe-Audit.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击体检" ($(if (Test-Path $checkCmd) { "ok" } else { "warn" })) ($(if (Test-Path $checkCmd) { $checkCmd } else { "缺少 Check-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击烟测" ($(if (Test-Path $smokeCmd) { "ok" } else { "warn" })) ($(if (Test-Path $smokeCmd) { $smokeCmd } else { "缺少 Smoke-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击外部服务体检" ($(if (Test-Path $serviceCheckCmd) { "ok" } else { "warn" })) ($(if (Test-Path $serviceCheckCmd) { $serviceCheckCmd } else { "缺少 Test-Dubhe-Services.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击生产就绪门禁" ($(if (Test-Path $productionCheckCmd) { "ok" } else { "warn" })) ($(if (Test-Path $productionCheckCmd) { $productionCheckCmd } else { "缺少 Check-Dubhe-Production.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击生产补齐包" ($(if (Test-Path $productionPackCmd) { "ok" } else { "warn" })) ($(if (Test-Path $productionPackCmd) { $productionPackCmd } else { "缺少 Export-Dubhe-Production-Pack.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击停止 Core" ($(if (Test-Path $stopCmd) { "ok" } else { "warn" })) ($(if (Test-Path $stopCmd) { $stopCmd } else { "缺少 Stop-Dubhe-Core.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击配置" ($(if (Test-Path $configureCmd) { "ok" } else { "warn" })) ($(if (Test-Path $configureCmd) { $configureCmd } else { "缺少 Configure-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击设置本地 MFA" ($(if (Test-Path $setupMfaCmd) { "ok" } else { "warn" })) ($(if (Test-Path $setupMfaCmd) { $setupMfaCmd } else { "缺少 Setup-Dubhe-MFA.cmd。" })))
Add-Check (New-Check "Windows 入口" "快捷方式安装器" ($(if (Test-Path $shortcutInstaller) { "ok" } else { "warn" })) ($(if (Test-Path $shortcutInstaller) { $shortcutInstaller } else { "缺少 scripts/install-windows-shortcuts.ps1。" })))
Add-Check (New-Check "本地配置" "配置模板" ($(if (Test-Path $localConfigExamplePath) { "ok" } else { "warn" })) ($(if (Test-Path $localConfigExamplePath) { $localConfigExamplePath } else { "缺少 config/dubhe.local.env.example。" })))
Add-Check (New-Check "本地配置" "配置文件" ($(if (Test-Path $localConfigPath) { "ok" } else { "warn" })) ($(if (Test-Path $localConfigPath) { "已加载 $($loadedLocalConfigKeys.Count) 项：$localConfigPath" } else { "尚未创建；可双击 Configure-Dubhe.cmd 创建并填写模型/新闻源 Key。" })))
Add-Check (New-Check "Core" "运行脚本" ($(if (Test-Path $coreRunScript) { "ok" } else { "fail" })) ($(if (Test-Path $coreRunScript) { $coreRunScript } else { "缺少 services/core/scripts/run.ps1。" })) (-not (Test-Path $coreRunScript)))
Add-Check (New-Check "Core" "测试脚本" ($(if (Test-Path $coreTestScript) { "ok" } else { "warn" })) ($(if (Test-Path $coreTestScript) { $coreTestScript } else { "缺少测试脚本，后续无法一键验证 Core。" })))
Add-Check (New-Check "Core" "主链路烟测" ($(if (Test-Path $coreSmokeScript) { "ok" } else { "warn" })) ($(if (Test-Path $coreSmokeScript) { $coreSmokeScript } else { "缺少 scripts/smoke-core-workflow.ps1。" })))
Add-Check (New-Check "Core" "本机完整验收" ($(if (Test-Path $localAcceptanceScript) { "ok" } else { "warn" })) ($(if (Test-Path $localAcceptanceScript) { $localAcceptanceScript } else { "缺少 scripts/run-local-acceptance.ps1。" })))
Add-Check (New-Check "Core" "审计链验证脚本" ($(if (Test-Path $auditVerifyScript) { "ok" } else { "warn" })) ($(if (Test-Path $auditVerifyScript) { $auditVerifyScript } else { "缺少 scripts/verify-audit-chain.ps1。" })))
Add-Check (New-Check "移动端" "手机连接卡脚本" ($(if (Test-Path $mobileConnectScript) { "ok" } else { "warn" })) ($(if (Test-Path $mobileConnectScript) { $mobileConnectScript } else { "缺少 scripts/show-mobile-connect.ps1。" })))
Add-Check (New-Check "移动端" "二维码生成脚本" ($(if (Test-Path $qrGeneratorScript) { "ok" } else { "warn" })) ($(if (Test-Path $qrGeneratorScript) { $qrGeneratorScript } else { "缺少 scripts/generate-qr-svg.py。" })))
Add-Check (New-Check "生产门禁" "生产补齐包脚本" ($(if (Test-Path $productionPackScript) { "ok" } else { "warn" })) ($(if (Test-Path $productionPackScript) { $productionPackScript } else { "缺少 scripts/export-production-pack.ps1。" })))
Add-Check (New-Check "交付包" "最终 ZIP 验证脚本" ($(if (Test-Path $deliveryVerifyScript) { "ok" } else { "warn" })) ($(if (Test-Path $deliveryVerifyScript) { $deliveryVerifyScript } else { "缺少 scripts/verify-delivery-pack.ps1。" })))
Add-Check (New-Check "交付包" "CI 产物导入脚本" ($(if (Test-Path $ciArtifactImportScript) { "ok" } else { "warn" })) ($(if (Test-Path $ciArtifactImportScript) { $ciArtifactImportScript } else { "缺少 scripts/import-ci-artifacts.ps1。" })))
Add-Check (New-Check "交付包" "发行证据包脚本" ($(if (Test-Path $releaseEvidenceScript) { "ok" } else { "warn" })) ($(if (Test-Path $releaseEvidenceScript) { $releaseEvidenceScript } else { "缺少 scripts/export-release-evidence.ps1。" })))
Add-Check (New-Check "交付包" "GitHub Actions 授权脚本" ($(if (Test-Path $githubActionsAuthorizeScript) { "ok" } else { "warn" })) ($(if (Test-Path $githubActionsAuthorizeScript) { $githubActionsAuthorizeScript } else { "缺少 scripts/authorize-github-workflow-scope.ps1。" })))
Add-Check (New-Check "交付包" "GitHub Actions 激活脚本" ($(if (Test-Path $githubActionsScript) { "ok" } else { "warn" })) ($(if (Test-Path $githubActionsScript) { $githubActionsScript } else { "缺少 scripts/activate-github-actions.ps1。" })))

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
$extraCorePorts = @(
    $coreListeners |
        Where-Object { $_.Port -ne $corePort } |
        Select-Object -ExpandProperty Port -Unique
)
if ($extraCorePorts.Count -gt 0) {
    Add-Check (New-Check "Core" "额外 Core 进程" "warn" "检测到其他 Dubhe Core 端口：$($extraCorePorts -join '、')；如非刻意多开，可双击 Stop-Dubhe-Core.cmd 后重新启动。")
} else {
    Add-Check (New-Check "Core" "额外 Core 进程" "ok" "未检测到其他 Dubhe Core 监听端口。")
}

$systemStatus = $null
if ($coreReady) {
    $systemStatus = Read-SystemStatus -Url $CoreUrl
    if ($systemStatus) {
        Add-Check (New-Check "Core" "系统体检接口" "ok" "已读取 /v1/system/status，版本 $($systemStatus.version)。")
        Add-Check (New-Check "账号安全" "本地 MFA 模式" ($(if ($systemStatus.auth.mfa_mode -eq "totp") { "ok" } else { "warn" })) ($(if ($systemStatus.auth.mfa_mode -eq "totp") { "已启用本机 TOTP 动态验证码。" } else { "当前仍是占位 MFA；可双击 Setup-Dubhe-MFA.cmd 启用本机动态验证码。" })))
        Add-Check (New-Check "交易" "实盘开关" ($(if ($systemStatus.trading.live_trading_enabled) { "fail" } else { "ok" })) ($(if ($systemStatus.trading.live_trading_enabled) { "实盘交易已开启，请确认风控和审批已完成。" } else { "实盘交易关闭，纸面交易可用。" })) ([bool]$systemStatus.trading.live_trading_enabled))
        foreach ($item in $systemStatus.config_items) {
            Add-Check (New-Check "数据源配置" $item.label_zh ($(if ($item.configured) { "ok" } else { "warn" })) $item.message_zh)
        }
        if (Test-Path $auditVerifyScript) {
            $auditVerification = Read-AuditChainVerification -Url $CoreUrl -ScriptPath $auditVerifyScript
            if ($auditVerification.report -and $auditVerification.report.verification -and $auditVerification.report.verification.ok) {
                Add-Check (New-Check "审计" "本地哈希链" "ok" $auditVerification.report.verification.message_zh)
            } elseif ($auditVerification.report -and $auditVerification.report.verification -and -not $auditVerification.report.verification.ok) {
                Add-Check (New-Check "审计" "本地哈希链" "fail" $auditVerification.report.verification.message_zh $true)
            } elseif ($auditVerification.report) {
                Add-Check (New-Check "审计" "本地哈希链" "warn" $auditVerification.report.message)
            } else {
                Add-Check (New-Check "审计" "本地哈希链" "warn" "暂未完成验证：$($auditVerification.error)")
            }
        }
    } else {
        Add-Check (New-Check "Core" "系统体检接口" "warn" "Core 可用，但 /v1/system/status 暂未返回；如果刚更新代码，请重启 Core。")
    }
} else {
    $envItems = @(
        @{ key = "FINNHUB_API_KEY"; label = "Finnhub 授权新闻源 Key" },
        @{ key = "ALPHA_VANTAGE_API_KEY"; label = "Alpha Vantage 新闻情绪 Key" },
        @{ key = "DUBHE_SEC_USER_AGENT"; label = "SEC EDGAR User-Agent" },
        @{ key = "DUBHE_PAPER_BROKER"; label = "Paper broker 适配器" },
        @{ key = "ALPACA_PAPER_API_KEY_ID"; label = "Alpaca Paper Key ID" },
        @{ key = "ALPACA_PAPER_SECRET_KEY"; label = "Alpaca Paper Secret" }
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
    Add-Check (New-Check "安装包" "Windows setup" "warn" "尚未生成 Windows setup；可在 apps/theia-desktop 执行 yarn dist:windows。")
}

if ($windowsPortable) {
    Add-Check (New-Check "安装包" "Windows portable" "ok" $windowsPortable)
} else {
    Add-Check (New-Check "安装包" "Windows portable" "warn" "尚未生成 Windows portable；可在 apps/theia-desktop 执行 yarn dist:windows。")
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

Add-Check (New-Check "安装包" "macOS / iOS" "warn" "当前 Windows 本机不能生成 macOS/iOS 包；请先运行 Authorize-Dubhe-GitHub-Actions.cmd 和 Activate-Dubhe-GitHub-Actions.cmd，再导入 GitHub Actions 产物。")

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
