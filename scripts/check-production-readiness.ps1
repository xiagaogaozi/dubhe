param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-CoreJson {
    param([string]$Url)

    $response = Invoke-WebRequest -Uri $Url -TimeoutSec 30 -UseBasicParsing
    if ($response.RawContentStream) {
        $response.RawContentStream.Position = 0
        $memory = [System.IO.MemoryStream]::new()
        $response.RawContentStream.CopyTo($memory)
        $body = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
        return $body | ConvertFrom-Json
    }
    return $response.Content | ConvertFrom-Json
}

function Write-ReadinessLine {
    param([pscustomobject]$Item)

    $label = switch ($Item.status) {
        "pass" { "[PASS]" }
        "warn" { "[WARN]" }
        "fail" { "[FAIL]" }
        default { "[UNKNOWN]" }
    }
    $blocking = if ($Item.blocking) { "blocking" } else { "non-blocking" }
    Write-Host "$label $($Item.category_zh) / $($Item.id) / $blocking"
    Write-Host "    Requirement: $($Item.requirement_zh)"
    Write-Host "    Evidence: $($Item.evidence_zh)"
    Write-Host "    Next: $($Item.next_step_zh)"
}

try {
    $report = Read-CoreJson -Url "$CoreUrl/v1/system/production-readiness"
} catch {
    Write-Host "Unable to read Dubhe Core production readiness."
    Write-Host "Core URL: $CoreUrl"
    Write-Host "Start Core first with Start-Dubhe.cmd, then run this again."
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host "Dubhe production readiness"
Write-Host "Core URL: $CoreUrl"
Write-Host ""
foreach ($item in $report.items) {
    Write-ReadinessLine $item
}
Write-Host ""
Write-Host "Summary: $($report.message_zh)"
Write-Host "Pass: $($report.pass_count), warn: $($report.warning_count), blocking: $($report.blocking_count), total: $($report.total_count)"
Write-Host "Production ready: $($report.production_ready)"

if (-not $report.production_ready) {
    exit 1
}

