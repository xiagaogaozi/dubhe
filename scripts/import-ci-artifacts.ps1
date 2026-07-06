param(
    [string]$SourceRoot = "",
    [switch]$DownloadLatest,
    [string[]]$WorkflowNames = @("theia-desktop.yml", "mobile.yml"),
    [switch]$PrepareDelivery,
    [switch]$VerifyDelivery,
    [switch]$RequireAllPlatforms,
    [switch]$OpenReport,
    [switch]$OpenFolder
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Format-ByteSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Remove-SafeDirectory {
    param(
        [string]$Path,
        [string]$AllowedRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $allowedFull = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd("\")
    $targetFull = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd("\")
    $insideAllowedRoot = $targetFull.Equals($allowedFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $targetFull.StartsWith("$allowedFull\", [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $insideAllowedRoot) {
        throw "Refusing to remove directory outside allowed root: $targetFull"
    }
    Remove-Item -LiteralPath $targetFull -Recurse -Force
}

function Resolve-NewestFileFromRoots {
    param(
        [string[]]$Roots,
        [string]$Pattern
    )

    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $Pattern -ErrorAction SilentlyContinue)) {
            $files.Add($file) | Out-Null
        }
    }
    return @($files | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
}

function Resolve-NewestDirectoryFromRoots {
    param(
        [string[]]$Roots,
        [string]$Name
    )

    $directories = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($directory in @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Filter $Name -ErrorAction SilentlyContinue)) {
            $directories.Add($directory) | Out-Null
        }
    }
    return @($directories | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
}

function Import-FileArtifact {
    param(
        [string]$Label,
        [System.IO.FileInfo]$Source,
        [string]$DestinationDirectory
    )

    if ($null -eq $Source) {
        return [pscustomobject]@{
            label = $Label
            imported = $false
            source = $null
            destination = $null
            size_bytes = 0
            sha256 = $null
            message_zh = "未找到。"
        }
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $destination = Join-Path $DestinationDirectory $Source.Name
    Copy-Item -LiteralPath $Source.FullName -Destination $destination -Force
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $destination
    return [pscustomobject]@{
        label = $Label
        imported = $true
        source = $Source.FullName
        destination = $destination
        size_bytes = (Get-Item -LiteralPath $destination).Length
        sha256 = $hash.Hash
        message_zh = "已导入。"
    }
}

function Import-DirectoryArtifact {
    param(
        [string]$Label,
        [System.IO.DirectoryInfo]$Source,
        [string]$DestinationDirectory
    )

    if ($null -eq $Source) {
        return [pscustomobject]@{
            label = $Label
            imported = $false
            source = $null
            destination = $null
            size_bytes = 0
            file_count = 0
            sha256 = $null
            message_zh = "未找到。"
        }
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $destination = Join-Path $DestinationDirectory $Source.Name
    if (Test-Path -LiteralPath $destination) {
        Remove-SafeDirectory -Path $destination -AllowedRoot $DestinationDirectory
    }
    Copy-Item -LiteralPath $Source.FullName -Destination $destination -Recurse -Force
    $files = @(Get-ChildItem -LiteralPath $destination -Recurse -File)
    $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sizeBytes) { $sizeBytes = 0 }
    return [pscustomobject]@{
        label = $Label
        imported = $true
        source = $Source.FullName
        destination = $destination
        size_bytes = [int64]$sizeBytes
        file_count = $files.Count
        sha256 = $null
        message_zh = "已导入目录。"
    }
}

function Expand-ArtifactArchives {
    param(
        [string]$SourceRoot,
        [string]$StageRoot
    )

    New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
    $expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($zip in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Filter "*.zip" -ErrorAction SilentlyContinue)) {
        if ($zip.Name -like "Dubhe-*-mac-*.zip") {
            continue
        }
        $target = Join-Path $StageRoot ([System.IO.Path]::GetFileNameWithoutExtension($zip.Name))
        Remove-SafeDirectory -Path $target -AllowedRoot $StageRoot
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        try {
            Expand-Archive -LiteralPath $zip.FullName -DestinationPath $target -Force
            $expanded.Add($target) | Out-Null
        } catch {
            Write-Host "Skipping non-expandable archive: $($zip.FullName)"
            Remove-SafeDirectory -Path $target -AllowedRoot $StageRoot
        }
    }
    return @($expanded)
}

function Invoke-GhArtifactDownload {
    param(
        [string]$DestinationRoot,
        [string[]]$WorkflowNames
    )

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        throw "GitHub CLI gh was not found. Install gh or manually put artifact ZIPs into $DestinationRoot."
    }

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    foreach ($workflowName in $WorkflowNames) {
        Write-Host "Looking for latest successful workflow: $workflowName"
        $runsJson = & gh run list --workflow $workflowName --status success --limit 1 --json databaseId,name,headBranch,conclusion,status 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "gh run list failed for $workflowName`: $runsJson"
        }
        $runs = $runsJson | ConvertFrom-Json
        if ($runs.Count -eq 0) {
            throw "No successful GitHub Actions run found for workflow: $workflowName"
        }
        $runId = $runs[0].databaseId
        Write-Host "Downloading artifacts from run $runId ($workflowName)..."
        & gh run download $runId --dir $DestinationRoot
        if ($LASTEXITCODE -ne 0) {
            throw "gh run download failed for run $runId."
        }
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $runRoot "ci-artifacts"
}
$stageRoot = Join-Path $runRoot "ci-artifact-import-stage"
$reportTextPath = Join-Path $runRoot "ci-artifact-import.txt"
$reportJsonPath = Join-Path $runRoot "ci-artifact-import.json"

New-Item -ItemType Directory -Force -Path $runRoot, $SourceRoot | Out-Null
Remove-SafeDirectory -Path $stageRoot -AllowedRoot $runRoot
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

if ($DownloadLatest) {
    Invoke-GhArtifactDownload -DestinationRoot $SourceRoot -WorkflowNames $WorkflowNames
}

$expandedRoots = @(Expand-ArtifactArchives -SourceRoot $SourceRoot -StageRoot $stageRoot)
$searchRoots = @($SourceRoot, $stageRoot) + $expandedRoots

$desktopDist = Join-Path $repoRoot "apps\theia-desktop\app\dist"
$mobileRoot = Join-Path $repoRoot "apps\mobile"
$androidApkDir = Join-Path $mobileRoot "build\app\outputs\flutter-apk"
$androidAabDir = Join-Path $mobileRoot "build\app\outputs\bundle\release"
$iosAppDir = Join-Path $mobileRoot "build\ios\iphoneos"
$iosIpaDir = Join-Path $mobileRoot "build\ios\ipa"

$results = @(
    Import-FileArtifact -Label "Windows setup" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "Dubhe-*-win-x64-setup.exe") -DestinationDirectory $desktopDist
    Import-FileArtifact -Label "Windows portable" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "Dubhe-*-win-x64-portable.exe") -DestinationDirectory $desktopDist
    Import-FileArtifact -Label "macOS DMG" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "Dubhe-*-mac-*.dmg") -DestinationDirectory $desktopDist
    Import-FileArtifact -Label "macOS ZIP" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "Dubhe-*-mac-*.zip") -DestinationDirectory $desktopDist
    Import-FileArtifact -Label "Android debug APK" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "app-debug.apk") -DestinationDirectory $androidApkDir
    Import-FileArtifact -Label "Android release AAB" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "app-release.aab") -DestinationDirectory $androidAabDir
    Import-DirectoryArtifact -Label "iOS Runner.app" -Source (Resolve-NewestDirectoryFromRoots -Roots $searchRoots -Name "Runner.app") -DestinationDirectory $iosAppDir
    Import-FileArtifact -Label "iOS IPA" -Source (Resolve-NewestFileFromRoots -Roots $searchRoots -Pattern "*.ipa") -DestinationDirectory $iosIpaDir
)

$importedCount = @($results | Where-Object { $_.imported }).Count
$missingCount = @($results | Where-Object { -not $_.imported }).Count
$deliveryResult = $null
$verificationResult = $null

if ($PrepareDelivery -and $importedCount -gt 0) {
    $prepareScript = Join-Path $repoRoot "scripts\prepare-delivery.ps1"
    Write-Host "Preparing delivery ZIP after artifact import..."
    $prepareOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $prepareScript 2>&1
    $prepareExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    $deliveryResult = [pscustomobject]@{
        exit_code = $prepareExit
        output = @($prepareOutput | ForEach-Object { "$_" })
    }
    if ($prepareExit -ne 0) {
        throw "prepare-delivery.ps1 failed after import."
    }
}

if ($VerifyDelivery -and $importedCount -gt 0) {
    $verifyScript = Join-Path $repoRoot "scripts\verify-delivery-pack.ps1"
    $verifyArguments = @("-Json")
    if ($RequireAllPlatforms) {
        $verifyArguments += "-RequireAllPlatforms"
    }
    Write-Host "Verifying delivery ZIP after artifact import..."
    $verifyOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript @verifyArguments 2>&1
    $verifyExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    $verificationResult = [pscustomobject]@{
        exit_code = $verifyExit
        output = @($verifyOutput | ForEach-Object { "$_" })
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    source_root = $SourceRoot
    stage_root = $stageRoot
    download_latest = [bool]$DownloadLatest
    imported_count = $importedCount
    missing_count = $missingCount
    artifacts = $results
    delivery = $deliveryResult
    verification = $verificationResult
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportJsonPath -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Dubhe CI 产物导入报告") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("生成时间：$($report.generated_at)") | Out-Null
$lines.Add("产物来源目录：$SourceRoot") | Out-Null
$lines.Add("导入成功：$importedCount") | Out-Null
$lines.Add("未找到：$missingCount") | Out-Null
$lines.Add("") | Out-Null
foreach ($item in $results) {
    if ($item.imported) {
        $sizeText = Format-ByteSize -Bytes $item.size_bytes
        $lines.Add("[OK] $($item.label)：$($item.destination) ($sizeText)") | Out-Null
    } else {
        $lines.Add("[缺失] $($item.label)：$($item.message_zh)") | Out-Null
    }
}
$lines.Add("") | Out-Null
if ($deliveryResult) {
    $lines.Add("交付包生成退出码：$($deliveryResult.exit_code)") | Out-Null
}
if ($verificationResult) {
    $lines.Add("交付包验证退出码：$($verificationResult.exit_code)") | Out-Null
}
$lines.Add("JSON 报告：$reportJsonPath") | Out-Null
$lines | Out-File -FilePath $reportTextPath -Encoding UTF8

Write-Host "Dubhe CI artifact import"
Write-Host "Source: $SourceRoot"
Write-Host "Imported: $importedCount"
Write-Host "Missing: $missingCount"
Write-Host "Report: $reportTextPath"

if ($OpenReport) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($reportTextPath)
}
if ($OpenFolder) {
    Start-Process -FilePath "explorer.exe" -ArgumentList @($SourceRoot)
}

if ($importedCount -eq 0) {
    exit 1
}
if ($verificationResult -and $verificationResult.exit_code -ne 0) {
    exit $verificationResult.exit_code
}
exit 0
