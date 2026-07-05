param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [switch]$Live,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-CoreJson {
    param([string]$Url)

    $response = Invoke-WebRequest -Uri $Url -TimeoutSec 75 -UseBasicParsing
    if ($response.RawContentStream) {
        $response.RawContentStream.Position = 0
        $memory = [System.IO.MemoryStream]::new()
        $response.RawContentStream.CopyTo($memory)
        $body = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
        return $body | ConvertFrom-Json
    }
    return $response.Content | ConvertFrom-Json
}

function Write-CheckLine {
    param([pscustomobject]$Check)

    $label = switch ($Check.status) {
        "ok" { "[OK]" }
        "skipped" { "[SKIP]" }
        "unavailable" { "[FAIL]" }
        default { "[UNKNOWN]" }
    }
    $liveLabel = if ($Check.live_checked) { "live $($Check.duration_ms)ms" } else { "config" }
    Write-Host "$label $($Check.label_zh) / ${liveLabel}: $($Check.message_zh)"
    if ($Check.next_step_zh) {
        Write-Host "    Next: $($Check.next_step_zh)"
    }
}

$liveText = if ($Live) { "true" } else { "false" }
$url = "$CoreUrl/v1/system/external-checks?live=$liveText"

try {
    $report = Read-CoreJson -Url $url
} catch {
    Write-Host "Unable to read Dubhe Core external service checks."
    Write-Host "Core URL: $CoreUrl"
    Write-Host "Start Core first with Start-Dubhe.cmd or Start-Dubhe-LAN.cmd, then run this again."
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host "Dubhe external service checks"
Write-Host "Core URL: $CoreUrl"
Write-Host "Live check: $liveText"
if ($Live) {
    Write-Host "Note: live mode sends minimal requests to configured AI/news providers."
}
Write-Host ""
foreach ($check in $report.checks) {
    Write-CheckLine $check
}
Write-Host ""
Write-Host "Summary: $($report.message_zh)"
Write-Host "Ready: $($report.ready_count)/$($report.total_count), overall: $($report.overall_status)"

if ($report.overall_status -eq "action_required") {
    exit 1
}
