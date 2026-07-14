# Codex Plus installer.
#
param(
    [switch]$LocalDev
)

function Pause-ForInstallerExit {
    param([string]$Message = 'Press Enter to close this window.')

    if ($Host.Name -ne 'ConsoleHost') {
        return
    }

    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    try {
        [void](Read-Host)
    } catch {
    }
}

if ($env:OS -ne 'Windows_NT') {
    Write-Host "Codex Plus is Windows-only. Please run it on Windows 10/11." -ForegroundColor Red
    exit 1
}

$RepoBase = 'https://raw.githubusercontent.com/limudim972/codex-plus/main'
$TmpRoot  = Join-Path $env:TEMP 'codex_rtl_fix_patch'
$TmpFile  = Join-Path $TmpRoot 'patch.ps1'
$LocalRepoRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Get-Location }
$SourceRoot = if ($LocalDev) { $LocalRepoRoot } else { $null }
$ModuleFiles = @(
    'src/shared/logging.ps1',
    'src/shared/prompting.ps1',
    'src/shared/asar.ps1',
    'src/codex/detection.ps1',
    'src/codex/rtl-payload.ps1',
    'src/codex/rtl-payload-Plan.ps1',
    'src/codex/context-badge.ps1',
    'src/codex/split-model-effort-selector.ps1',
    'src/codex/sidebar-paging.ps1',
    'src/runtime/state.ps1',
    'src/runtime/files.ps1',
    'src/runtime/shortcuts.ps1',
    'src/runtime/launch.ps1',
    'src/runtime/patching.ps1',
    'src/ui/menu.ps1'
)

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$client = New-Object System.Net.WebClient
if ($LocalDev) {
    $patchPath = Join-Path $SourceRoot 'patch.ps1'
    if (-not (Test-Path -LiteralPath $patchPath)) {
        Write-Host "Local patch not found: $patchPath" -ForegroundColor Red
        return
    }
} else {
    try {
        $patchBytes = $client.DownloadData("$RepoBase/patch.ps1")
    } catch {
        Write-Host ""
        Write-Host "Network error downloading patch: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Check connectivity and retry." -ForegroundColor Yellow
        return
    }
}

if ($LocalDev) {
    Write-Host "Launching local Codex Plus installer..." -ForegroundColor Green
    & (Join-Path $SourceRoot 'patch.ps1') -InstallCodexPlus
    Write-Host "Codex Plus installer finished." -ForegroundColor Green
    Write-Host "Launch Codex Plus to see the changes." -ForegroundColor Yellow
    Pause-ForInstallerExit
} else {
    $content = [System.Text.Encoding]::UTF8.GetString($patchBytes)
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }

    try {
        if (-not (Test-Path -LiteralPath $TmpRoot)) {
            New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
        }

        foreach ($module in $ModuleFiles) {
            $moduleBytes = $client.DownloadData("$RepoBase/$module")
            $modulePath = Join-Path $TmpRoot $module
            $moduleDir = Split-Path -Parent $modulePath
            if (-not (Test-Path -LiteralPath $moduleDir)) {
                New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null
            }
            [System.IO.File]::WriteAllBytes($modulePath, $moduleBytes)
        }
    } catch {
        Write-Host ""
        Write-Host "Network error downloading required modules: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Check connectivity and retry." -ForegroundColor Yellow
        return
    }

    [System.IO.File]::WriteAllText($TmpFile, $content, [System.Text.UTF8Encoding]::new($true))
    Write-Host "Codex Plus downloaded ($($patchBytes.Length) bytes) and modules staged. Running installer..." -ForegroundColor Green
    & $TmpFile -InstallCodexPlus
    Write-Host "Codex Plus installer finished." -ForegroundColor Green
    Write-Host "Launch Codex Plus to see the changes." -ForegroundColor Yellow
    Pause-ForInstallerExit
}
