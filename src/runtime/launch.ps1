function Get-CodexRtlDefaultPort {
    18317
}

function Test-TcpPortAvailable {
    param([Parameter(Mandatory)][int]$Port)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Get-CodexRtlAvailablePort {
    param([int]$StartPort = 0)

    $start = if ($StartPort -gt 0) { $StartPort } else { Get-CodexRtlDefaultPort }
    for ($port = $start; $port -lt ($start + 50); $port++) {
        if (Test-TcpPortAvailable -Port $port) { return $port }
    }
    return $start
}

function New-CodexRtlLaunchArguments {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey,
        [int]$WindowTitleOrdinal = 0
    )

    $args = @(
        "--remote-debugging-port=$Port",
        '--remote-debugging-address=127.0.0.1'
    )
    $userDataDir = Get-CodexPlusUserDataDirectory -LauncherKey $LauncherKey
    if ($userDataDir) {
        $args += "--user-data-dir=$userDataDir"
    }
    if ($WindowTitleOrdinal -gt 0) {
        $args += "--codex-plus-window-title-ordinal=$WindowTitleOrdinal"
    }
    return $args
}

function Join-CodexRtlProcessArguments {
    param([string[]]$Arguments)

    $quoted = @()
    foreach ($argument in @($Arguments)) {
        if ($argument -match '[\s"]') {
            $quoted += ('"{0}"' -f $argument.Replace('"', '\"'))
        } else {
            $quoted += $argument
        }
    }
    return ($quoted -join ' ')
}

function Test-CodexProcessHasRtlDebugPort {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][int]$Port
    )

    return [bool]($Process.CommandLine -match [regex]::Escape("--remote-debugging-port=$Port") -and
        $Process.CommandLine -match [regex]::Escape('--remote-debugging-address=127.0.0.1'))
}

function Get-CodexProcessRtlDebugPort {
    param([Parameter(Mandatory)]$Process)

    $match = [regex]::Match([string]$Process.CommandLine, '--remote-debugging-port=(\d+)')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }
    return 0
}

function Test-CodexProcessIsBrowserProcess {
    param([Parameter(Mandatory)]$Process)

    return -not ([string]$Process.CommandLine -match '(^|\s)--type=')
}

function Normalize-CodexRtlMatchPath {
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $normalized = $Path.Trim().Trim('"').Replace('\\', '\')
    try {
        return [System.IO.Path]::GetFullPath($normalized).TrimEnd('\').ToLowerInvariant()
    } catch {
        return $normalized.TrimEnd('\').ToLowerInvariant()
    }
}

function Get-CodexProcessUserDataDirectory {
    param([Parameter(Mandatory)]$Process)

    $commandLine = [string]$Process.CommandLine
    $match = [regex]::Match($commandLine, '(?:"--user-data-dir=([^"]+)"|--user-data-dir=(?:"([^"]+)"|([^\s]+)))')
    if (-not $match.Success) { return '' }
    $value = if ($match.Groups[1].Success) {
        $match.Groups[1].Value
    } elseif ($match.Groups[2].Success) {
        $match.Groups[2].Value
    } else {
        $match.Groups[3].Value
    }
    return (Normalize-CodexRtlMatchPath -Path $value)
}

function Get-CodexProcessWindowTitleOrdinal {
    param([Parameter(Mandatory)]$Process)

    $match = [regex]::Match([string]$Process.CommandLine, '--codex-plus-window-title-ordinal=(\d+)')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }
    return 0
}

function Test-CodexProcessIsCodexPlusManaged {
    param([Parameter(Mandatory)]$Process)

    $profileRoot = Normalize-CodexRtlMatchPath -Path (Join-Path (Get-CodexRtlStateRoot) 'profile')
    $processUserDataDir = Get-CodexProcessUserDataDirectory -Process $Process
    if (-not $profileRoot -or -not $processUserDataDir) {
        return $false
    }

    return ($processUserDataDir -eq $profileRoot -or $processUserDataDir.StartsWith("$profileRoot\", [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-CodexNextWindowTitleOrdinal {
    $managedBrowserProcesses = @(
        Get-CodexDesktopProcesses | Where-Object {
            (Test-CodexProcessIsBrowserProcess -Process $_) -and
            (Test-CodexProcessIsCodexPlusManaged -Process $_)
        }
    )
    if ($managedBrowserProcesses.Count -eq 0) {
        return 1
    }

    $maxOrdinal = 0
    foreach ($process in $managedBrowserProcesses) {
        $ordinal = Get-CodexProcessWindowTitleOrdinal -Process $process
        if ($ordinal -gt $maxOrdinal) {
            $maxOrdinal = $ordinal
        }
    }

    return [Math]::Max($managedBrowserProcesses.Count, $maxOrdinal) + 1
}

function Get-CodexDesiredWindowTitle {
    param([int]$Ordinal = 0)

    if ($Ordinal -gt 0) {
        return "$Ordinal.Codex"
    }

    return 'Codex'
}

function Set-CodexNativeWindowTitle {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][string]$Title
    )

    if ($WindowHandle -eq [IntPtr]::Zero -or [string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }

    if (-not ('CodexPlusNativeWindowTitle' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class CodexPlusNativeWindowTitle {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetWindowText(IntPtr hWnd, string lpString);
}
'@
    }

    return [CodexPlusNativeWindowTitle]::SetWindowText($WindowHandle, $Title)
}

function Update-CodexWindowTitles {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey
    )

    $matchingProcesses = @(
        Get-CodexDesktopProcesses | Where-Object {
            Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port -LauncherKey $LauncherKey
        }
    )
    if ($matchingProcesses.Count -eq 0) {
        return $false
    }

    $updated = $false
    foreach ($process in $matchingProcesses) {
        $processOrdinal = Get-CodexProcessWindowTitleOrdinal -Process $process
        try {
            $liveProcess = Get-Process -Id $process.ProcessId -ErrorAction Stop
            if ($liveProcess.MainWindowHandle -eq 0) {
                continue
            }

            $desiredTitle = Get-CodexDesiredWindowTitle -Ordinal $processOrdinal
            if ([string]$liveProcess.MainWindowTitle -eq $desiredTitle) {
                continue
            }
            if (Set-CodexNativeWindowTitle -WindowHandle $liveProcess.MainWindowHandle -Title $desiredTitle) {
                $updated = $true
            }
        } catch {
        }
    }

    return $updated
}

function Wait-CodexWindowTitleSync {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey,
        [int]$TimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $matchingProcesses = @(
            Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port -LauncherKey $LauncherKey
            }
        )
        if ($matchingProcesses.Count -gt 0) {
            $allVisibleTitlesMatch = $true
            $visibleProcessCount = 0
            foreach ($process in $matchingProcesses) {
                $processOrdinal = Get-CodexProcessWindowTitleOrdinal -Process $process
                try {
                    $liveProcess = Get-Process -Id $process.ProcessId -ErrorAction Stop
                    if ($liveProcess.MainWindowHandle -ne 0) {
                        $visibleProcessCount += 1
                        $desiredTitle = Get-CodexDesiredWindowTitle -Ordinal $processOrdinal
                        if ([string]$liveProcess.MainWindowTitle -ne $desiredTitle) {
                            $allVisibleTitlesMatch = $false
                        }
                    }
                } catch {
                }
            }

            if ($visibleProcessCount -gt 0) {
                Update-CodexWindowTitles -Port $Port -LauncherKey $LauncherKey | Out-Null
                if ($allVisibleTitlesMatch) {
                    return $true
                }
            }
        }

        Start-Sleep -Milliseconds 300
    }

    return $false
}

function Test-CodexProcessMatchesCodexPlusInstance {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey
    )

    if (-not (Test-CodexProcessIsBrowserProcess -Process $Process)) {
        return $false
    }

    $expectedUserDataDir = Normalize-CodexRtlMatchPath -Path (Get-CodexPlusUserDataDirectory -LauncherKey $LauncherKey)
    if ($expectedUserDataDir) {
        return (Get-CodexProcessUserDataDirectory -Process $Process) -eq $expectedUserDataDir
    }

    return Test-CodexProcessHasRtlDebugPort -Process $Process -Port $Port
}

function Get-CodexDesktopProcesses {
    $installInfo = Get-CodexInstallInfo
    $preferredExeName = if ($installInfo.AppExe) { [System.IO.Path]::GetFileName($installInfo.AppExe) } else { $null }
    $allowedNames = @('ChatGPT.exe', 'Codex.exe')
    if ($preferredExeName -and ($allowedNames -notcontains $preferredExeName)) {
        $allowedNames = @($preferredExeName) + $allowedNames
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*\app\*.exe' -and
            $_.ExecutablePath -notlike '*\WindowsApps\OpenAI.Codex_*\app\resources\*' -and
            ($allowedNames -contains [System.IO.Path]::GetFileName($_.ExecutablePath))
        }
}

function Get-CodexRtlLaunchPort {
    param(
        [int]$PreferredPort = 0,
        [AllowEmptyString()][string]$LauncherKey
    )

    $port = if ($PreferredPort -gt 0) { $PreferredPort } else { Get-CodexRtlDefaultPort }
    $matchingProcesses = @(
        Get-CodexDesktopProcesses | Where-Object {
            Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $port -LauncherKey $LauncherKey
        }
    )
    if ($matchingProcesses.Count -gt 0) {
        $matchingPort = Get-CodexProcessRtlDebugPort -Process ($matchingProcesses | Select-Object -First 1)
        if ($matchingPort -gt 0) {
            return $matchingPort
        }
        return $port
    }
    if (Test-TcpPortAvailable -Port $port) { return $port }
    return (Get-CodexRtlAvailablePort -StartPort ($port + 1))
}

function Stop-CodexDesktopProcesses {
    param(
        [int]$Port = 0,
        [AllowEmptyString()][string]$LauncherKey,
        [switch]$CurrentInstanceOnly
    )

    foreach ($process in @(Get-CodexDesktopProcesses)) {
        if (-not (Test-CodexProcessIsBrowserProcess -Process $process)) {
            continue
        }
        if ($CurrentInstanceOnly) {
            if (-not (Test-CodexProcessMatchesCodexPlusInstance -Process $process -Port $Port -LauncherKey $LauncherKey)) {
                continue
            }
        } elseif ($Port -gt 0 -and (-not (Test-CodexProcessHasRtlDebugPort -Process $process -Port $Port))) {
            continue
        }
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "Could not stop Codex process $($process.ProcessId): $($_.Exception.Message)"
        }
    }
}

function Start-CodexWithRtlDebug {
    param(
        [Parameter(Mandatory)][string]$AppExe,
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey,
        [int]$WindowTitleOrdinal = 0
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $AppExe
    $startInfo.Arguments = Join-CodexRtlProcessArguments -Arguments (New-CodexRtlLaunchArguments -Port $Port -LauncherKey $LauncherKey -WindowTitleOrdinal $WindowTitleOrdinal)
    $startInfo.WorkingDirectory = Get-CodexRtlWorkingDirectory
    $startInfo.UseShellExecute = $false

    $userDataDir = Get-CodexPlusUserDataDirectory -LauncherKey $LauncherKey
    if ($userDataDir) {
        $startInfo.EnvironmentVariables['CODEX_ELECTRON_USER_DATA_PATH'] = $userDataDir
    }

    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
}

function Start-CodexNormally {
    param([Parameter(Mandatory)][string]$AppExe)

    Start-Process `
        -FilePath $AppExe `
        -WorkingDirectory (Split-Path -Parent $AppExe) | Out-Null
}

function Start-CodexForRtl {
    param(
        [Parameter(Mandatory)]$Inspection,
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey,
        [switch]$AllowRestart
    )

    $processes = @(Get-CodexDesktopProcesses)
    $browserProcesses = @($processes | Where-Object { Test-CodexProcessIsBrowserProcess -Process $_ })
    $scopedLaunch = -not [string]::IsNullOrWhiteSpace($LauncherKey)

    if ($scopedLaunch) {
        $matchingProcesses = @($browserProcesses | Where-Object { Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port -LauncherKey $LauncherKey })

        if ($matchingProcesses.Count -gt 0) {
            if ($AllowRestart) {
                $windowTitleOrdinal = Get-CodexNextWindowTitleOrdinal
                Write-Host 'Restarting Codex with local RTL injection support...' -ForegroundColor Yellow
                Stop-CodexDesktopProcesses -Port $Port -LauncherKey $LauncherKey -CurrentInstanceOnly
                Start-Sleep -Milliseconds 700
                Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port -LauncherKey $LauncherKey -WindowTitleOrdinal $windowTitleOrdinal
                return 'restarted'
            }
            return 'already-running'
        }

        $windowTitleOrdinal = Get-CodexNextWindowTitleOrdinal
        Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port -LauncherKey $LauncherKey -WindowTitleOrdinal $windowTitleOrdinal
        return 'started'
    }

    $matchingProcesses = @($browserProcesses | Where-Object { Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port })

    if ($matchingProcesses.Count -gt 0) {
        return 'already-running'
    }

    if ($browserProcesses.Count -gt 0) {
        if ($AllowRestart) {
            $windowTitleOrdinal = Get-CodexNextWindowTitleOrdinal
            Write-Host 'Restarting Codex with local RTL injection support...' -ForegroundColor Yellow
            Stop-CodexDesktopProcesses
            Start-Sleep -Milliseconds 700
            Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port -WindowTitleOrdinal $windowTitleOrdinal
            return 'restarted'
        }
        return 'running-without-debug-port'
    }

    $windowTitleOrdinal = Get-CodexNextWindowTitleOrdinal
    Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port -WindowTitleOrdinal $windowTitleOrdinal
    return 'started'
}

function Test-CodexDevToolsTarget {
    param([Parameter(Mandatory)]$Target)

    if ($Target.type -ne 'page') { return $false }
    if (-not $Target.webSocketDebuggerUrl) { return $false }

    $url = [string]$Target.url
    return ($url -like 'app://*')
}

function Get-CodexDevToolsTargets {
    param([Parameter(Mandatory)][int]$Port)

    foreach ($base in @("http://127.0.0.1:$Port", "http://[::1]:$Port")) {
        try {
            return @(Invoke-RestMethod -Uri "$base/json/list" -UseBasicParsing -TimeoutSec 2)
        } catch {
            continue
        }
    }
    return @()
}

function Wait-CodexDevToolsTargets {
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSeconds = 60
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $targets = @(Get-CodexDevToolsTargets -Port $Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })
        if ($targets.Count -gt 0) { return $targets }
        Start-Sleep -Milliseconds 500
    }
    return @()
}

function Test-CodexProcessHasVisibleWindow {
    param([Parameter(Mandatory)]$Process)

    try {
        $liveProcess = Get-Process -Id $Process.ProcessId -ErrorAction Stop
        return ($liveProcess.MainWindowHandle -ne 0)
    } catch {
        return $false
    }
}

function Get-CodexVisibleProcessCount {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey
    )

    return @(
        Get-CodexDesktopProcesses | Where-Object {
            Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port -LauncherKey $LauncherKey
        } | Where-Object {
            Test-CodexProcessHasVisibleWindow -Process $_
        }
    ).Count
}

function Wait-CodexInstanceDebugPort {
    param(
        [AllowEmptyString()][string]$LauncherKey,
        [int]$PreferredPort = 0,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $matchingProcesses = @(
            Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $PreferredPort -LauncherKey $LauncherKey
            }
        )
        foreach ($process in $matchingProcesses) {
            $resolvedPort = Get-CodexProcessRtlDebugPort -Process $process
            if ($resolvedPort -gt 0) {
                return $resolvedPort
            }
        }
        Start-Sleep -Milliseconds 500
    }

    return (Get-CodexRtlLaunchPort -PreferredPort $PreferredPort -LauncherKey $LauncherKey)
}

function Start-CodexCloseWatchdog {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey
    )

    $scriptPath = Get-CodexRtlPatchScriptPath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Codex Plus watchdog script not found: $scriptPath"
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $scriptPath,
        '-SkipMain',
        '-StartCloseWatchdog',
        '-WatchPort', $Port
    )
    if (-not [string]::IsNullOrWhiteSpace($LauncherKey)) {
        $args += @('-LauncherKey', $LauncherKey)
    }

    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $args | Out-Null
}

function Watch-CodexCloseToQuit {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey,
        [int]$PollSeconds = 1,
        [int]$GracePolls = 3,
        [int]$StartupWaitSeconds = 30,
        [int]$NoWindowKillAfterSeconds = 12
    )

    $startupDeadline = [DateTime]::UtcNow.AddSeconds($StartupWaitSeconds)
    $seenMatchingProcess = $false
    $matchingProcessSeenAt = $null
    $seenVisibleWindow = $false
    $missingVisibleWindowCount = 0
    while ($true) {
        $matchingProcesses = @(
            Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port -LauncherKey $LauncherKey
            }
        )
        if ($matchingProcesses.Count -eq 0) {
            if ((-not $seenMatchingProcess) -and ([DateTime]::UtcNow -lt $startupDeadline)) {
                Start-Sleep -Seconds $PollSeconds
                continue
            }
            return
        }
        if (-not $seenMatchingProcess) {
            $seenMatchingProcess = $true
            $matchingProcessSeenAt = [DateTime]::UtcNow
        }

        $visibleProcessCount = Get-CodexVisibleProcessCount -Port $Port -LauncherKey $LauncherKey
        if ($visibleProcessCount -gt 0) {
            $seenVisibleWindow = $true
            $missingVisibleWindowCount = 0
            Update-CodexWindowTitles -Port $Port -LauncherKey $LauncherKey | Out-Null
        } else {
            $allowNoWindowKill = $seenVisibleWindow
            if ((-not $allowNoWindowKill) -and $matchingProcessSeenAt) {
                $allowNoWindowKill = ([DateTime]::UtcNow -ge $matchingProcessSeenAt.AddSeconds($NoWindowKillAfterSeconds))
            }
            if ($allowNoWindowKill) {
                $missingVisibleWindowCount++
            } else {
                $missingVisibleWindowCount = 0
            }
        }

        if ($missingVisibleWindowCount -ge $GracePolls) {
            Stop-CodexDesktopProcesses -Port $Port -LauncherKey $LauncherKey -CurrentInstanceOnly
            return
        }

        Start-Sleep -Seconds $PollSeconds
    }
}

function New-CodexCdpCommand {
    param(
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params = @{}
    )

    [pscustomobject]@{
        id = $Id
        method = $Method
        params = [pscustomobject]$Params
    }
}

function Invoke-CodexCdpCommand {
    param(
        [Parameter(Mandatory)][string]$WebSocketDebuggerUrl,
        [Parameter(Mandatory)]$Command
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    $buffer = New-Object byte[] 65536
    try {
        $client.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $json = $Command | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $segment = [ArraySegment[byte]]::new($bytes)
        $client.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $receive = [ArraySegment[byte]]::new($buffer)
        $message = [System.Collections.Generic.List[byte]]::new()
        $result = $client.ReceiveAsync($receive, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw 'Codex DevTools closed the WebSocket before returning a response.'
        }
        if ($result.Count -gt 0) {
            $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
        }
        while (-not $result.EndOfMessage) {
            $result = $client.ReceiveAsync($receive, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'Codex DevTools closed the WebSocket before returning a complete response.'
            }
            if ($result.Count -gt 0) {
                $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
            }
        }
        return [System.Text.Encoding]::UTF8.GetString($message.ToArray())
    } finally {
        if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $client.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        }
        $client.Dispose()
    }
}

function Invoke-CodexRtlInjectionForTarget {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$Payload
    )

    $commands = @(
        (New-CodexCdpCommand -Id 1 -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{
            source = $Payload
            runImmediately = $true
        }),
        (New-CodexCdpCommand -Id 2 -Method 'Runtime.evaluate' -Params @{
            expression = $Payload
            awaitPromise = $true
            returnByValue = $true
        })
    )

    foreach ($command in $commands) {
        Invoke-CodexCdpCommand -WebSocketDebuggerUrl $Target.webSocketDebuggerUrl -Command $command | Out-Null
    }
}

function Invoke-CodexRtlInjection {
    param([Parameter(Mandatory)][int]$Port)

    $payload = Get-CodexPlusPayloadBundle
    $targets = @(Wait-CodexDevToolsTargets -Port $Port)
    if ($targets.Count -eq 0) {
        Start-Sleep -Seconds 5
        $targets = @(Wait-CodexDevToolsTargets -Port $Port -TimeoutSeconds 20)
    }
    if ($targets.Count -eq 0) {
        Write-Warn "Codex DevTools target was not found on port $Port."
        return $false
    }

    foreach ($target in $targets) {
        try {
            Invoke-CodexRtlInjectionForTarget -Target $target -Payload $payload
        } catch {
            Write-Warn "Codex Plus injection failed for target '$($target.title)': $($_.Exception.Message)"
        }
    }
    Update-CodexWindowTitles -Port $Port | Out-Null
    return $true
}
