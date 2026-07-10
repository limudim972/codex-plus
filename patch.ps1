<#
.SYNOPSIS
    Codex Plus
.DESCRIPTION
    Installs and restores the local Codex Desktop RTL runtime.
#>
param(
    [string]$TrustedPubKey,
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

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$RequiresElevation = (-not ($LaunchCodexRtl -or $ShowLaunchSplash -or $StartCloseWatchdog -or $SkipMain))
if ((-not $SkipMain) -and $RequiresElevation -and (-not $IsAdmin)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($TrustedPubKey) { $args += @('-TrustedPubKey', $TrustedPubKey) }
        Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs `
            -ArgumentList $args
        Exit
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $InstallUrl = "https://raw.githubusercontent.com/limudim972/codex-plus/main/install.ps1"
    Invoke-Expression (Invoke-RestMethod $InstallUrl)
    Exit
}

foreach ($module in @(
    'src/shared/logging.ps1',
    'src/shared/prompting.ps1',
    'src/shared/asar.ps1',
    'src/codex/detection.ps1',
    'src/codex/rtl-payload.ps1',
    'src/codex/rtl-payload-Plan.ps1',
    'src/codex/context-badge.ps1',
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
    Exit
}

$script:CodexRtlPatchScriptPath = $PSCommandPath

if ($ShowLaunchSplash) {
    Show-CodexLaunchSplash -LauncherKey $LauncherKey
    Exit
}

if ($SkipMain) {
    return
}

if ($InstallCodexPlus) {
    Install-CodexRtlPatch
    Exit
}

if ($LaunchCodexRtl) {
    Launch-CodexRtl
    Exit
}

Show-Menu
