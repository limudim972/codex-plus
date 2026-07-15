<#
.SYNOPSIS
    Codex Plus
.DESCRIPTION
    Installs and restores the local Codex Desktop RTL runtime.
#>
param(
    [switch]$LaunchCodexRtl,
    [switch]$ShowLaunchSplash,
    [switch]$StartCloseWatchdog,
    [int]$WatchPort,
    [AllowEmptyString()][string]$LauncherKey,
    [switch]$InstallCodexPlus,
    [switch]$SkipMain
)

if ($env:OS -ne 'Windows_NT') {
    Write-Host "Codex Plus is Windows-only. Please run it on Windows 10/11." -ForegroundColor Red
    exit 1
}

foreach ($module in @(
    'src/shared/logging.ps1',
    'src/shared/prompting.ps1',
    'src/shared/asar.ps1',
    'src/runtime/assets/codex-plus.ico',
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
)) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required module not found: $modulePath"
    }
    . $modulePath
}

if ($StartCloseWatchdog) {
    if (-not $WatchPort) {
        $state = Read-CodexRtlState
        $preferredPort = if ($state -and $state.Port) { [int]$state.Port } else { 0 }
        $WatchPort = Wait-CodexInstanceDebugPort -PreferredPort $preferredPort -LauncherKey $LauncherKey
    }
    if (-not $WatchPort) {
        throw 'WatchPort could not be resolved for the Codex close watchdog.'
    }
    Watch-CodexCloseToQuit -Port $WatchPort -LauncherKey $LauncherKey
    return
}

$script:CodexRtlPatchScriptPath = $PSCommandPath

if ($ShowLaunchSplash) {
    Show-CodexLaunchSplash -LauncherKey $LauncherKey
    return
}

if ($SkipMain) {
    return
}

if ($InstallCodexPlus) {
    Install-CodexRtlPatch
    return
}

if ($LaunchCodexRtl) {
    Launch-CodexRtl
    return
}

Show-Menu
