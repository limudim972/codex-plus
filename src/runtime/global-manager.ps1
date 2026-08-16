function Get-CodexPlusManagerIdentity {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = [string]$identity.User.Value
    $safeSid = $sid.Replace('-', '_')
    [pscustomobject]@{
        Sid = $sid
        PipeName = "CodexPlusManager_$safeSid"
        MutexName = "Local\CodexPlusManager_$safeSid"
        ProtocolVersion = 1
    }
}

function Get-CodexPlusManagerLogPath {
    Join-Path (Get-CodexRtlRuntimeRoot) 'manager.log'
}

function Get-CodexPlusRuntimeVersion {
    '2026.08.03.3'
}

function Get-CodexPlusRuntimeFingerprint {
    param([Parameter(Mandatory)][string]$RuntimeRoot)

    $files = @(
        Get-Item -LiteralPath (Join-Path $RuntimeRoot 'patch.ps1') -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $RuntimeRoot 'src') -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue
    ) | Where-Object { $_ } | Sort-Object FullName
    $manifest = foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($RuntimeRoot.Length).TrimStart('\').Replace('\', '/')
        '{0}:{1}' -f $relativePath, (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes(($manifest -join "`n"))))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Send-CodexPlusManagerCommand {
    param(
        [Parameter(Mandatory)][hashtable]$Command,
        [int]$ConnectTimeoutMilliseconds = 750
    )

    $identity = Get-CodexPlusManagerIdentity
    $pipe = [IO.Pipes.NamedPipeClientStream]::new(
        '.',
        $identity.PipeName,
        [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::Asynchronous
    )
    try {
        $pipe.Connect($ConnectTimeoutMilliseconds)
        $writer = [IO.StreamWriter]::new($pipe)
        $writer.AutoFlush = $true
        $reader = [IO.StreamReader]::new($pipe)
        $writer.WriteLine(($Command | ConvertTo-Json -Depth 8 -Compress))
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw 'The Codex Plus manager returned an empty response.'
        }
        return ($line | ConvertFrom-Json)
    } finally {
        $pipe.Dispose()
    }
}

function Get-CodexPlusGlobalManagerProcesses {
    $scriptPath = Get-CodexRtlPatchScriptPath
    $normalizedScriptPath = ([string]$scriptPath).Replace('/', '\')
    try {
        return @(
            Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction Stop |
                Where-Object {
                    $_.ProcessId -ne $PID -and
                    $_.CommandLine -and
                    $_.CommandLine -like '*-StartGlobalManager*' -and
                    $_.CommandLine.IndexOf($normalizedScriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
                }
        )
    } catch {
        return @()
    }
}

function Stop-CodexPlusGlobalManagerProcesses {
    foreach ($process in @(Get-CodexPlusGlobalManagerProcesses)) {
        try {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
        } catch {
        }
    }
}

function Ensure-CodexPlusGlobalManager {
    param([int]$StartupTimeoutMilliseconds = 7000)

    $identity = Get-CodexPlusManagerIdentity
    try {
        $status = Send-CodexPlusManagerCommand -Command @{ action = 'status' } -ConnectTimeoutMilliseconds 150
        if ($status.ok -and [int]$status.protocol_version -eq $identity.ProtocolVersion) {
            return $status
        }
    } catch {
    }

    # A manager can remain alive after its named pipe has stopped accepting
    # connections. Its mutex then prevents the replacement manager from
    # starting, so recover the exact stale manager before bootstrapping a new
    # one. The process filter is restricted to this runtime's script path and
    # excludes the current launcher process.
    $staleManagers = @(Get-CodexPlusGlobalManagerProcesses)
    if ($staleManagers.Count -gt 0) {
        Stop-CodexPlusGlobalManagerProcesses
        Start-Sleep -Milliseconds 200
    }

    $scriptPath = Get-CodexRtlPatchScriptPath
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', ('"{0}"' -f $scriptPath),
        '-SkipMain',
        '-StartGlobalManager'
    )
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $arguments | Out-Null

    # This is a bounded startup handshake, not a recurring runtime poll.
    $deadline = [DateTime]::UtcNow.AddMilliseconds($StartupTimeoutMilliseconds)
    do {
        try {
            $status = Send-CodexPlusManagerCommand -Command @{ action = 'status' } -ConnectTimeoutMilliseconds 150
            if ($status.ok -and [int]$status.protocol_version -eq $identity.ProtocolVersion) {
                return $status
            }
        } catch {
        }
        Start-Sleep -Milliseconds 75
    } while ([DateTime]::UtcNow -lt $deadline)

    throw 'The independent Codex Plus manager did not become ready.'
}

function Register-CodexPlusManagerInstance {
    param(
        [AllowEmptyString()][string]$LauncherKey,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$UserDataDirectory
    )

    Ensure-CodexPlusGlobalManager | Out-Null
    $response = Send-CodexPlusManagerCommand -Command @{
        action = 'register'
        launcher_key = $LauncherKey
        port = $Port
        user_data_dir = $UserDataDirectory
    }
    if (-not $response.ok) {
        throw "Codex Plus manager registration failed: $($response.error)"
    }
    return $response
}

function Unregister-CodexPlusManagerInstance {
    param([AllowEmptyString()][string]$LauncherKey)
    try {
        Send-CodexPlusManagerCommand -Command @{ action = 'unregister'; launcher_key = $LauncherKey } -ConnectTimeoutMilliseconds 250
    } catch {
        $null
    }
}

function New-CodexPlusManagerPipeServer {
    param([Parameter(Mandatory)]$Identity)

    $sid = [Security.Principal.SecurityIdentifier]::new($Identity.Sid)
    $security = [IO.Pipes.PipeSecurity]::new()
    $security.SetOwner($sid)
    $security.SetAccessRuleProtection($true, $false)
    $security.AddAccessRule([IO.Pipes.PipeAccessRule]::new(
        $sid,
        [IO.Pipes.PipeAccessRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow
    ))
    return [IO.Pipes.NamedPipeServerStream]::new(
        $Identity.PipeName,
        [IO.Pipes.PipeDirection]::InOut,
        8,
        [IO.Pipes.PipeTransmissionMode]::Byte,
        [IO.Pipes.PipeOptions]::Asynchronous,
        8192,
        8192,
        $security
    )
}

function Start-CodexPlusGlobalManager {
    $identity = Get-CodexPlusManagerIdentity
    $mutex = [Threading.Mutex]::new($false, $identity.MutexName)
    $ownsMutex = $false
    try {
        try { $ownsMutex = $mutex.WaitOne(0, $false) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { return }

        $runtimeRoot = Get-CodexRtlRuntimeRoot
        $logPath = Get-CodexPlusManagerLogPath
        $runtimeVersion = Get-CodexPlusRuntimeVersion
        $runtimeFingerprint = Get-CodexPlusRuntimeFingerprint -RuntimeRoot $runtimeRoot
        $shared = [hashtable]::Synchronized(@{
            Queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
            Signal = [Threading.AutoResetEvent]::new($false)
        })
        $instances = @{}
        $scheduled = @{}
        $eventRegistrations = [Collections.ArrayList]::new()
        $eventSources = [Collections.ArrayList]::new()
        $nativeWindowWatcher = $null
        $dashboard = [pscustomobject]@{ State = 'stopped'; PowerShell = $null; Async = $null; Root = $null }
        $managerState = [pscustomobject]@{ UsageRevision = 0; UsageSource = $null; Stopping = $false }
        $script:CodexPlusGlobalUsageAuthority = $true
        $eventCounters = @{}
        $startedAt = [DateTimeOffset]::UtcNow

        function Write-ManagerLog {
            param(
                [Parameter(Mandatory)][string]$Event,
                [hashtable]$Fields = @{}
            )
            try {
                $entry = [ordered]@{
                    timestamp = [DateTimeOffset]::UtcNow.ToString('o')
                    event = $Event
                    manager_pid = $PID
                }
                foreach ($key in $Fields.Keys) {
                    $entry[$key] = $Fields[$key]
                }
                Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ($entry | ConvertTo-Json -Depth 12 -Compress)
            } catch {
            }
        }

        try {
            # Keep one easy-to-read diagnostic session. The manager is global,
            # so every subsequent event is serialized by its coordinator loop.
            Set-Content -LiteralPath $logPath -Encoding UTF8 -Value ([string]::Empty)
        } catch {
        }

        function Add-EventCount {
            param([string]$Name)
            if (-not $eventCounters.ContainsKey($Name)) { $eventCounters[$Name] = 0 }
            $eventCounters[$Name] = [int]$eventCounters[$Name] + 1
        }

        function Set-ManagerTask {
            param([string]$Key, [int]$DelayMilliseconds, [string]$Kind, $Data)
            $scheduled[$Key] = [pscustomobject]@{
                Key = $Key
                Due = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(0, $DelayMilliseconds))
                Kind = $Kind
                Data = $Data
            }
            [void]$shared.Signal.Set()
        }

        function Remove-ManagerTask {
            param([string]$Key)
            if ($scheduled.ContainsKey($Key)) { $scheduled.Remove($Key) }
        }

        function Stop-CdpWorker {
            param($Instance)
            if (-not $Instance) { return }
            try { if ($Instance.CdpCancellation) { $Instance.CdpCancellation.Cancel() } } catch { }
            try { if ($Instance.CdpPowerShell) { $Instance.CdpPowerShell.Stop() } } catch { }
            try { if ($Instance.CdpPowerShell) { $Instance.CdpPowerShell.Dispose() } } catch { }
            try { if ($Instance.CdpCancellation) { $Instance.CdpCancellation.Dispose() } } catch { }
            $Instance.CdpPowerShell = $null
            $Instance.CdpCancellation = $null
            $Instance.CdpConnected = $false
            $Instance.CdpStarting = $false
        }

        function Start-CdpWorker {
            param($Instance)
            if (-not $Instance) { return }
            Stop-CdpWorker -Instance $Instance
            $cancellation = [Threading.CancellationTokenSource]::new()
            $worker = [PowerShell]::Create()
            $workerScript = @'
param($Shared, [int]$Port, [string]$LauncherKey, $Cancellation)
function Publish($Message) {
    [void]$Shared.Queue.Enqueue($Message)
    [void]$Shared.Signal.Set()
}
$client = $null
$disconnectPublished = $false
$disconnectReason = 'unknown'
try {
    $version = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/version" -f $Port) -TimeoutSec 2
    if (-not $version.webSocketDebuggerUrl) { throw 'Browser WebSocket URL was not published.' }
    $client = [Net.WebSockets.ClientWebSocket]::new()
    $client.ConnectAsync([Uri]$version.webSocketDebuggerUrl, $Cancellation.Token).GetAwaiter().GetResult()
    $command = [Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"Target.setDiscoverTargets","params":{"discover":true}}')
    $client.SendAsync([ArraySegment[byte]]::new($command), [Net.WebSockets.WebSocketMessageType]::Text, $true, $Cancellation.Token).GetAwaiter().GetResult()
    Publish ([pscustomobject]@{ kind='cdp-connected'; launcher_key=$LauncherKey; port=$Port })
    $buffer = New-Object byte[] 65536
    while (-not $Cancellation.IsCancellationRequested -and $client.State -eq [Net.WebSockets.WebSocketState]::Open) {
        $bytes = [Collections.Generic.List[byte]]::new()
        do {
            $result = $client.ReceiveAsync([ArraySegment[byte]]::new($buffer), $Cancellation.Token).GetAwaiter().GetResult()
            if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
                $disconnectReason = 'remote-close'
                break
            }
            if ($result.Count -gt 0) { $bytes.AddRange([byte[]]$buffer[0..($result.Count - 1)]) }
        } while (-not $result.EndOfMessage)
        if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { break }
        if ($bytes.Count -eq 0) { continue }
        try { $message = [Text.Encoding]::UTF8.GetString($bytes.ToArray()) | ConvertFrom-Json } catch { continue }
        if ([string]$message.method -like 'Target.*') {
            $targetInfo = $message.params.targetInfo
            Publish ([pscustomobject]@{
                kind='cdp-target'
                launcher_key=$LauncherKey
                method=[string]$message.method
                target_id=if ($targetInfo) { [string]$targetInfo.targetId } else { [string]$message.params.targetId }
                target_type=if ($targetInfo) { [string]$targetInfo.type } else { '' }
                target_url=if ($targetInfo) { [string]$targetInfo.url } else { '' }
                params=$message.params
            })
        } elseif ([string]$message.method -eq 'Inspector.detached') {
            Publish ([pscustomobject]@{
                kind='cdp-inspector-detached'
                launcher_key=$LauncherKey
                reason='inspector-detached'
                error=[string]$message.params.reason
            })
        }
    }
} catch {
    if (-not $Cancellation.IsCancellationRequested) {
        $disconnectReason = 'error'
        Publish ([pscustomobject]@{ kind='cdp-disconnected'; launcher_key=$LauncherKey; reason=$disconnectReason; error=$_.Exception.Message })
        $disconnectPublished = $true
    }
} finally {
    if (-not $Cancellation.IsCancellationRequested -and -not $disconnectPublished) {
        Publish ([pscustomobject]@{ kind='cdp-disconnected'; launcher_key=$LauncherKey; reason=$disconnectReason; error='' })
    }
    try { if ($client) { $client.Dispose() } } catch { }
}
'@
            [void]$worker.AddScript($workerScript).AddArgument($shared).AddArgument([int]$Instance.Port).AddArgument([string]$Instance.Key).AddArgument($cancellation)
            $Instance.CdpCancellation = $cancellation
            $Instance.CdpPowerShell = $worker
            $Instance.CdpAsync = $worker.BeginInvoke()
            $Instance.CdpStarting = $true
            $Instance.CdpAttempt += 1
            Add-EventCount 'cdp_worker_started'
        }

        function Stop-RefreshWorker {
            param($Instance)
            if (-not $Instance) { return }
            try { if ($Instance.RefreshPowerShell) { $Instance.RefreshPowerShell.Stop() } } catch { }
            try { if ($Instance.RefreshPowerShell) { $Instance.RefreshPowerShell.Dispose() } } catch { }
            $Instance.RefreshPowerShell = $null
            $Instance.RefreshAsync = $null
            $Instance.RefreshRunning = $false
        }

        function Refresh-ManagerInstance {
            param($Instance)
            if (-not $Instance) { return }
            if ($Instance.RefreshRunning -and $Instance.RefreshAsync -and -not $Instance.RefreshAsync.IsCompleted) {
                $Instance.RefreshPending = $true
                return
            }
            Stop-RefreshWorker -Instance $Instance
            $worker = [PowerShell]::Create()
            $workerScript = @'
param($Shared, $Instance, $UsageCache, [string]$PatchScript)
$errorMessage = $null
try {
    . $PatchScript -SkipMain
    $script:CodexPlusGlobalUsageAuthority = $true
    $script:CodexPlusRateLimitTitleCache = $UsageCache
    $script:CodexPlusInjectedTargetIds = $Instance.InjectedTargetIds
    $script:CodexPlusKnownWindowHandles = $Instance.KnownWindowHandles
    $script:CodexPlusPrimaryWindowHandles = $Instance.PrimaryWindowHandles
    $script:CodexPlusWindowProjectNames = $Instance.WindowProjectNames
    $script:CodexPlusProjectWindowOrder = @($Instance.ProjectWindowOrder)

    $matching = @(Get-CodexDesktopProcesses | Where-Object {
        Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Instance.Port -LauncherKey $Instance.Key
    })
    foreach ($process in $matching) { $Instance.SeenProcessIds[[string]$process.ProcessId] = $true }
    if ($matching.Count -gt 0) { $Instance.HasSeenProcess = $true }
    if ((Get-CodexVisibleProcessCount -Port $Instance.Port -LauncherKey $Instance.Key) -gt 0) { $Instance.HasSeenWindow = $true }

    $targets = @(Get-CodexDevToolsTargets -Port $Instance.Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })
    if ($targets.Count -gt 0) { $Instance.HasSeenTarget = $true }
    if (-not $Instance.Payload) { $Instance.Payload = Get-CodexPlusPayloadBundle }
    foreach ($target in $targets) {
        $targetId = [string]$target.id
        if ($targetId -and $Instance.InjectedTargetIds.ContainsKey($targetId)) { continue }
        try {
            Invoke-CodexRtlInjectionForTarget -Target $target -Payload $Instance.Payload
            if ($targetId) { $Instance.InjectedTargetIds[$targetId] = $true }
        } catch { }
    }
    Maximize-CodexPlusWindows -Port $Instance.Port -LauncherKey $Instance.Key | Out-Null
    Update-CodexWindowTitles -Port $Instance.Port -LauncherKey $Instance.Key | Out-Null
    $Instance.InjectedTargetIds = $script:CodexPlusInjectedTargetIds
    $Instance.KnownWindowHandles = $script:CodexPlusKnownWindowHandles
    $Instance.PrimaryWindowHandles = $script:CodexPlusPrimaryWindowHandles
    $Instance.WindowProjectNames = $script:CodexPlusWindowProjectNames
    $Instance.ProjectWindowOrder = @($script:CodexPlusProjectWindowOrder)
    $Instance.LastRefresh = [DateTimeOffset]::UtcNow
} catch {
    $errorMessage = $_.Exception.Message
} finally {
    [void]$Shared.Queue.Enqueue([pscustomobject]@{ kind='refresh-complete'; launcher_key=[string]$Instance.Key; error=$errorMessage })
    [void]$Shared.Signal.Set()
}
'@
            $patchScript = Join-Path $runtimeRoot 'patch.ps1'
            [void]$worker.AddScript($workerScript).AddArgument($shared).AddArgument($Instance).AddArgument($script:CodexPlusRateLimitTitleCache).AddArgument($patchScript)
            $Instance.RefreshPowerShell = $worker
            $Instance.RefreshRunning = $true
            $Instance.RefreshPending = $false
            $Instance.RefreshAsync = $worker.BeginInvoke()
            Add-EventCount 'refresh_worker_started'
        }

        function Remove-ManagerInstance {
            param([string]$Key, [switch]$StopProcesses)
            if (-not $instances.ContainsKey($Key)) { return }
            $instance = $instances[$Key]
            if ($StopProcesses) {
                $knownProcessIds = @($instance.SeenProcessIds.Keys | ForEach-Object { [int]$_ })
                try {
                    Stop-CodexDesktopProcesses -Port $instance.Port -LauncherKey $instance.Key -CurrentInstanceOnly -KnownProcessIds $knownProcessIds
                } catch { }
            }
            Stop-RefreshWorker -Instance $instance
            Stop-CdpWorker -Instance $instance
            $instances.Remove($Key)
            Add-EventCount 'instance_removed'
            Write-ManagerLog -Event 'instance-removed' -Fields @{ launcher_key=$Key; stop_processes=[bool]$StopProcesses }
            if ($instances.Count -eq 0) {
                Set-ManagerTask -Key 'manager-idle' -DelayMilliseconds 5000 -Kind 'manager-idle' -Data $null
            }
        }

        function Test-ManagerInstanceClosed {
            param($Instance)
            if (-not $Instance) { return }
            $matching = @(Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Instance.Port -LauncherKey $Instance.Key
            })
            foreach ($process in $matching) { $Instance.SeenProcessIds[[string]$process.ProcessId] = $true }
            $visible = Get-CodexVisibleProcessCount -Port $Instance.Port -LauncherKey $Instance.Key
            $windowSnapshot = @(
                foreach ($process in $matching) {
                    $handles = @()
                    try { $handles = @(Get-CodexVisibleWindowHandles -ProcessId ([int]$process.ProcessId)) } catch { }
                    $mainWindowHandle = 0
                    try { $mainWindowHandle = [int64](Get-Process -Id $process.ProcessId -ErrorAction Stop).MainWindowHandle } catch { }
                    [ordered]@{
                        process_id = [int]$process.ProcessId
                        main_window_handle = $mainWindowHandle
                        visible_window_handles = @($handles | ForEach-Object { [int64]$_ })
                    }
                }
            )
            $visibleWindowCount = @($windowSnapshot | ForEach-Object { @($_.visible_window_handles) }).Count
            $targets = @(Get-CodexDevToolsTargets -Port $Instance.Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })
            if ($targets.Count -eq 0 -and $matching.Count -gt 0 -and
                ([DateTime]::UtcNow -ge $Instance.StartupDeadline -or $Instance.HasSeenTarget)) {
                Write-ManagerLog -Event 'close-check' -Fields @{
                    launcher_key=$Instance.Key
                    port=$Instance.Port
                    matching_process_count=$matching.Count
                    visible_process_count=$visible
                    visible_window_count=$visibleWindowCount
                    devtools_target_count=0
                    process_snapshot=$windowSnapshot
                    has_seen_target=[bool]$Instance.HasSeenTarget
                    action='remove-empty-devtools-target-list'
                }
                Remove-ManagerInstance -Key $Instance.Key -StopProcesses
                return
            }
            if ($visible -gt 0) {
                $Instance.HasSeenWindow = $true
                Write-ManagerLog -Event 'close-check' -Fields @{
                    launcher_key=$Instance.Key
                    port=$Instance.Port
                    matching_process_count=$matching.Count
                    visible_process_count=$visible
                    visible_window_count=$visibleWindowCount
                    process_snapshot=$windowSnapshot
                    has_seen_window=[bool]$Instance.HasSeenWindow
                    action='keep-visible'
                }
                return
            }
            if ($Instance.HasSeenWindow) {
                Write-ManagerLog -Event 'close-check' -Fields @{
                    launcher_key=$Instance.Key
                    port=$Instance.Port
                    matching_process_count=$matching.Count
                    visible_process_count=$visible
                    visible_window_count=$visibleWindowCount
                    process_snapshot=$windowSnapshot
                    has_seen_window=[bool]$Instance.HasSeenWindow
                    action='remove-and-stop-processes'
                }
                Remove-ManagerInstance -Key $Instance.Key -StopProcesses
            } elseif ([DateTime]::UtcNow -ge $Instance.StartupDeadline -and $matching.Count -eq 0) {
                Write-ManagerLog -Event 'close-check' -Fields @{
                    launcher_key=$Instance.Key
                    port=$Instance.Port
                    matching_process_count=$matching.Count
                    visible_process_count=$visible
                    visible_window_count=$visibleWindowCount
                    process_snapshot=$windowSnapshot
                    has_seen_window=[bool]$Instance.HasSeenWindow
                    action='remove-startup-timeout'
                }
                Remove-ManagerInstance -Key $Instance.Key
            } else {
                Write-ManagerLog -Event 'close-check' -Fields @{
                    launcher_key=$Instance.Key
                    port=$Instance.Port
                    matching_process_count=$matching.Count
                    visible_process_count=$visible
                    visible_window_count=$visibleWindowCount
                    process_snapshot=$windowSnapshot
                    has_seen_window=[bool]$Instance.HasSeenWindow
                    action='keep-not-ready'
                }
            }
        }

        function Get-UsageCandidate {
            param([string[]]$Paths)
            $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
            $changedFiles = if (@($Paths).Count -gt 0) {
                @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object {
                    Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue
                } | Where-Object { $_ -and $_.Extension -eq '.jsonl' } | Sort-Object LastWriteTime -Descending)
            } else {
                @()
            }
            # FileSystemWatcher can report the write before the token_count
            # record is flushed. Always keep a bounded newest-session fallback
            # so a missed/early event cannot leave the shared usage cache stale.
            $recentFiles = @(Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 100)
            $files = @($changedFiles + $recentFiles | Where-Object { $_ } |
                Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending)
            foreach ($file in $files) {
                $primary = $null
                foreach ($line in Get-Content -LiteralPath $file.FullName -Tail 10 -ErrorAction SilentlyContinue) {
                    try { $object = $line | ConvertFrom-Json } catch { continue }
                    $payload = if ($object.payload -is [pscustomobject]) { $object.payload } elseif ($object.event_msg -is [pscustomobject]) { $object.event_msg } else { $null }
                    if ($payload -and $payload.rate_limits -and $payload.rate_limits.primary) {
                        $primary = $payload.rate_limits.primary
                    }
                }
                if ($primary -and $null -ne $primary.used_percent -and $null -ne $primary.resets_at) {
                    return [pscustomobject]@{ Primary = $primary; Path = $file.FullName; LastWriteTime = $file.LastWriteTimeUtc }
                }
            }
            return $null
        }

        function Schedule-UsageBoundary {
            Remove-ManagerTask -Key 'usage-boundary'
            $cache = $script:CodexPlusRateLimitTitleCache
            if (-not $cache -or $null -eq $cache.resets_at) { return }
            $now = [DateTimeOffset]::UtcNow
            $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$cache.resets_at)
            $remaining = $reset - $now
            if ($remaining.TotalSeconds -le 0) { return }
            if ($remaining.TotalDays -ge 1) {
                $units = [Math]::Round($remaining.TotalDays, 0, [MidpointRounding]::AwayFromZero)
                $next = $reset.AddDays(-($units - 0.5)).AddMilliseconds(50)
            } elseif ($remaining.TotalHours -ge 1) {
                $units = [Math]::Ceiling($remaining.TotalHours)
                $next = $reset.AddHours(-($units - 1)).AddMilliseconds(50)
            } else {
                $units = [Math]::Ceiling($remaining.TotalMinutes)
                $next = $reset.AddMinutes(-($units - 1)).AddMilliseconds(50)
            }
            # Refresh the published title hourly so the elapsed-time percentage
            # stays current even when the usage data itself has not changed.
            $hourly = $now.AddHours(1)
            if ($hourly -lt $next) { $next = $hourly }
            $delay = [Math]::Max(1, [int][Math]::Min([int]::MaxValue, ($next - $now).TotalMilliseconds))
            Set-ManagerTask -Key 'usage-boundary' -DelayMilliseconds $delay -Kind 'usage-boundary' -Data $null
        }

        function Refresh-GlobalUsage {
            param([string[]]$Paths)
            $candidate = Get-UsageCandidate -Paths $Paths
            if ($candidate) {
                $script:CodexPlusRateLimitTitleCache = [pscustomobject]@{
                    fetched_at = [DateTimeOffset]::UtcNow
                    used_percent = $candidate.Primary.used_percent
                    resets_at = $candidate.Primary.resets_at
                }
                $managerState.UsageRevision += 1
                $managerState.UsageSource = $candidate.Path
                Add-EventCount 'usage_revision'
                foreach ($instance in @($instances.Values)) { Refresh-ManagerInstance -Instance $instance }
                Schedule-UsageBoundary
            } elseif (@($Paths).Count -gt 0) {
                # The write notification may have preceded the flush. Retry
                # after the producer has had time to finish the JSONL record.
                Set-ManagerTask -Key 'usage-retry' -DelayMilliseconds 500 -Kind 'usage-refresh' -Data $null
            }
            if (@($Paths).Count -gt 0) {
                Update-CodexPrematureSessionState -Paths $Paths
                foreach ($path in @($script:CodexPlusPrematurePending.Keys)) {
                    $pending = $script:CodexPlusPrematurePending[$path]
                    if (-not $pending) { continue }
                    $due = if ($pending.shell_error) { [DateTime]::UtcNow } else { $pending.last_activity.AddSeconds(120) }
                    $delay = [Math]::Max(1, [int][Math]::Min([int]::MaxValue, ($due - [DateTime]::UtcNow).TotalMilliseconds))
                    Set-ManagerTask -Key ("session-alert:$path") -DelayMilliseconds $delay -Kind 'session-alert' -Data $path
                }
            }
        }

        function Publish-PrematureAlert {
            param([string]$Path)
            Update-CodexPrematureSessionState -Paths @($Path)
            foreach ($alert in @(Get-CodexPrematureSessionAlerts)) {
                if (Test-CodexAutomaticContinuationError -Alert $alert) {
                    # The manager is process-global for all Plus windows. Key by
                    # thread, rather than by target/window or retry record, so a
                    # failed continuation cannot recursively create another one.
                    $attemptKey = [string]$alert.session
                    if (-not $script:CodexPlusAutoContinuationAttempted.ContainsKey($attemptKey)) {
                        $script:CodexPlusAutoContinuationAttempted[$attemptKey] = $true
                        $detail = (@{ session = [string]$alert.session } | ConvertTo-Json -Compress)
                        $probe = New-CodexCdpCommand -Id 91 -Method 'Runtime.evaluate' -Params @{
                            expression = "JSON.stringify((()=>{const detail=$detail;return {can:Boolean(window.__CODEX_PLUS_AUTO_CONTINUE_CAN_HANDLE_ERROR?.(detail)),preferred:Boolean(window.__CODEX_PLUS_AUTO_CONTINUE_PREFERS_ERROR?.(detail))}})())"
                            returnByValue = $true
                        }
                        $fallbackTarget = $null
                        $preferredTarget = $null
                        foreach ($instance in @($instances.Values)) {
                            if ($preferredTarget) { break }
                            foreach ($target in @(Get-CodexDevToolsTargets -Port $instance.Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })) {
                                try {
                                    $probeResponse = Invoke-CodexCdpCommand -WebSocketDebuggerUrl $target.webSocketDebuggerUrl -Command $probe
                                    $probePayload = $probeResponse | ConvertFrom-Json
                                    $probeResult = $probePayload.result.result.value | ConvertFrom-Json
                                    if (-not [bool]$probeResult.can) { continue }
                                    if (-not $fallbackTarget) { $fallbackTarget = $target }
                                    if ([bool]$probeResult.preferred) {
                                        $preferredTarget = $target
                                        break
                                    }
                                } catch { }
                            }
                        }
                        $selectedTarget = if ($preferredTarget) { $preferredTarget } else { $fallbackTarget }
                        $continuationStatus = 'failed'
                        $continuationReason = 'no-live-codex-page'
                        $continuationMessage = 'Auto-continue could not start because no live Codex page was available.'
                        if ($selectedTarget) {
                            $command = New-CodexCdpCommand -Id 92 -Method 'Runtime.evaluate' -Params @{
                                expression = "(async()=>{const detail=$detail;window.dispatchEvent(new CustomEvent('codex-plus-auto-continue',{detail}));const result=await window.__CODEX_PLUS_AUTO_CONTINUE_LAST_PROMISE;return JSON.stringify(result||{ok:false,reason:'handler-did-not-report'});})()"
                                awaitPromise = $true
                                returnByValue = $true
                            }
                            try {
                                $response = Invoke-CodexCdpCommand -WebSocketDebuggerUrl $selectedTarget.webSocketDebuggerUrl -Command $command
                                $value = $response.result.result.value
                                $result = if ($value -is [string]) { $value | ConvertFrom-Json } else { $value }
                                if ([bool]$result.ok) {
                                    $continuationStatus = 'started'
                                    $continuationReason = 'started'
                                    $continuationMessage = 'Auto-continue started a new turn after the model-capacity error.'
                                } elseif ($result.reason) {
                                    $continuationReason = [string]$result.reason
                                    $continuationMessage = if ($result.error) { "Auto-continue failed: $($result.error)" } elseif ($result.message) { [string]$result.message } else { "Auto-continue failed: $continuationReason." }
                                }
                            } catch {
                                $continuationReason = 'cdp-dispatch-failed'
                                $continuationMessage = "Auto-continue could not reach the Codex page: $($_.Exception.Message)"
                            }
                        }
                        Write-ManagerLog -Event (if ($continuationStatus -eq 'started') { 'auto-continue-started' } else { 'auto-continue-failed' }) -Fields @{
                            session=[string]$alert.session
                            reason=$continuationReason
                            target_id=if ($selectedTarget) { [string]$selectedTarget.id } else { '' }
                        }
                        Show-CodexAutoContinueAlert -Status $continuationStatus -Message $continuationMessage -Session ([string]$alert.session)
                    }
                    $script:CodexPlusPrematurePending.Remove($Path)
                    continue
                }
                Show-CodexPrematureSessionAlert -Alert $alert
                $alertJson = $script:CodexPlusPrematureAlertPayload
                $command = New-CodexCdpCommand -Id 91 -Method 'Runtime.evaluate' -Params @{
                    expression = "window.dispatchEvent(new CustomEvent('codex-plus-session-alert',{detail:$alertJson}));"
                }
                foreach ($instance in @($instances.Values)) {
                    foreach ($target in @(Get-CodexDevToolsTargets -Port $instance.Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })) {
                        try { Invoke-CodexCdpCommand -WebSocketDebuggerUrl $target.webSocketDebuggerUrl -Command $command | Out-Null } catch { }
                    }
                }
            }
        }

        function Start-ManagerDashboard {
            if ($dashboard.PowerShell -and -not $dashboard.Async.IsCompleted) { return }
            if (-not (Test-TcpPortAvailable -Port 3000)) {
                $dashboard.State = 'external-transition'
                return
            }
            $dashboardScript = Join-Path $runtimeRoot 'src\runtime\dashboard-server.ps1'
            $dashboardRoot = Join-Path $env:USERPROFILE 'Documents\code\Codex Usage Dashboard'
            $powerShell = [PowerShell]::Create()
            [void]$powerShell.AddCommand($dashboardScript).AddParameter('DashboardRoot', $dashboardRoot).AddParameter('Port', 3000)
            $dashboard.PowerShell = $powerShell
            $dashboard.Async = $powerShell.BeginInvoke()
            $dashboard.Root = $dashboardRoot
            $dashboard.State = 'starting'
            Set-ManagerTask -Key 'dashboard-check' -DelayMilliseconds 500 -Kind 'dashboard-check' -Data $null
        }

        function Get-ManagerStatus {
            $instanceStatus = foreach ($instance in @($instances.Values)) {
                [ordered]@{
                    launcher_key = $instance.Key
                    port = $instance.Port
                    user_data_dir = $instance.UserDataDirectory
                    cdp_connected = [bool]$instance.CdpConnected
                    targets_seen = [bool]$instance.HasSeenTarget
                    visible_window_seen = [bool]$instance.HasSeenWindow
                    process_ids = @($instance.SeenProcessIds.Keys | ForEach-Object { [int]$_ })
                    injected_target_count = $instance.InjectedTargetIds.Count
                    last_refresh = if ($instance.LastRefresh) { $instance.LastRefresh.ToString('o') } else { $null }
                }
            }
            [ordered]@{
                ok = $true
                protocol_version = $identity.ProtocolVersion
                manager_pid = $PID
                started_at = $startedAt.ToString('o')
                instance_count = $instances.Count
                instances = @($instanceStatus)
                usage = [ordered]@{
                    revision = $managerState.UsageRevision
                    source_path = $managerState.UsageSource
                    title = Get-CodexUsageWindowTitle
                }
                dashboard = [ordered]@{ state = $dashboard.State; root = $dashboard.Root; port = 3000 }
                event_counters = $eventCounters
                scheduled_task_count = $scheduled.Count
            }
        }

        function Handle-ManagerCommand {
            param($Request)
            switch ([string]$Request.action) {
                'status' { return Get-ManagerStatus }
                'register' {
                    $key = [string]$Request.launcher_key
                    if ([string]::IsNullOrWhiteSpace($key) -or [int]$Request.port -le 0) {
                        return [ordered]@{ ok=$false; error='launcher_key and port are required' }
                    }
                    if ($instances.ContainsKey($key)) { Remove-ManagerInstance -Key $key }
                    $instance = [pscustomobject]@{
                        Key = $key
                        Port = [int]$Request.port
                        UserDataDirectory = [string]$Request.user_data_dir
                        RegisteredAt = [DateTimeOffset]::UtcNow
                        StartupDeadline = [DateTime]::UtcNow.AddSeconds(30)
                        ReconnectDeadline = [DateTime]::UtcNow.AddSeconds(30)
                        CdpAttempt = 0
                        CdpConnected = $false
                        CdpStarting = $false
                        CdpPowerShell = $null
                        CdpCancellation = $null
                        CdpAsync = $null
                        HasSeenProcess = $false
                        HasSeenTarget = $false
                        HasSeenWindow = $false
                        SeenProcessIds = [hashtable]::Synchronized(@{})
                        InjectedTargetIds = [hashtable]::Synchronized(@{})
                        KnownWindowHandles = [hashtable]::Synchronized(@{})
                        PrimaryWindowHandles = [hashtable]::Synchronized(@{})
                        WindowProjectNames = [hashtable]::Synchronized(@{})
                        KnownTargetUrls = [hashtable]::Synchronized(@{})
                        ProjectWindowOrder = @()
                        Payload = $null
                        LastRefresh = $null
                        RefreshPowerShell = $null
                        RefreshAsync = $null
                        RefreshRunning = $false
                        RefreshPending = $false
                    }
                    $instances[$key] = $instance
                    Remove-ManagerTask -Key 'manager-idle'
                    Start-CdpWorker -Instance $instance
                    Set-ManagerTask -Key ("refresh:$key") -DelayMilliseconds 100 -Kind 'refresh' -Data $key
                    Set-ManagerTask -Key ("startup:$key") -DelayMilliseconds 30000 -Kind 'close-check' -Data $key
                    Start-ManagerDashboard
                    Add-EventCount 'instance_registered'
                    Write-ManagerLog -Event 'instance-registered' -Fields @{
                        launcher_key=$key
                        port=$instance.Port
                        user_data_dir=$instance.UserDataDirectory
                    }
                    return Get-ManagerStatus
                }
                'unregister' {
                    Remove-ManagerInstance -Key ([string]$Request.launcher_key)
                    return Get-ManagerStatus
                }
                default { return [ordered]@{ ok=$false; error='unknown action' } }
            }
        }

        function Register-ManagerEvents {
            $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
            if (Test-Path -LiteralPath $sessionsRoot -PathType Container) {
                $watcher = [IO.FileSystemWatcher]::new($sessionsRoot, '*.jsonl')
                $watcher.IncludeSubdirectories = $true
                $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
                $watcher.EnableRaisingEvents = $true
                [void]$eventSources.Add($watcher)
                $fileAction = {
                    $state = $Event.MessageData
                    $path = [string]$Event.SourceEventArgs.FullPath
                    [void]$state.Queue.Enqueue([pscustomobject]@{ kind='session-file'; path=$path })
                    [void]$state.Signal.Set()
                }
                foreach ($eventName in @('Changed','Created','Renamed')) {
                    [void]$eventRegistrations.Add((Register-ObjectEvent -InputObject $watcher -EventName $eventName -MessageData $shared -Action $fileAction))
                }
            }

            foreach ($eventType in @('start','stop')) {
                $traceClass = if ($eventType -eq 'start') { 'Win32_ProcessStartTrace' } else { 'Win32_ProcessStopTrace' }
                $query = "SELECT * FROM $traceClass WHERE ProcessName = 'ChatGPT.exe' OR ProcessName = 'Codex.exe' OR ProcessName = 'powershell.exe'"
                $processAction = {
                    $state = $Event.MessageData
                    $record = $Event.SourceEventArgs.NewEvent
                    $process = if ($record.TargetInstance) { $record.TargetInstance } else { $record }
                    $traceClass = if ([string]$record.__CLASS -eq '__InstanceCreationEvent') { 'Win32_ProcessStartTrace' } elseif ([string]$record.__CLASS -eq '__InstanceDeletionEvent') { 'Win32_ProcessStopTrace' } else { [string]$record.__CLASS }
                    [void]$state.Queue.Enqueue([pscustomobject]@{
                        kind='process-event'
                        trace_class=$traceClass
                        process_name=if ($process.ProcessName) { [string]$process.ProcessName } else { [string]$process.Name }
                        process_id=[int]$process.ProcessID
                    })
                    [void]$state.Signal.Set()
                }
                try {
                    $source = [Management.ManagementEventWatcher]::new([Management.WqlEventQuery]::new($query))
                    $registration = Register-ObjectEvent -InputObject $source -EventName EventArrived -MessageData $shared -Action $processAction -ErrorAction Stop
                } catch [Management.ManagementException] {
                    try { if ($source) { $source.Dispose() } } catch { }
                    Write-ManagerLog -Event 'process-trace-unavailable' -Fields @{ fallback='persistent-cdp-lifecycle' }
                    continue
                }
                [void]$eventSources.Add($source)
                [void]$eventRegistrations.Add($registration)
            }
        }

        function Handle-ManagerEvent {
            param($Message)
            Add-EventCount ([string]$Message.kind)
            switch ([string]$Message.kind) {
                'session-file' {
                    if (-not $script:ManagerChangedPaths) { $script:ManagerChangedPaths = @{} }
                    if ($Message.path) { $script:ManagerChangedPaths[[string]$Message.path] = $true }
                    Set-ManagerTask -Key 'usage-debounce' -DelayMilliseconds 150 -Kind 'usage-refresh' -Data $null
                    if ($dashboard.State -eq 'external-transition') {
                        Set-ManagerTask -Key 'dashboard-retry' -DelayMilliseconds 250 -Kind 'dashboard-start' -Data $null
                    }
                }
                'process-event' {
                    Write-ManagerLog -Event 'process-event' -Fields @{
                        trace_class=[string]$Message.trace_class
                        process_name=[string]$Message.process_name
                        process_id=[int]$Message.process_id
                    }
                    if ([string]$Message.process_name -ieq 'powershell.exe') {
                        if ($dashboard.State -eq 'external-transition') {
                            Set-ManagerTask -Key 'dashboard-retry' -DelayMilliseconds 250 -Kind 'dashboard-start' -Data $null
                        }
                        break
                    }
                    foreach ($instance in @($instances.Values)) {
                        if ($Message.trace_class -eq 'Win32_ProcessStartTrace') {
                            $instance.ReconnectDeadline = [DateTime]::UtcNow.AddSeconds(30)
                            if (-not $instance.CdpConnected) { Set-ManagerTask -Key ("cdp-retry:$($instance.Key)") -DelayMilliseconds 100 -Kind 'cdp-retry' -Data $instance.Key }
                            Set-ManagerTask -Key ("refresh:$($instance.Key)") -DelayMilliseconds 100 -Kind 'refresh' -Data $instance.Key
                        }
                    }
                }
                'cdp-connected' {
                    Write-ManagerLog -Event 'cdp-connected' -Fields @{ launcher_key=[string]$Message.launcher_key; port=[int]$Message.port }
                    $key = [string]$Message.launcher_key
                    if ($instances.ContainsKey($key)) {
                        $instances[$key].CdpConnected = $true
                        $instances[$key].CdpStarting = $false
                        $instances[$key].CdpAttempt = 0
                        Set-ManagerTask -Key ("refresh:$key") -DelayMilliseconds 0 -Kind 'refresh' -Data $key
                    }
                }
                'cdp-disconnected' {
                    Write-ManagerLog -Event 'cdp-disconnected' -Fields @{
                        launcher_key=[string]$Message.launcher_key
                        reason=[string]$Message.reason
                        error=[string]$Message.error
                    }
                    $key = [string]$Message.launcher_key
                    if ($instances.ContainsKey($key)) {
                        $instance = $instances[$key]
                        $instance.CdpConnected = $false
                        $instance.CdpStarting = $false
                        $instance.ReconnectDeadline = [DateTime]::UtcNow.AddSeconds(30)
                        Set-ManagerTask -Key ("cdp-retry:$key") -DelayMilliseconds 100 -Kind 'cdp-retry' -Data $key
                    }
                }
                'cdp-inspector-detached' {
                    Write-ManagerLog -Event 'cdp-inspector-detached' -Fields @{
                        launcher_key=[string]$Message.launcher_key
                        reason=[string]$Message.reason
                        error=[string]$Message.error
                    }
                }
                'native-window-event' {
                    $processId = [int]$Message.ProcessId
                    $windowHandle = [int64]$Message.WindowHandle
                    $eventType = [int]$Message.EventType
                    $objectId = [int]$Message.ObjectId
                    $childId = [int]$Message.ChildId
                    $eventName = switch ($eventType) {
                        32769 { 'EVENT_OBJECT_DESTROY' }
                        32770 { 'EVENT_OBJECT_SHOW' }
                        32771 { 'EVENT_OBJECT_HIDE' }
                        default { 'EVENT_OBJECT_UNKNOWN' }
                    }
                    foreach ($instance in @($instances.Values)) {
                        if ($instance.SeenProcessIds.ContainsKey([string]$processId)) {
                            Write-ManagerLog -Event 'native-window-event' -Fields @{
                                process_id=$processId
                                window_handle=$windowHandle
                                event_type=$eventType
                                event_name=$eventName
                                object_id=$objectId
                                child_id=$childId
                                launcher_key=$instance.Key
                            }
                            Set-ManagerTask -Key ("close:$($instance.Key)") -DelayMilliseconds 250 -Kind 'close-check' -Data $instance.Key
                        }
                    }
                }
                'cdp-target' {
                    $key = [string]$Message.launcher_key
                    if (-not $instances.ContainsKey($key)) { return }
                    $instance = $instances[$key]
                    $method = [string]$Message.method
                    Write-ManagerLog -Event 'cdp-target' -Fields @{
                        launcher_key=$key
                        method=$method
                        target_id=[string]$Message.target_id
                        target_type=[string]$Message.target_type
                        target_url=[string]$Message.target_url
                    }
                    if ($method -eq 'Target.targetDestroyed') {
                        $targetId = [string]$Message.params.targetId
                        if ($targetId) {
                            $instance.KnownTargetUrls.Remove($targetId)
                            $instance.InjectedTargetIds.Remove($targetId)
                        }
                        return
                    }
                    $targetInfo = $Message.params.targetInfo
                    if (-not $targetInfo -or [string]$targetInfo.type -ne 'page' -or [string]$targetInfo.url -notlike 'app://*') { return }
                    $targetId = [string]$targetInfo.targetId
                    $targetUrl = [string]$targetInfo.url
                    if ($method -eq 'Target.targetInfoChanged' -and $targetId -and $instance.KnownTargetUrls.ContainsKey($targetId) -and [string]$instance.KnownTargetUrls[$targetId] -eq $targetUrl) {
                        return
                    }
                    if ($targetId) { $instance.KnownTargetUrls[$targetId] = $targetUrl }
                    Set-ManagerTask -Key ("refresh:$key") -DelayMilliseconds 0 -Kind 'refresh' -Data $key
                    foreach ($delay in @(100,250,500,1000)) {
                        Set-ManagerTask -Key ("settle:${key}:$delay") -DelayMilliseconds $delay -Kind 'refresh' -Data $key
                    }
                }
                'refresh-complete' {
                    $key = [string]$Message.launcher_key
                    if ($instances.ContainsKey($key)) {
                        $instance = $instances[$key]
                        $pending = [bool]$instance.RefreshPending
                        try { if ($instance.RefreshPowerShell -and $instance.RefreshAsync) { $instance.RefreshPowerShell.EndInvoke($instance.RefreshAsync) | Out-Null } } catch { }
                        Stop-RefreshWorker -Instance $instance
                        Add-EventCount 'instance_refresh'
                        if ($Message.error) {
                            Write-ManagerLog -Event 'refresh-error' -Fields @{ launcher_key=$key; error=[string]$Message.error }
                        }
                        if ($pending) { Set-ManagerTask -Key ("refresh:$key") -DelayMilliseconds 0 -Kind 'refresh' -Data $key }
                    }
                }
            }
        }

        function Invoke-ManagerTask {
            param($Task)
            switch ($Task.Kind) {
                'usage-refresh' {
                    $paths = if ($script:ManagerChangedPaths) { @($script:ManagerChangedPaths.Keys) } else { @() }
                    $script:ManagerChangedPaths = @{}
                    Refresh-GlobalUsage -Paths $paths
                }
                'usage-boundary' {
                    foreach ($instance in @($instances.Values)) { Refresh-ManagerInstance -Instance $instance }
                    Schedule-UsageBoundary
                }
                'refresh' { if ($instances.ContainsKey([string]$Task.Data)) { Refresh-ManagerInstance -Instance $instances[[string]$Task.Data] } }
                'close-check' { if ($instances.ContainsKey([string]$Task.Data)) { Test-ManagerInstanceClosed -Instance $instances[[string]$Task.Data] } }
                'cdp-retry' {
                    $key = [string]$Task.Data
                    if (-not $instances.ContainsKey($key)) { break }
                    $instance = $instances[$key]
                    if ($instance.CdpConnected) { break }
                    if ($instance.CdpStarting -and $instance.CdpAsync -and -not $instance.CdpAsync.IsCompleted) {
                        Set-ManagerTask -Key ("cdp-retry:$key") -DelayMilliseconds 250 -Kind 'cdp-retry' -Data $key
                        break
                    }
                    if ([DateTime]::UtcNow -gt $instance.ReconnectDeadline) {
                        Set-ManagerTask -Key ("close:$key") -DelayMilliseconds 0 -Kind 'close-check' -Data $key
                        break
                    }
                    Start-CdpWorker -Instance $instance
                    $delays = @(100,250,500,1000,2000,5000)
                    $delayIndex = [Math]::Min([Math]::Max(0, $instance.CdpAttempt - 1), $delays.Count - 1)
                    Set-ManagerTask -Key ("cdp-retry:$key") -DelayMilliseconds $delays[$delayIndex] -Kind 'cdp-retry' -Data $key
                }
                'session-alert' { Publish-PrematureAlert -Path ([string]$Task.Data) }
                'dashboard-start' { Start-ManagerDashboard }
                'dashboard-check' {
                    if ($dashboard.PowerShell -and -not $dashboard.Async.IsCompleted -and -not (Test-TcpPortAvailable -Port 3000)) {
                        $dashboard.State = 'owned'
                    } elseif (-not (Test-TcpPortAvailable -Port 3000)) {
                        $dashboard.State = 'external-transition'
                    } else {
                        $dashboard.State = 'stopped'
                    }
                }
                'manager-idle' { if ($instances.Count -eq 0) { $managerState.Stopping = $true } }
            }
        }

        Write-ManagerLog -Event 'manager-start' -Fields @{
            runtime_root=$runtimeRoot
            runtime_version=$runtimeVersion
            runtime_fingerprint=$runtimeFingerprint
        }
        Register-ManagerEvents
        try {
            $nativeWindowWatcher = Start-CodexNativeWindowEventWatcher -Queue $shared.Queue -Signal $shared.Signal
            [void]$eventSources.Add($nativeWindowWatcher)
            Write-ManagerLog -Event 'native-window-hook-started' -Fields @{ hook_events='EVENT_OBJECT_DESTROY,EVENT_OBJECT_SHOW,EVENT_OBJECT_HIDE' }
        } catch {
            Write-ManagerLog -Event 'native-window-hook-error' -Fields @{ error=$_.Exception.ToString() }
        }
        Start-ManagerDashboard
        Set-ManagerTask -Key 'usage-startup' -DelayMilliseconds 500 -Kind 'usage-refresh' -Data $null
        Set-ManagerTask -Key 'manager-idle' -DelayMilliseconds 10000 -Kind 'manager-idle' -Data $null

        $pipe = New-CodexPlusManagerPipeServer -Identity $identity
        $pipeWait = $pipe.BeginWaitForConnection($null, $null)
        while (-not $managerState.Stopping) {
            $now = [DateTime]::UtcNow
            $dueTasks = @($scheduled.Values | Where-Object { $_.Due -le $now } | Sort-Object Due)
            foreach ($task in $dueTasks) {
                if ($scheduled.ContainsKey($task.Key) -and $scheduled[$task.Key] -eq $task) { $scheduled.Remove($task.Key) }
                try {
                    Invoke-ManagerTask -Task $task
                } catch {
                    Write-ManagerLog -Event 'scheduled-task-error' -Fields @{ kind=$task.Kind; error=$_.Exception.Message }
                }
            }
            if ($managerState.Stopping) { break }

            $message = $null
            while ($shared.Queue.TryDequeue([ref]$message)) {
                try {
                    Handle-ManagerEvent -Message $message
                } catch {
                    Write-ManagerLog -Event 'event-handler-error' -Fields @{ kind=$message.kind; error=$_.Exception.Message }
                }
            }

            $next = @($scheduled.Values | Sort-Object Due | Select-Object -First 1)
            $timeout = if ($next.Count -eq 0) { -1 } else { [Math]::Max(0, [int][Math]::Min([int]::MaxValue, ($next[0].Due - [DateTime]::UtcNow).TotalMilliseconds)) }
            $waitResult = [Threading.WaitHandle]::WaitAny(@($shared.Signal, $pipeWait.AsyncWaitHandle), $timeout)
            if ($waitResult -eq 1) {
                try {
                    $pipe.EndWaitForConnection($pipeWait)
                    $reader = [IO.StreamReader]::new($pipe)
                    $writer = [IO.StreamWriter]::new($pipe)
                    $writer.AutoFlush = $true
                    try {
                        $requestLine = $reader.ReadLine()
                        $request = $requestLine | ConvertFrom-Json
                        $response = Handle-ManagerCommand -Request $request
                    } catch {
                        $response = [ordered]@{ ok=$false; error=$_.Exception.Message }
                    }
                    $writer.WriteLine(($response | ConvertTo-Json -Depth 10 -Compress))
                } catch {
                    Write-ManagerLog -Event 'pipe-request-error' -Fields @{ error=$_.Exception.Message }
                } finally {
                    try { $pipe.Dispose() } catch { }
                }
                $pipe = New-CodexPlusManagerPipeServer -Identity $identity
                $pipeWait = $pipe.BeginWaitForConnection($null, $null)
            }
        }
    } catch {
        try {
            $fatalEntry = [ordered]@{
                timestamp = [DateTimeOffset]::UtcNow.ToString('o')
                event = 'manager-fatal'
                manager_pid = $PID
                error = $_.Exception.ToString()
            }
            Add-Content -LiteralPath (Get-CodexPlusManagerLogPath) -Encoding UTF8 -Value ($fatalEntry | ConvertTo-Json -Depth 12 -Compress)
        } catch { }
        throw
    } finally {
        try { if ($pipe) { $pipe.Dispose() } } catch { }
        try {
            foreach ($instance in @($instances.Values)) {
                Stop-RefreshWorker -Instance $instance
                Stop-CdpWorker -Instance $instance
            }
        } catch { }
        try {
            foreach ($registration in @($eventRegistrations)) {
                Unregister-Event -SourceIdentifier $registration.Name -ErrorAction SilentlyContinue
                Remove-Job -Id $registration.Id -Force -ErrorAction SilentlyContinue
            }
        } catch { }
        try {
            foreach ($source in @($eventSources)) {
                if ($source -is [CodexPlusWindowEventWatcher]) {
                    try { $source.Dispose() } catch { }
                    continue
                }
                try { $source.Stop() } catch { }
                try { $source.EnableRaisingEvents = $false } catch { }
                try { $source.Dispose() } catch { }
            }
        } catch { }
        try {
            if ($dashboard -and $dashboard.PowerShell) {
                $dashboard.PowerShell.Stop()
                $dashboard.PowerShell.Dispose()
            }
        } catch { }
        try { if ($shared -and $shared.Signal) { $shared.Signal.Dispose() } } catch { }
        try { if ($ownsMutex) { $mutex.ReleaseMutex() } } catch { }
        try { $mutex.Dispose() } catch { }
        try { Write-ManagerLog -Event 'manager-stop' } catch { }
    }
}
