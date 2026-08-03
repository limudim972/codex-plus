function Get-CodexPlusLauncherScriptPath {
    Join-Path (Get-CodexRtlRuntimeRoot) 'launch-codex-plus.vbs'
}

function Get-CodexUsageDashboardServerScriptPath {
    Join-Path (Get-CodexRtlRuntimeRoot) 'dashboard-server.ps1'
}

function Install-CodexRtlRuntimeFiles {
    param([Parameter(Mandatory)][string]$SourceRoot)

    $runtimeRoot = Get-CodexRtlRuntimeRoot
    $items = @(
        'patch.ps1',
        'src/runtime/assets/codex-plus.ico',
        'src/runtime/dashboard-server.ps1',
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
        'src/runtime/patching.ps1',
        'src/ui/menu.ps1'
    )

    foreach ($item in $items) {
        $source = Join-Path $SourceRoot $item
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Runtime source file not found: $source"
        }
        $destination = Join-Path $runtimeRoot $item
        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
        }
        $sourceFullPath = [System.IO.Path]::GetFullPath($source)
        $destinationFullPath = [System.IO.Path]::GetFullPath($destination)
        if ($sourceFullPath -ine $destinationFullPath) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }

    foreach ($obsoleteItem in @('src/runtime/project-order.ps1', 'src/codex/new-session-button.ps1')) {
        $obsoletePath = Join-Path $runtimeRoot $obsoleteItem
        if (Test-Path -LiteralPath $obsoletePath) {
            Remove-Item -LiteralPath $obsoletePath -Force
        }
    }

    return $runtimeRoot
}

function New-CodexRtlLauncherScriptContent {
    param([Parameter(Mandatory)][string]$PatchScriptPath)

    $escapedPatchScriptPath = $PatchScriptPath.Replace('"', '""')
@"
Set shell = CreateObject("WScript.Shell")
launcherKey = ""
desktopLaunch = False
If WScript.Arguments.Count > 0 Then
    launcherKey = WScript.Arguments(0)
End If
If WScript.Arguments.Count > 1 Then
    desktopLaunch = (LCase(WScript.Arguments(1)) = "desktop")
End If
preferredPort = 0
portFromEnvironment = shell.Environment("Process")("CODEX_PLUS_REQUESTED_PORT")
If portFromEnvironment <> "" Then
    On Error Resume Next
    preferredPort = CInt(portFromEnvironment)
    On Error GoTo 0
End If
If WScript.Arguments.Count > 2 Then
    On Error Resume Next
    preferredPort = CInt(WScript.Arguments(2))
    On Error GoTo 0
End If
If launcherKey <> "" Then
    instanceKey = launcherKey & "-" & Replace(Replace(CreateObject("Scriptlet.TypeLib").Guid, "{", ""), "}", "")
    shell.Environment("Process")("CODEX_PLUS_LAUNCHER_KEY") = instanceKey
Else
    instanceKey = ""
End If
If desktopLaunch Then
    shell.Environment("Process")("CODEX_PLUS_DESKTOP_LAUNCH") = "1"
End If
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedPatchScriptPath" & Chr(34) & " -LaunchCodexRtl"
launchSplashCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedPatchScriptPath" & Chr(34) & " -ShowLaunchSplash"
If preferredPort > 0 Then
    command = command & " -PreferredPort " & CStr(preferredPort)
    launchSplashCommand = launchSplashCommand & " -PreferredPort " & CStr(preferredPort)
End If
If instanceKey <> "" Then
    launchSplashCommand = launchSplashCommand & " -LauncherKey " & Chr(34) & instanceKey & Chr(34)
End If
dashboardServerPath = Replace("$escapedPatchScriptPath", "patch.ps1", "src\runtime\dashboard-server.ps1")
dashboardRoot = shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\code\Codex Usage Dashboard"
dashboardCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & dashboardServerPath & Chr(34) & " -DashboardRoot " & Chr(34) & dashboardRoot & Chr(34) & " -Port 3000"
If instanceKey <> "" Then
    dashboardCommand = dashboardCommand & " -LauncherKey " & Chr(34) & instanceKey & Chr(34)
End If
shell.Run launchSplashCommand, 0, False
shell.Run command, 0, False
shell.Run dashboardCommand, 0, False
watchdogCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedPatchScriptPath" & Chr(34) & " -SkipMain -StartCloseWatchdog"
If instanceKey <> "" Then
    watchdogCommand = watchdogCommand & " -LauncherKey " & Chr(34) & instanceKey & Chr(34)
End If
shell.Run watchdogCommand, 0, False
"@
}

function Install-CodexRtlLauncherScript {
    param([Parameter(Mandatory)][string]$PatchScriptPath)

    $launcherPath = Get-CodexPlusLauncherScriptPath
    $launcherDir = Split-Path -Parent $launcherPath
    if (-not (Test-Path -LiteralPath $launcherDir)) {
        New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
    }
    New-CodexRtlLauncherScriptContent -PatchScriptPath $PatchScriptPath |
        Set-Content -LiteralPath $launcherPath -Encoding ASCII
    return $launcherPath
}

function Get-CodexRtlPatchScriptPath {
    if ($script:CodexRtlPatchScriptPath) { return $script:CodexRtlPatchScriptPath }
    if ($PSCommandPath) { return $PSCommandPath }
    return (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'patch.ps1')
}
