function Get-CodexPlusLauncherScriptPath {
    Join-Path (Get-CodexRtlRuntimeRoot) 'launch-codex-plus.vbs'
}

function Install-CodexRtlRuntimeFiles {
    param([Parameter(Mandatory)][string]$SourceRoot)

    $runtimeRoot = Get-CodexRtlRuntimeRoot
    $items = @(
        'patch.ps1',
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

    return $runtimeRoot
}

function New-CodexRtlLauncherScriptContent {
    param([Parameter(Mandatory)][string]$PatchScriptPath)

    $escapedPatchScriptPath = $PatchScriptPath.Replace('"', '""')
@"
Set shell = CreateObject("WScript.Shell")
launcherKey = ""
If WScript.Arguments.Count > 0 Then
    launcherKey = WScript.Arguments(0)
End If
If launcherKey <> "" Then
    shell.Environment("Process")("CODEX_PLUS_LAUNCHER_KEY") = launcherKey
End If
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedPatchScriptPath" & Chr(34) & " -LaunchCodexRtl"
shell.Run command, 0, False
watchdogCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedPatchScriptPath" & Chr(34) & " -SkipMain -StartCloseWatchdog"
If launcherKey <> "" Then
    watchdogCommand = watchdogCommand & " -LauncherKey " & Chr(34) & launcherKey & Chr(34)
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
