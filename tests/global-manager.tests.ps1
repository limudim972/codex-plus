$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$managerSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\global-manager.ps1')
$launcherSource = New-CodexRtlLauncherScriptContent -PatchScriptPath (Join-Path (Get-CodexRtlRuntimeRoot) 'patch.ps1')
$dashboardSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\dashboard-server.ps1')
$launchSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\launch.ps1')

Assert-True ($managerSource.Contains('[hashtable]::Synchronized')) 'Manager should share event state explicitly across PowerShell event scopes.'
Assert-True ($managerSource.Contains('-MessageData $shared')) 'Manager event subscriptions should use MessageData.'
Assert-True ($managerSource.Contains('[Collections.Concurrent.ConcurrentQueue[object]]')) 'Manager should serialize callback work through a concurrent queue.'
Assert-True ($managerSource.Contains('[Threading.AutoResetEvent]')) 'Manager should wake its coordinator through an event handle.'
Assert-True ($managerSource.Contains('[Threading.WaitHandle]::WaitAny')) 'Manager should block instead of polling.'
Assert-True ($managerSource.Contains('[Threading.WaitHandle]::WaitAny(@($pipeWait.AsyncWaitHandle, $shared.Signal), $timeout)')) 'Manager commands should take priority over noisy native window events.'
Assert-True ($managerSource.Contains('$processedEventCount -lt 256')) 'Manager event draining should be bounded so pipe commands remain responsive.'
Assert-True ($managerSource.Contains('Target.setDiscoverTargets')) 'Manager should subscribe to browser-level CDP target events.'
Assert-True ($managerSource.Contains('[string]$message.method -eq ''Inspector.detached''')) 'Manager should observe CDP inspector detach events.'
Assert-True ($managerSource.Contains("`$disconnectReason = 'remote-close'")) 'CDP worker should preserve a clean remote websocket close reason.'
Assert-True ($managerSource.Contains('$disconnectPublished')) 'CDP worker should publish a disconnect event when the websocket closes cleanly.'
Assert-True ($managerSource.Contains("Write-ManagerLog -Event 'cdp-target'")) 'Manager should log each CDP target lifecycle event.'
Assert-True ($managerSource.Contains("Write-ManagerLog -Event 'close-check'")) 'Manager should log close-check snapshots and decisions.'
Assert-True ($managerSource.Contains("Set-Content -LiteralPath $logPath")) 'Manager should start each diagnostic session with a fresh log.'
Assert-True ($managerSource.Contains("function Get-CodexPlusRuntimeVersion")) 'Runtime should expose an explicit diagnostic version.'
Assert-True ($managerSource.Contains('runtime_version=$runtimeVersion')) 'Manager startup log should expose the runtime version.'
Assert-True ($managerSource.Contains('runtime_fingerprint=$runtimeFingerprint')) 'Manager startup log should expose the runtime fingerprint.'
Assert-True ($launchSource.Contains('SetWinEventHook')) 'Runtime should expose the native Windows event hook.'
Assert-True ($launchSource.Contains('EVENT_OBJECT_DESTROY') -or $launchSource.Contains('EventObjectDestroy')) 'Native window monitoring should listen for object destruction.'
Assert-True ($managerSource.Contains("'native-window-event'")) 'Native window events should enter the manager queue.'
Assert-True ($managerSource.Contains("Write-ManagerLog -Event 'native-window-hook-started'")) 'Manager should log native hook startup.'
Assert-True ($managerSource.Contains('Win32_ProcessStartTrace')) 'Manager should subscribe to process lifecycle indications.'
Assert-True (-not $managerSource.Contains('WITHIN 1')) 'Manager should not fall back to intrinsic WMI polling when process trace events are unavailable.'
Assert-True ($managerSource.Contains("fallback='persistent-cdp-lifecycle'")) 'Persistent CDP events should own lifecycle when native process traces are unavailable.'
Assert-True ($managerSource.Contains('''-File'', (''"{0}"'' -f $scriptPath)')) 'Manager bootstrap should quote the installed runtime path, which contains a space.'
Assert-True (-not $managerSource.Contains('PollMilliseconds')) 'Manager should not expose a recurring poll interval.'
Assert-True ($managerSource.Contains('$script:CodexPlusGlobalUsageAuthority = $true')) 'Only the manager should be authoritative for the shared usage cache.'
Assert-True ($managerSource.Contains('FileSystemWatcher can report the write before the token_count')) 'Usage refresh should tolerate an early file notification.'
Assert-True ($managerSource.Contains("Set-ManagerTask -Key 'usage-retry' -DelayMilliseconds 500")) 'Usage refresh should retry after an early file notification.'
Assert-True ($managerSource.Contains('$instance.CdpStarting -and $instance.CdpAsync')) 'Manager should not duplicate an in-flight persistent CDP connection.'
Assert-True ($managerSource.Contains("`$method -eq 'Target.targetInfoChanged'")) 'CDP target-info events should be deduplicated instead of creating a title-refresh feedback loop.'
Assert-True ($managerSource.Contains("Set-ManagerTask -Key 'session-scan' -DelayMilliseconds 30000")) 'Session diagnostics should not block manager startup and renderer registration.'
Assert-True (-not $launcherSource.Contains('-StartCloseWatchdog')) 'Launcher should not create one watchdog per window.'
Assert-True (-not $launcherSource.Contains('dashboard-server.ps1')) 'Launcher should not create one dashboard server per window.'
Assert-True ($dashboardSource.Contains('$listener.GetContext()')) 'Dashboard should block on incoming HTTP requests.'
Assert-True ($launchSource.Contains('$cancellation.CancelAfter([Math]::Max(250, $TimeoutMilliseconds))')) 'One-shot CDP commands should be bounded so one target cannot freeze the global manager.'

$managerProcess = $null
$contractKey = 'codex-plus-manager-contract-test'
try {
    $managerProcess = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$patchScript,'-SkipMain','-StartGlobalManager'
    )
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(7)
    do {
        try {
            $status = Send-CodexPlusManagerCommand -Command @{ action='status' } -ConnectTimeoutMilliseconds 150
            $ready = [bool]$status.ok
        } catch { }
        if (-not $ready) { Start-Sleep -Milliseconds 75 }
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    Assert-True $ready 'Manager pipe should become ready.'
    $initialStatus = $status

    $registration = Send-CodexPlusManagerCommand -Command @{
        action='register'
        launcher_key=$contractKey
        port=29991
        user_data_dir=(Join-Path $env:TEMP 'codex-plus-manager-contract')
    }
    $matchingRegistration = @($registration.instances | Where-Object { $_.launcher_key -eq $contractKey })
    Assert-True ($registration.ok -and $matchingRegistration.Count -eq 1) 'Manager should register one exact instance identity.'
    Assert-True ($registration.instance_count -ge ([int]$initialStatus.instance_count + 1)) 'Manager status should include the new instance without discarding existing instances.'
    Assert-True ($matchingRegistration[0].launcher_key -eq $contractKey) 'Manager status should return the registered launcher key.'

    $unregistered = Send-CodexPlusManagerCommand -Command @{ action='unregister'; launcher_key=$contractKey }
    $matchingAfterUnregister = @($unregistered.instances | Where-Object { $_.launcher_key -eq $contractKey })
    Assert-True ($unregistered.ok -and $matchingAfterUnregister.Count -eq 0) 'Manager should unregister the exact requested identity.'

    if ([int]$initialStatus.instance_count -eq 0) {
        Wait-Process -Id $managerProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
        Assert-True (-not [bool](Get-Process -Id $managerProcess.Id -ErrorAction SilentlyContinue)) 'Manager should exit five seconds after its final managed instance is removed.'
    }
} finally {
    try { Send-CodexPlusManagerCommand -Command @{ action='unregister'; launcher_key=$contractKey } -ConnectTimeoutMilliseconds 100 | Out-Null } catch { }
    if ($managerProcess -and (Get-Process -Id $managerProcess.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $managerProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'global-manager.tests.ps1 passed'
