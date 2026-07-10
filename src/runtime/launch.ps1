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
    param([Parameter(Mandatory)][int]$Port)

    $args = @(
        "--remote-debugging-port=$Port",
        '--remote-debugging-address=127.0.0.1'
    )
    $userDataDir = Get-CodexPlusUserDataDirectory
    if ($userDataDir) {
        $args += "--user-data-dir=$userDataDir"
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

function Test-CodexProcessMatchesCodexPlusInstance {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][int]$Port
    )

    if (-not (Test-CodexProcessIsBrowserProcess -Process $Process)) {
        return $false
    }

    $expectedUserDataDir = Normalize-CodexRtlMatchPath -Path (Get-CodexPlusUserDataDirectory)
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
    param([int]$PreferredPort = 0)

    $port = if ($PreferredPort -gt 0) { $PreferredPort } else { Get-CodexRtlDefaultPort }
    $matchingProcesses = @(
        Get-CodexDesktopProcesses | Where-Object {
            Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $port
        }
    )
    if ($matchingProcesses.Count -gt 0) { return $port }
    if (Test-TcpPortAvailable -Port $port) { return $port }
    return (Get-CodexRtlAvailablePort -StartPort ($port + 1))
}

function Stop-CodexDesktopProcesses {
    param(
        [int]$Port = 0,
        [switch]$CurrentInstanceOnly
    )

    foreach ($process in @(Get-CodexDesktopProcesses)) {
        if (-not (Test-CodexProcessIsBrowserProcess -Process $process)) {
            continue
        }
        if ($CurrentInstanceOnly) {
            if (-not (Test-CodexProcessMatchesCodexPlusInstance -Process $process -Port $Port)) {
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
        [Parameter(Mandatory)][int]$Port
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $AppExe
    $startInfo.Arguments = Join-CodexRtlProcessArguments -Arguments (New-CodexRtlLaunchArguments -Port $Port)
    $startInfo.WorkingDirectory = Get-CodexRtlWorkingDirectory
    $startInfo.UseShellExecute = $false

    $userDataDir = Get-CodexPlusUserDataDirectory
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
        [switch]$AllowRestart
    )

    $processes = @(Get-CodexDesktopProcesses)
    $browserProcesses = @($processes | Where-Object { Test-CodexProcessIsBrowserProcess -Process $_ })
    $matchingProcesses = @($browserProcesses | Where-Object { Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port })

    if ($matchingProcesses.Count -gt 0) {
        return 'already-running'
    }

    if ($browserProcesses.Count -gt 0) {
        if ($AllowRestart) {
            Write-Host 'Restarting Codex with local RTL injection support...' -ForegroundColor Yellow
            Stop-CodexDesktopProcesses
            Start-Sleep -Milliseconds 700
            Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port
            return 'restarted'
        }
        return 'running-without-debug-port'
    }

    Start-CodexWithRtlDebug -AppExe $Inspection.AppExe -Port $Port
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
    return $true
}
