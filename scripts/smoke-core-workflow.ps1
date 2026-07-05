param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$Market = "US",
    [string]$Symbol = "NVDA",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
$reportPath = Join-Path $runRoot "smoke-core-workflow.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$steps = [System.Collections.Generic.List[object]]::new()
$artifacts = [ordered]@{}
$status = "failed"
$failureMessage = $null

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

function Write-SmokeHost {
    param([string]$Message)
    if (-not $Json) {
        Write-Host $Message
    }
}

function Add-SmokeStep {
    param(
        [string]$Name,
        [ValidateSet("passed", "failed")]
        [string]$Status,
        [int]$DurationMs,
        [string]$Message,
        [object]$Data = $null
    )

    $script:steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        duration_ms = $DurationMs
        message = $Message
        data = $Data
    }) | Out-Null
}

function Assert-Smoke {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-DubheApi {
    param(
        [ValidateSet("Get", "Post", "Put")]
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$AccessToken = ""
    )

    $uri = if ($Path.StartsWith("http")) { $Path } else { "$CoreUrl$Path" }
    $headers = @{ Accept = "application/json" }
    if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
        $headers.Authorization = "Bearer $AccessToken"
    }

    try {
        if ($null -ne $Body) {
            $jsonBody = $Body | ConvertTo-Json -Depth 40
            return Invoke-RestMethod `
                -Method $Method `
                -Uri $uri `
                -Headers $headers `
                -ContentType "application/json; charset=utf-8" `
                -Body $utf8NoBom.GetBytes($jsonBody) `
                -TimeoutSec 20
        }

        return Invoke-RestMethod `
            -Method $Method `
            -Uri $uri `
            -Headers $headers `
            -TimeoutSec 20
    } catch {
        throw "$Method $Path 失败：$($_.Exception.Message)"
    }
}

function Invoke-SmokeStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $startedAt = Get-Date
    try {
        $result = & $Action
        $durationMs = [int]([DateTime]::UtcNow - $startedAt.ToUniversalTime()).TotalMilliseconds
        Add-SmokeStep -Name $Name -Status "passed" -DurationMs $durationMs -Message "通过"
        Write-SmokeHost "[OK] $Name"
        return $result
    } catch {
        $durationMs = [int]([DateTime]::UtcNow - $startedAt.ToUniversalTime()).TotalMilliseconds
        Add-SmokeStep -Name $Name -Status "failed" -DurationMs $durationMs -Message $_.Exception.Message
        Write-SmokeHost "[失败] $Name：$($_.Exception.Message)"
        throw
    }
}

$normalizedSymbol = $Symbol.Trim().ToUpperInvariant()
$encodedMarket = [System.Uri]::EscapeDataString($Market)
$encodedSymbol = [System.Uri]::EscapeDataString($normalizedSymbol)
$suffix = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
$accountKey = "smoke-$suffix"
$paperAccountId = "smoke-paper-$suffix"

try {
    Write-SmokeHost "Dubhe Core workflow smoke"
    Write-SmokeHost "Core 地址：$CoreUrl"
    Write-SmokeHost "标的：$Market / $normalizedSymbol"

    $health = Invoke-SmokeStep "Core 健康检查" {
        $response = Invoke-DubheApi -Method Get -Path "/health"
        Assert-Smoke ($response.status -eq "ok") "Core /health 未返回 ok。"
        Assert-Smoke ($response.service -eq "dubhe-core") "Core service 不是 dubhe-core。"
        return $response
    }
    $artifacts.health_service = $health.service

    $session = Invoke-SmokeStep "注册本地账号并取得设备令牌" {
        $response = Invoke-DubheApi -Method Post -Path "/v1/auth/accounts/register" -Body @{
            account_key = $accountKey
            account_name = "Dubhe 烟测账户 $suffix"
            password = "Dubhe@2026"
            mfa_code = "000000"
            device_name = "Dubhe smoke workflow"
            platform = "windows"
        }
        Assert-Smoke (-not [string]::IsNullOrWhiteSpace($response.access_token)) "注册成功但未返回 access_token。"
        Assert-Smoke (-not [string]::IsNullOrWhiteSpace($response.workspace_id)) "注册成功但未返回 workspace_id。"
        return $response
    }
    $artifacts.account_key = $accountKey
    $artifacts.workspace_id = $session.workspace_id
    $accessToken = $session.access_token

    $checklist = Invoke-SmokeStep "读取首次使用清单" {
        $response = Invoke-DubheApi -Method Get -Path "/v1/onboarding/checklist" -AccessToken $accessToken
        $accountStep = @($response.steps | Where-Object { $_.id -eq "account_login" } | Select-Object -First 1)
        Assert-Smoke ($response.total_count -ge 8) "首次使用清单步骤数量不足。"
        Assert-Smoke ($accountStep.status -eq "complete") "登录后的账号步骤未标记为已完成。"
        return $response
    }
    $artifacts.onboarding_complete = "$($checklist.complete_count)/$($checklist.total_count)"

    $feed = Invoke-SmokeStep "刷新新闻雷达 fixture" {
        $response = Invoke-DubheApi -Method Get -Path "/v1/news/feed?market=$encodedMarket&symbol=$encodedSymbol&limit=3&live=false"
        $events = @($response.events)
        Assert-Smoke ($events.Count -gt 0) "新闻雷达未返回事件。"
        return $response
    }
    $newsEvent = @($feed.events)[0]
    $artifacts.news_event_id = $newsEvent.id

    $analysis = Invoke-SmokeStep "生成中文新闻影响分析" {
        $response = Invoke-DubheApi -Method Post -Path "/v1/news/analyze" -Body $newsEvent
        Assert-Smoke (-not [string]::IsNullOrWhiteSpace($response.summary_zh)) "新闻分析缺少中文摘要。"
        Assert-Smoke (@($response.citations).Count -gt 0) "新闻分析缺少来源引用。"
        return $response
    }
    $artifacts.analysis_id = $analysis.id

    $assistant = Invoke-SmokeStep "AI 分析师中文问答" {
        $response = Invoke-DubheApi -Method Post -Path "/v1/assistant/chat" -AccessToken $accessToken -Body @{
            question_zh = "请用一句话说明这条新闻对 $normalizedSymbol 的影响，并给出下一步验证动作。"
            context = @{
                news_event = $newsEvent
                analysis = $analysis
                strategy = $null
                backtest = $null
            }
        }
        Assert-Smoke (-not [string]::IsNullOrWhiteSpace($response.answer_zh)) "AI 分析师未返回中文答复。"
        return $response
    }
    $artifacts.assistant_turn_id = $assistant.id

    $draft = Invoke-SmokeStep "从分析生成策略草案" {
        $response = Invoke-DubheApi -Method Post -Path "/v1/strategy/drafts/from-analysis" -Body @{
            analysis = $analysis
            symbol = $normalizedSymbol
            market = $Market
            max_order_notional = 10000
        }
        Assert-Smoke (-not [string]::IsNullOrWhiteSpace($response.strategy_version_id)) "策略草案缺少 strategy_version_id。"
        Assert-Smoke (@($response.spec.broker_permissions) -contains "paper") "策略草案未限制为 paper 权限。"
        return $response
    }
    $artifacts.strategy_draft_id = $draft.id
    $artifacts.strategy_version_id = $draft.strategy_version_id

    $backtest = Invoke-SmokeStep "运行 deterministic replay 回测" {
        $response = Invoke-DubheApi -Method Post -Path "/v1/backtests/replay" -Body @{
            strategy = $draft
            initial_cash = 100000
            replay_scenario = "golden_news_sentiment_v1"
        }
        Assert-Smoke ($response.final_equity -gt 100000) "回测最终权益未高于初始资金。"
        Assert-Smoke (@($response.equity_curve).Count -ge 5) "回测权益曲线点数不足。"
        return $response
    }
    $artifacts.backtest_id = $backtest.id

    $paperOrder = Invoke-SmokeStep "提交 1 股纸面买入" {
        $response = Invoke-DubheApi -Method Post -Path "/v1/simulation/paper-orders" -AccessToken $accessToken -Body @{
            account_id = $paperAccountId
            strategy_version_id = $draft.strategy_version_id
            market = $Market
            symbol = $normalizedSymbol
            side = "buy"
            order_type = "market"
            quantity = 1
            estimated_price = 120
            currency = "USD"
            created_by = "user"
            destination = "paper"
            rationale_zh = "Dubhe Core 自动烟测：只进入纸面账户，不连接真实券商。"
            source_refs = @($analysis.id)
        }
        Assert-Smoke ($response.status -eq "accepted") "纸面订单未被接受：$($response.status)。"
        return $response
    }
    $artifacts.paper_order_id = $paperOrder.id

    $portfolio = Invoke-SmokeStep "验证纸面组合入账" {
        $response = Invoke-DubheApi -Method Get -Path "/v1/simulation/paper-portfolio/$paperAccountId" -AccessToken $accessToken
        $position = @($response.positions | Where-Object { $_.symbol -eq $normalizedSymbol } | Select-Object -First 1)
        Assert-Smoke ($position.quantity -ge 1) "纸面组合未出现 $normalizedSymbol 持仓。"
        return $response
    }
    $artifacts.paper_account_id = $portfolio.account_id

    $snapshot = Invoke-SmokeStep "验证工作区同步快照" {
        $workspaceId = [System.Uri]::EscapeDataString($session.workspace_id)
        $response = Invoke-DubheApi -Method Get -Path "/v1/workspaces/$workspaceId/snapshot" -AccessToken $accessToken
        Assert-Smoke (@($response.events).Count -gt 0) "工作区快照没有同步事件。"
        return $response
    }
    $artifacts.workspace_sequence = $snapshot.server_sequence

    $status = "passed"
} catch {
    $failureMessage = $_.Exception.Message
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    status = $status
    core_url = $CoreUrl
    market = $Market
    symbol = $normalizedSymbol
    failure = $failureMessage
    report_path = $reportPath
    artifacts = [pscustomobject]$artifacts
    steps = $steps
}

$reportJson = $report | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($reportPath, $reportJson, $utf8NoBom)

if ($Json) {
    $reportJson
} else {
    Write-SmokeHost ""
    Write-SmokeHost "烟测结果：$status"
    if ($failureMessage) {
        Write-SmokeHost "失败原因：$failureMessage"
    }
    Write-SmokeHost "报告：$reportPath"
}

if ($status -eq "passed") {
    exit 0
}
exit 1
