$ErrorActionPreference = "Stop"

function Import-DubheLocalConfig {
    param(
        [string]$RepoRoot,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        throw "RepoRoot is required."
    }

    $configPath = Join-Path $RepoRoot "config\dubhe.local.env"
    if (-not (Test-Path $configPath)) {
        if (-not $Quiet) {
            Write-Host "Local config not found: $configPath"
        }
        return @()
    }

    $loaded = [System.Collections.Generic.List[string]]::new()
    $lineNumber = 0
    foreach ($line in Get-Content -Encoding UTF8 $configPath) {
        $lineNumber += 1
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#") -or $trimmed.StartsWith(";")) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf("=")
        if ($separatorIndex -le 0) {
            throw "Invalid config line $lineNumber in $configPath. Expected KEY=VALUE."
        }

        $key = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if ($key -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
            throw "Invalid config key '$key' on line $lineNumber in $configPath."
        }

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) -or
            ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2)
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [Environment]::SetEnvironmentVariable($key, $value, "Process")
        $loaded.Add($key) | Out-Null
    }

    if (-not $Quiet) {
        if ($loaded.Count -gt 0) {
            Write-Host "Loaded local config: $configPath"
        } else {
            Write-Host "Local config has no active entries: $configPath"
        }
    }
    return @($loaded)
}

