param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$AccessToken = "",
    [string]$AccountKey = "",
    [string]$DeviceName = "Windows 审计验证器",
    [switch]$Json,
    [switch]$OpenReport
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
$textReportPath = Join-Path $runRoot "audit-chain-verification.txt"
$jsonReportPath = Join-Path $runRoot "audit-chain-verification.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

function Read-CoreJson {
    param(
        [string]$Url,
        [hashtable]$Headers = @{}
    )

    $response = Invoke-WebRequest -Uri $Url -Headers $Headers -TimeoutSec 20 -UseBasicParsing
    if ($response.RawContentStream) {
        $response.RawContentStream.Position = 0
        $memory = [System.IO.MemoryStream]::new()
        $response.RawContentStream.CopyTo($memory)
        $body = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
        return $body | ConvertFrom-Json
    }
    return $response.Content | ConvertFrom-Json
}

function Invoke-CoreJson {
    param(
        [ValidateSet("Get", "Post")]
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $headers = @{ Accept = "application/json" }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }
    $uri = "$CoreUrl$Path"
    if ($null -eq $Body) {
        return Read-CoreJson -Url $uri -Headers $headers
    }

    $jsonBody = $Body | ConvertTo-Json -Depth 20
    $response = Invoke-WebRequest `
        -Method $Method `
        -Uri $uri `
        -Headers $headers `
        -ContentType "application/json; charset=utf-8" `
        -Body $utf8NoBom.GetBytes($jsonBody) `
        -TimeoutSec 20 `
        -UseBasicParsing
    if ($response.RawContentStream) {
        $response.RawContentStream.Position = 0
        $memory = [System.IO.MemoryStream]::new()
        $response.RawContentStream.CopyTo($memory)
        $bodyText = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
        return $bodyText | ConvertFrom-Json
    }
    return $response.Content | ConvertFrom-Json
}

function Get-StatusCode {
    param([object]$ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    if ($response -and $response.StatusCode) {
        return [int]$response.StatusCode
    }
    return $null
}

$reportLines = [System.Collections.Generic.List[string]]::new()
function Write-ReportLine {
    param([string]$Message = "")

    if (-not $Json) {
        Write-Host $Message
    }
    $script:reportLines.Add($Message) | Out-Null
}

$status = "failed"
$sessionRole = $null
$sessionAccountKey = $AccountKey
$verification = $null
$message = ""

try {
    if ([string]::IsNullOrWhiteSpace($sessionAccountKey)) {
        $sessionAccountKey = [Environment]::GetEnvironmentVariable("DUBHE_AUDIT_ACCOUNT_KEY")
    }
    if ([string]::IsNullOrWhiteSpace($sessionAccountKey)) {
        $sessionAccountKey = "local-demo"
    }

    $health = Read-CoreJson -Url "$CoreUrl/health"
    if ($health.status -ne "ok" -or $health.service -ne "dubhe-core") {
        throw "Core 健康检查没有返回 ok。"
    }

    $token = $AccessToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        $session = Invoke-CoreJson -Method Post -Path "/v1/auth/devices/register" -Body @{
            account_key = $sessionAccountKey
            account_name = "本机审计验证"
            device_name = $DeviceName
            platform = "windows"
        }
        $token = $session.access_token
        $sessionRole = $session.role
    } else {
        $sessionRole = "provided-token"
    }

    try {
        $verification = Invoke-CoreJson -Method Get -Path "/v1/audit/chain/verify" -Token $token
    } catch {
        $code = Get-StatusCode -ErrorRecord $_
        if ($code -eq 401 -or $code -eq 403) {
            throw "当前令牌没有审计验证权限。请使用管理员或风控管理员账号，或把 DUBHE_AUDIT_ACCOUNT_KEY 设置为有权限的本机账号。"
        }
        throw
    }

    $status = if ($verification.ok) { "passed" } else { "failed" }
    $message = $verification.message_zh
} catch {
    $message = $_.Exception.Message
    $status = "failed"
}

$jsonReport = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    status = $status
    core_url = $CoreUrl
    account_key = $sessionAccountKey
    role = $sessionRole
    verification = $verification
    message = $message
    text_report_path = $textReportPath
    json_report_path = $jsonReportPath
}

if ($Json) {
    $jsonReport | ConvertTo-Json -Depth 12
} else {
    Write-ReportLine "Dubhe 本地审计链验证"
    Write-ReportLine "Core 地址：$CoreUrl"
    Write-ReportLine "账号：$sessionAccountKey"
    if ($sessionRole) {
        Write-ReportLine "角色：$sessionRole"
    }
    Write-ReportLine ""
    if ($status -eq "passed") {
        Write-ReportLine "[OK] $message"
        if ($verification.latest_sequence) {
            Write-ReportLine "最新序号：$($verification.latest_sequence)"
            Write-ReportLine "最新哈希：$($verification.latest_hash)"
        }
    } else {
        Write-ReportLine "[需处理] $message"
        if ($verification -and $verification.first_broken_sequence) {
            Write-ReportLine "首个异常序号：$($verification.first_broken_sequence)"
        }
    }
    Write-ReportLine ""
    Write-ReportLine "文本报告：$textReportPath"
    Write-ReportLine "JSON 报告：$jsonReportPath"
    Write-ReportLine "说明：这是本地 SQLite 审计日志的防篡改校验，不等同于生产级 WORM 或外部不可变审计存储。"
}

Set-Content -Path $textReportPath -Encoding UTF8 -Value $reportLines
$jsonReport | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonReportPath -Encoding UTF8

if ($OpenReport -and -not $Json) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($textReportPath)
}

if ($status -ne "passed") {
    exit 1
}
exit 0
