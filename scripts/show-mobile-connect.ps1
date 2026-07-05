param(
    [int]$CorePort = 8000,
    [switch]$StartLan,
    [switch]$OpenHtml,
    [switch]$OpenText,
    [switch]$NoClipboard
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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

function ConvertTo-HtmlText {
    param([string]$Value)

    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function Get-ToolPython {
    param([string]$RepoRoot)

    $corePython = Join-Path $RepoRoot "services\core\.venv\Scripts\python.exe"
    if (Test-Path $corePython) {
        return $corePython
    }
    $systemPython = Get-Command python -ErrorAction SilentlyContinue
    if ($systemPython) {
        return $systemPython.Source
    }
    return $null
}

function Invoke-QrGenerator {
    param(
        [string]$RepoRoot,
        [string]$Text,
        [string]$OutputPath,
        [switch]$AllowSetup
    )

    $python = Get-ToolPython -RepoRoot $RepoRoot
    $qrScript = Join-Path $RepoRoot "scripts\generate-qr-svg.py"
    if (-not $python -or -not (Test-Path $qrScript)) {
        return [pscustomobject]@{ ok = $false; message = "未找到 Python 或二维码脚本。" }
    }

    $output = & $python $qrScript --text $Text --output $OutputPath 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($exitCode -eq 0 -and (Test-Path $OutputPath)) {
        return [pscustomobject]@{ ok = $true; message = "二维码已生成：$OutputPath" }
    }

    if ($AllowSetup) {
        $setupScript = Join-Path $RepoRoot "services\core\scripts\setup.ps1"
        if (Test-Path $setupScript) {
            Write-Host "正在准备本地二维码工具；如果这是第一次运行，可能需要几十秒..."
            try {
                & $setupScript | Out-Null
                return Invoke-QrGenerator -RepoRoot $RepoRoot -Text $Text -OutputPath $OutputPath
            } catch {
                return [pscustomobject]@{ ok = $false; message = "二维码工具安装失败：$($_.Exception.Message)" }
            }
        }
    }

    return [pscustomobject]@{ ok = $false; message = "二维码生成失败：$($output -join ' ')" }
}

function New-MobileConnectHtml {
    param(
        [string]$PrimaryUrl,
        [string[]]$LanUrls,
        [string]$ApkPath,
        [string]$QrFileName,
        [bool]$QrAvailable,
        [string]$QrMessage,
        [string]$TextReportPath
    )

    $encodedPrimary = ConvertTo-HtmlText $PrimaryUrl
    $encodedApk = ConvertTo-HtmlText $ApkPath
    $encodedTextReport = ConvertTo-HtmlText $TextReportPath
    $encodedQrMessage = ConvertTo-HtmlText $QrMessage
    $urlItems = ($LanUrls | ForEach-Object {
        $encodedUrl = ConvertTo-HtmlText $_
        "<li><code>$encodedUrl</code><button data-copy=`"$encodedUrl`">复制</button></li>"
    }) -join "`n"
    $qrBlock = if ($QrAvailable) {
        "<img class=`"qr`" src=`"$QrFileName`" alt=`"Dubhe Core URL QR code`">"
    } else {
        "<div class=`"qr-missing`">暂未生成二维码<br><span>$encodedQrMessage</span></div>"
    }

    return @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Dubhe 手机连接卡</title>
  <style>
    :root { color-scheme: light; font-family: "Microsoft YaHei", "Segoe UI", sans-serif; }
    body { margin: 0; background: #f6f7f9; color: #1b1f24; }
    main { max-width: 980px; margin: 0 auto; padding: 32px 20px 44px; }
    h1 { margin: 0 0 8px; font-size: 32px; line-height: 1.2; }
    p { line-height: 1.7; }
    .panel { background: #fff; border: 1px solid #d8dee4; border-radius: 8px; padding: 22px; margin-top: 18px; }
    .hero { display: grid; grid-template-columns: minmax(0, 1fr) 260px; gap: 24px; align-items: center; }
    .primary-url { font-size: 28px; font-weight: 700; word-break: break-all; margin: 12px 0; }
    .qr { width: 240px; height: 240px; background: #fff; border: 1px solid #d8dee4; padding: 10px; }
    .qr-missing { width: 240px; min-height: 190px; border: 1px dashed #8c959f; display: grid; place-content: center; text-align: center; padding: 24px; color: #57606a; }
    .qr-missing span { font-size: 13px; }
    ol, ul { padding-left: 22px; line-height: 1.8; }
    li { margin: 6px 0; }
    code { background: #eef1f4; border-radius: 6px; padding: 2px 6px; word-break: break-all; }
    button { border: 1px solid #1f6feb; background: #1f6feb; color: #fff; border-radius: 6px; padding: 8px 12px; margin-left: 8px; cursor: pointer; }
    .muted { color: #57606a; }
    .ok { color: #116329; font-weight: 700; }
    @media (max-width: 760px) {
      .hero { grid-template-columns: 1fr; }
      .primary-url { font-size: 22px; }
    }
  </style>
</head>
<body>
  <main>
    <h1>Dubhe 手机连接卡</h1>
    <p class="muted">电脑和手机必须在同一个 Wi-Fi / 局域网。这个页面只保存在本机 <code>.dubhe-run</code>，不会上传任何密钥。</p>

    <section class="panel hero">
      <div>
        <div class="ok">手机登录页的 Core 地址</div>
        <div class="primary-url" id="primaryUrl">$encodedPrimary</div>
        <button data-copy="$encodedPrimary">复制地址</button>
        <p>如果手机能扫码，直接扫右侧二维码；不能扫码时，把上面的地址填入移动端登录页的 “Core 地址”。</p>
      </div>
      <div>$qrBlock</div>
    </section>

    <section class="panel">
      <h2>最快步骤</h2>
      <ol>
        <li>保持这个电脑窗口不要关闭。</li>
        <li>手机安装 Android APK：<code>$encodedApk</code></li>
        <li>手机打开 Dubhe，登录页填写或扫描 Core 地址。</li>
        <li>点击 “检查连接”，成功后注册或登录同一个本地账号。</li>
        <li>连接失败时，确认 Windows 防火墙允许专用网络访问，并让手机和电脑连接同一个 Wi-Fi。</li>
      </ol>
    </section>

    <section class="panel">
      <h2>候选地址</h2>
      <ul>$urlItems</ul>
      <p class="muted">文本版说明：<code>$encodedTextReport</code></p>
    </section>
  </main>
  <script>
    document.querySelectorAll("button[data-copy]").forEach((button) => {
      button.addEventListener("click", async () => {
        const text = button.getAttribute("data-copy");
        try {
          await navigator.clipboard.writeText(text);
          button.textContent = "已复制";
        } catch {
          button.textContent = "请手动复制";
        }
      });
    });
  </script>
</body>
</html>
"@
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
$htmlPath = Join-Path $runRoot "mobile-connect.html"
$textPath = Join-Path $runRoot "mobile-connect.txt"
$urlPath = Join-Path $runRoot "mobile-core-url.txt"
$qrPath = Join-Path $runRoot "mobile-core-url.svg"
$apkPath = Join-Path $repoRoot "apps\mobile\build\app\outputs\flutter-apk\app-debug.apk"

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

if ($StartLan) {
    Write-Host "提示：连接卡脚本不再内嵌重启 Core；请双击 Connect-Dubhe-Mobile.cmd，它会先启动局域网 Core，再生成本连接卡。"
}

$lanUrls = @(Get-LanCoreUrls -Port $CorePort)
$primaryUrl = if ($lanUrls.Count -gt 0) { $lanUrls[0] } else { "" }
$apkText = if (Test-Path $apkPath) { $apkPath } else { "$apkPath (not built yet)" }

if ([string]::IsNullOrWhiteSpace($primaryUrl)) {
    $message = "未检测到局域网 IPv4 地址。请让电脑和手机连接同一个 Wi-Fi 后重试。"
    Set-Content -Path $textPath -Encoding UTF8 -Value @("Dubhe 手机连接卡", "", $message)
    Write-Host $message
    Write-Host "文本说明：$textPath"
    exit 1
}

$clipboardMessage = "未复制到剪贴板。"
if (-not $NoClipboard) {
    try {
        Set-Clipboard -Value $primaryUrl
        $clipboardMessage = "已复制首选 Core 地址到 Windows 剪贴板：$primaryUrl"
    } catch {
        $clipboardMessage = "剪贴板复制失败：$($_.Exception.Message)"
    }
}

$qrResult = Invoke-QrGenerator -RepoRoot $repoRoot -Text $primaryUrl -OutputPath $qrPath -AllowSetup
$qrAvailable = [bool]$qrResult.ok

$textLines = @(
    "Dubhe 手机连接卡",
    "",
    "手机登录页 Core 地址：$primaryUrl",
    "其他候选地址：$($lanUrls -join ' / ')",
    "Android APK：$apkText",
    "二维码：$(if ($qrAvailable) { $qrPath } else { '未生成；请使用文本地址。' })",
    "LAN 启动说明：连接卡本身不重启 Core；双击 Connect-Dubhe-Mobile.cmd 会先启动局域网 Core。",
    "",
    "最快步骤：",
    "1. 手机和电脑连接同一个 Wi-Fi / 局域网。",
    "2. 手机安装 Android APK。",
    "3. 手机打开 Dubhe，在登录页填写或扫描 Core 地址。",
    "4. 点击检查连接，成功后注册或登录同一个本地账号。",
    "5. 如果连接失败，请允许 Windows 防火墙专用网络访问，然后重新双击 Connect-Dubhe-Mobile.cmd。",
    "",
    $clipboardMessage,
    $qrResult.message
)

Set-Content -Path $textPath -Encoding UTF8 -Value $textLines
Set-Content -Path $urlPath -Encoding ASCII -Value $primaryUrl

$html = New-MobileConnectHtml `
    -PrimaryUrl $primaryUrl `
    -LanUrls $lanUrls `
    -ApkPath $apkText `
    -QrFileName (Split-Path -Leaf $qrPath) `
    -QrAvailable $qrAvailable `
    -QrMessage $qrResult.message `
    -TextReportPath $textPath
Set-Content -Path $htmlPath -Encoding UTF8 -Value $html

Write-Host "Dubhe 手机连接卡"
Write-Host "Core 地址：$primaryUrl"
Write-Host $clipboardMessage
Write-Host $qrResult.message
Write-Host "HTML：$htmlPath"
Write-Host "文本：$textPath"

if ($OpenHtml) {
    Start-Process -FilePath $htmlPath
}
if ($OpenText) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($textPath)
}
