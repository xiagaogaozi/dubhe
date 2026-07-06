param(
    [string]$RepoRoot = "",
    [string]$Issuer = "Dubhe",
    [string]$AccountName = "local-admin",
    [switch]$RotateSecret,
    [switch]$OpenReport
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Get-ActiveConfigValues {
    param([string]$Path)

    $values = @{}
    if (-not (Test-Path $Path)) {
        return $values
    }

    foreach ($line in Get-Content -Encoding UTF8 $Path) {
        $trimmed = $line.Trim().TrimStart([char]0xFEFF)
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#") -or $trimmed.StartsWith(";")) {
            continue
        }
        $separatorIndex = $trimmed.IndexOf("=")
        if ($separatorIndex -le 0) {
            continue
        }
        $key = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if (
            ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) -or
            ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2)
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }
    return $values
}

function Set-DubheConfigValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $Path) {
        foreach ($line in Get-Content -Encoding UTF8 $Path) {
            $lines.Add($line) | Out-Null
        }
    }

    $replacement = "$Key=$Value"
    $pattern = "^\s*#?\s*$([regex]::Escape($Key))\s*="
    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        if ($lines[$index] -match $pattern) {
            $lines[$index] = $replacement
            Set-Content -Path $Path -Encoding UTF8 -Value $lines
            return
        }
    }

    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.Add("") | Out-Null
    }
    $lines.Add($replacement) | Out-Null
    Set-Content -Path $Path -Encoding UTF8 -Value $lines
}

function New-Base32Secret {
    param([int]$ByteCount = 20)

    $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bytes = New-Object byte[] $ByteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }

    $builder = [System.Text.StringBuilder]::new()
    [int]$buffer = 0
    [int]$bitsLeft = 0
    foreach ($byte in $bytes) {
        $buffer = ($buffer -shl 8) -bor [int]$byte
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $index = ($buffer -shr ($bitsLeft - 5)) -band 31
            [void]$builder.Append($alphabet[$index])
            $bitsLeft -= 5
        }
        if ($bitsLeft -gt 0) {
            $buffer = $buffer -band ((1 -shl $bitsLeft) - 1)
        } else {
            $buffer = 0
        }
    }
    if ($bitsLeft -gt 0) {
        $index = ($buffer -shl (5 - $bitsLeft)) -band 31
        [void]$builder.Append($alphabet[$index])
    }
    return $builder.ToString()
}

function ConvertTo-HtmlText {
    param([string]$Value)
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$configDir = Join-Path $RepoRoot "config"
$examplePath = Join-Path $configDir "dubhe.local.env.example"
$localPath = Join-Path $configDir "dubhe.local.env"
$runRoot = Join-Path $RepoRoot ".dubhe-run"
$textReportPath = Join-Path $runRoot "local-mfa.txt"
$htmlReportPath = Join-Path $runRoot "local-mfa.html"
$qrPath = Join-Path $runRoot "local-mfa.svg"

New-Item -ItemType Directory -Force -Path $configDir, $runRoot | Out-Null
if (-not (Test-Path $localPath)) {
    if (-not (Test-Path $examplePath)) {
        throw "Template not found: $examplePath"
    }
    Copy-Item -LiteralPath $examplePath -Destination $localPath
}

$currentValues = Get-ActiveConfigValues -Path $localPath
$secret = $currentValues["DUBHE_LOCAL_TOTP_SECRET"]
if ([string]::IsNullOrWhiteSpace($secret) -or $RotateSecret) {
    $secret = New-Base32Secret
}

Set-DubheConfigValue -Path $localPath -Key "DUBHE_LOCAL_MFA_MODE" -Value "totp"
Set-DubheConfigValue -Path $localPath -Key "DUBHE_LOCAL_TOTP_SECRET" -Value $secret
Set-DubheConfigValue -Path $localPath -Key "DUBHE_LOCAL_TOTP_ISSUER" -Value $Issuer
Set-DubheConfigValue -Path $localPath -Key "DUBHE_LOCAL_TOTP_ACCOUNT" -Value $AccountName

$label = [uri]::EscapeDataString("$Issuer`:$AccountName")
$query = "secret=$secret&issuer=$([uri]::EscapeDataString($Issuer))&algorithm=SHA1&digits=6&period=30"
$otpauthUri = "otpauth://totp/$label`?$query"

$qrGenerated = $false
$qrGenerator = Join-Path $RepoRoot "scripts\generate-qr-svg.py"
$venvPython = Join-Path $RepoRoot "services\core\.venv\Scripts\python.exe"
$pythonCommand = $null
if (Test-Path $venvPython) {
    $pythonCommand = $venvPython
} else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $pythonCommand = $python.Source
    }
}
if ($pythonCommand -and (Test-Path $qrGenerator)) {
    try {
        & $pythonCommand $qrGenerator --text $otpauthUri --output $qrPath | Out-Null
        $qrGenerated = (Test-Path $qrPath)
    } catch {
        $qrGenerated = $false
    }
}

$createdText = if ($RotateSecret) { "已生成新的 TOTP 密钥。" } else { "已配置 TOTP；如已有密钥则已复用原密钥。" }
$qrText = if ($qrGenerated) { "二维码：$qrPath" } else { "二维码未生成；请手动复制 otpauth 链接到认证器 App。" }
$reportLines = @(
    "Dubhe 本地 MFA 设置",
    "",
    $createdText,
    "配置文件：$localPath",
    "发行方：$Issuer",
    "账号名：$AccountName",
    "密钥：$secret",
    "",
    "认证器链接：",
    $otpauthUri,
    "",
    $qrText,
    "",
    "下一步：",
    "1. 用 Microsoft Authenticator、Google Authenticator、1Password 等认证器 App 扫描二维码，或手动输入密钥。",
    "2. 重新启动 Dubhe Core。",
    "3. 注册或登录账号时，填写认证器 App 中显示的 6 位动态验证码。",
    "",
    "注意：这是本机 TOTP 兜底，不等同于生产级 OIDC、正式 MFA、刷新令牌和集中身份审计。"
)
$reportLines | Out-File -FilePath $textReportPath -Encoding UTF8

$qrHtml = if ($qrGenerated) {
    '<p><img src="local-mfa.svg" alt="Dubhe MFA QR code" /></p>'
} else {
    '<p>二维码未生成，请复制下面的认证器链接。</p>'
}
$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <title>Dubhe 本地 MFA 设置</title>
  <style>
    body { font-family: "Microsoft YaHei", "Segoe UI", sans-serif; margin: 32px; color: #1f2937; }
    main { max-width: 760px; }
    code, pre { background: #f3f4f6; border-radius: 6px; padding: 10px; white-space: pre-wrap; word-break: break-all; }
    img { width: 260px; height: 260px; }
    .warning { border-left: 4px solid #b45309; padding-left: 12px; color: #92400e; }
  </style>
</head>
<body>
  <main>
    <h1>Dubhe 本地 MFA 设置</h1>
    <p>$([System.Net.WebUtility]::HtmlEncode($createdText))</p>
    $qrHtml
    <p>认证器 App 无法扫码时，请手动输入这个密钥：</p>
    <pre>$(ConvertTo-HtmlText $secret)</pre>
    <p>高级方式：复制完整 otpauth 链接。</p>
    <pre>$(ConvertTo-HtmlText $otpauthUri)</pre>
    <p>重新启动 Dubhe Core 后，注册或登录账号时填写认证器 App 中显示的 6 位动态验证码。</p>
    <p class="warning">这是本机 TOTP 兜底，不等同于生产级 OIDC、正式 MFA、刷新令牌和集中身份审计。</p>
  </main>
</body>
</html>
"@
$html | Out-File -FilePath $htmlReportPath -Encoding UTF8

Write-Host "Dubhe 本地 MFA 设置完成"
Write-Host "配置文件：$localPath"
Write-Host "说明文件：$textReportPath"
Write-Host "网页说明：$htmlReportPath"
if ($qrGenerated) {
    Write-Host "二维码：$qrPath"
} else {
    Write-Host "二维码未生成；请打开说明文件复制认证器链接。"
}
Write-Host "请重新启动 Dubhe Core 后再登录。"

if ($OpenReport) {
    Start-Process -FilePath $htmlReportPath | Out-Null
}
