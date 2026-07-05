param(
    [string]$RepoRoot = "",
    [switch]$Guided,
    [switch]$NoOpen,
    [switch]$PlainInput
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
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#") -or $trimmed.StartsWith(";")) {
            continue
        }
        $separatorIndex = $trimmed.IndexOf("=")
        if ($separatorIndex -le 0) {
            continue
        }
        $key = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        $values[$key] = $value
    }
    return $values
}

function ConvertFrom-SecureStringPlain {
    param([securestring]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Set-DubheConfigValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value,
        [switch]$Clear
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $Path) {
        foreach ($line in Get-Content -Encoding UTF8 $Path) {
            $lines.Add($line) | Out-Null
        }
    }

    $replacement = if ($Clear) { "# $Key=" } else { "$Key=$Value" }
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

function Read-GuidedConfigValue {
    param(
        [hashtable]$CurrentValues,
        [string]$Key,
        [string]$Label,
        [string]$Hint,
        [switch]$Secret,
        [switch]$PlainInput
    )

    $hasCurrent = $CurrentValues.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($CurrentValues[$Key])
    $currentText = if ($hasCurrent) {
        if ($Secret) { "已配置，直接回车会保留。" } else { "当前值：$($CurrentValues[$Key])" }
    } else {
        "当前未配置。"
    }

    Write-Host ""
    Write-Host "$Label"
    Write-Host $Hint
    Write-Host $currentText
    Write-Host "直接回车：保留/跳过；输入 - ：清空。"
    if ($Secret -and -not $PlainInput) {
        $secure = Read-Host "请输入 $Key" -AsSecureString
        return ConvertFrom-SecureStringPlain $secure
    }
    return Read-Host "请输入 $Key"
}

function Invoke-GuidedConfig {
    param(
        [string]$Path,
        [switch]$PlainInput
    )

    $items = @(
        @{
            key = "DUBHE_LLM_MODEL"
            label = "1. AI 模型名称"
            hint = "例如 gpt-4.1-mini，或你的本地/第三方 OpenAI-compatible 网关模型名。"
            secret = $false
        },
        @{
            key = "DUBHE_LLM_API_KEY"
            label = "2. AI 模型 API Key"
            hint = "从模型服务商控制台复制；本地无鉴权模型可以直接回车跳过。"
            secret = $true
        },
        @{
            key = "DUBHE_LLM_BASE_URL"
            label = "3. AI 模型地址"
            hint = "OpenAI 官方可留空；第三方或本地网关填写类似 https://example.com/v1。"
            secret = $false
        },
        @{
            key = "FINNHUB_API_KEY"
            label = "4. Finnhub 授权新闻 Key"
            hint = "用于美股公司新闻；没有授权 key 可直接回车，Dubhe 会继续使用演示/公开兜底。"
            secret = $true
        },
        @{
            key = "ALPHA_VANTAGE_API_KEY"
            label = "5. Alpha Vantage Key"
            hint = "用于全球新闻情绪补充；没有 key 可直接回车。"
            secret = $true
        },
        @{
            key = "DUBHE_SEC_USER_AGENT"
            label = "6. SEC EDGAR User-Agent"
            hint = "建议填写产品名和邮箱，例如 Dubhe/0.1 your-email@example.com。"
            secret = $false
        }
    )

    Write-Host "Dubhe 中文配置向导"
    Write-Host "配置文件：$Path"
    Write-Host "不会写代码也没关系；不知道的项目直接回车即可。"

    $currentValues = Get-ActiveConfigValues -Path $Path
    foreach ($item in $items) {
        $value = Read-GuidedConfigValue `
            -CurrentValues $currentValues `
            -Key $item.key `
            -Label $item.label `
            -Hint $item.hint `
            -Secret:([bool]$item.secret) `
            -PlainInput:$PlainInput
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        if ($value.Trim() -eq "-") {
            Set-DubheConfigValue -Path $Path -Key $item.key -Clear
        } else {
            Set-DubheConfigValue -Path $Path -Key $item.key -Value $value.Trim()
        }
        $currentValues = Get-ActiveConfigValues -Path $Path
    }

    Write-Host ""
    Write-Host "配置已保存。重新启动 Dubhe Core 后生效；数据库路径变更也需要重启。"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$configDir = Join-Path $RepoRoot "config"
$examplePath = Join-Path $configDir "dubhe.local.env.example"
$localPath = Join-Path $configDir "dubhe.local.env"

New-Item -ItemType Directory -Force -Path $configDir | Out-Null

if (-not (Test-Path $examplePath)) {
    throw "Template not found: $examplePath"
}

if (-not (Test-Path $localPath)) {
    Copy-Item -Path $examplePath -Destination $localPath
    Write-Host "Created local config: $localPath"
} else {
    Write-Host "Opening existing local config: $localPath"
}

Write-Host ""
Write-Host "真实 key 只会写入本机 config\dubhe.local.env；该文件已被 .gitignore 忽略。"
Write-Host ""

if ($Guided) {
    Invoke-GuidedConfig -Path $localPath -PlainInput:$PlainInput
} else {
    Write-Host "Edit values after '=' and remove the leading '# ' to enable an item."
    Write-Host "Save the file, then restart Dubhe Core with Start-Dubhe.cmd."
}

if (-not $NoOpen) {
    Write-Host ""
    Write-Host "Opening config file in Notepad for review..."
    Start-Process notepad.exe -ArgumentList @($localPath) | Out-Null
}

