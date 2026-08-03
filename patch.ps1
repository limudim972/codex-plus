<#
.SYNOPSIS
    Codex Plus
.DESCRIPTION
    Installs and restores the local Codex Desktop RTL runtime.
#>
param(
    [switch]$LaunchCodexRtl,
    [switch]$ShowLaunchSplash,
    [switch]$StartGlobalManager,
    [int]$PreferredPort,
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
    'src/codex/rtl-shared.ps1',
    'src/codex/detection.ps1',
    'src/codex/new-chat-button.ps1',
    'src/codex/new-window-button.ps1',
    'src/codex/rtl-payload.ps1',
    'src/codex/rtl-payload-Plan.ps1',
    'src/codex/payload-bundle.ps1',
    'src/codex/activity-onboarding-hider.ps1',
    'src/codex/context-badge.ps1',
    'src/codex/full-access-reminder-hider.ps1',
    'src/codex/split-model-effort-selector.ps1',
    'src/codex/project-selector-guard.ps1',
    'src/codex/sidebar-paging.ps1',
    'src/codex/auto-continue.ps1',
    'src/runtime/state.ps1',
    'src/runtime/gpu.ps1',
    'src/runtime/files.ps1',
    'src/runtime/shortcuts.ps1',
    'src/runtime/launch.ps1',
    'src/runtime/global-manager.ps1',
    'src/runtime/patching.ps1',
    'src/ui/menu.ps1'
)) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required module not found: $modulePath"
    }
    . $modulePath
}

$script:CodexRtlPatchScriptPath = $PSCommandPath

if ($StartGlobalManager) {
    Start-CodexPlusGlobalManager
    return
}

if ($ShowLaunchSplash) {
    Show-CodexLaunchSplash -LauncherKey $LauncherKey -PreferredPort $PreferredPort
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
    Launch-CodexRtl -PreferredPort $PreferredPort -LauncherKey $LauncherKey
    return
}

Show-Menu
