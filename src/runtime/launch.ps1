function Get-CodexRtlDefaultPort {
    18317
}

function Get-CodexLaunchSplashIcon {
    try {
        Add-Type -AssemblyName System.Drawing

        $installInfo = Get-CodexInstallInfo
        $iconLocation = Get-CodexIconLocation -InstallInfo $installInfo
        if ([string]::IsNullOrWhiteSpace($iconLocation)) {
            return $null
        }

        $iconPath = $iconLocation
        $iconIndex = 0
        if ($iconLocation -match '^(.*),\s*(-?\d+)$') {
            $iconPath = $matches[1]
            $iconIndex = [int]$matches[2]
        }
        $iconPath = $iconPath.Trim().Trim('"')
        if (-not (Test-Path -LiteralPath $iconPath)) {
            return $null
        }

        if ([System.IO.Path]::GetExtension($iconPath).Equals('.ico', [System.StringComparison]::OrdinalIgnoreCase)) {
            $stream = [System.IO.File]::OpenRead($iconPath)
            try {
                return [System.Drawing.Icon]::new($stream)
            } finally {
                $stream.Close()
            }
        }

        if ($iconIndex -eq 0) {
            $associatedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
            if ($associatedIcon) {
                return $associatedIcon
            }
        }

        return [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
    } catch {
        return $null
    }
}

function Get-CodexLaunchSplashIconSource {
    try {
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName WindowsBase
    } catch {
        return $null
    }

    $icon = Get-CodexLaunchSplashIcon
    if (-not $icon) {
        return $null
    }

    try {
        $bitmapSource = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
            $icon.Handle,
            [System.Windows.Int32Rect]::Empty,
            [System.Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight(36, 36)
        )
        $formattedBitmap = [System.Windows.Media.Imaging.FormatConvertedBitmap]::new()
        $formattedBitmap.BeginInit()
        $formattedBitmap.Source = $bitmapSource
        $formattedBitmap.DestinationFormat = [System.Windows.Media.PixelFormats]::Bgra32
        $formattedBitmap.EndInit()

        $width = $formattedBitmap.PixelWidth
        $height = $formattedBitmap.PixelHeight
        $stride = $width * 4
        $pixels = New-Object byte[] ($stride * $height)
        $formattedBitmap.CopyPixels($pixels, $stride, 0)

        for ($i = 0; $i -lt $pixels.Length; $i += 4) {
            $alpha = $pixels[$i + 3]
            if ($alpha -gt 0) {
                $pixels[$i] = 255
                $pixels[$i + 1] = 255
                $pixels[$i + 2] = 255
            }
        }

        $whiteBitmap = [System.Windows.Media.Imaging.BitmapSource]::Create(
            $width,
            $height,
            $formattedBitmap.DpiX,
            $formattedBitmap.DpiY,
            [System.Windows.Media.PixelFormats]::Bgra32,
            $null,
            $pixels,
            $stride
        )
        $whiteBitmap.Freeze()
        return $whiteBitmap
    } catch {
        return $null
    } finally {
        $icon.Dispose()
    }
}

function Show-CodexLaunchSplash {
    param(
        [AllowEmptyString()][string]$LauncherKey,
        [int]$PreferredPort = 0,
        [int]$TimeoutSeconds = 20
    )

    try {
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName WindowsBase
    } catch {
        return $false
    }

    $window = [System.Windows.Window]::new()
    $window.Title = 'Codex Plus'
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar = $false
    $window.Topmost = $true
    $window.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $window.ShowActivated = $true

    $stack = [System.Windows.Controls.StackPanel]::new()
    $stack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $stack.Margin = [System.Windows.Thickness]::new(20, 18, 20, 18)
    $stack.SnapsToDevicePixels = $true

    $image = [System.Windows.Controls.Image]::new()
    $image.Width = 36
    $image.Height = 36
    $image.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $image.Source = Get-CodexLaunchSplashIconSource

    $rotation = [System.Windows.Media.RotateTransform]::new()
    $image.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
    $image.RenderTransform = $rotation
    $spin = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 360, [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.2)))
    $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $rotation.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)

    $text = [System.Windows.Controls.TextBlock]::new()
    $text.Text = 'Plus'
    $text.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI Semibold')
    $text.FontSize = 28
    $text.FontWeight = [System.Windows.FontWeights]::SemiBold
    $text.Foreground = [System.Windows.Media.Brushes]::White
    $text.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $text.TextOptions_TextFormattingMode = [System.Windows.Media.TextFormattingMode]::Display
    $text.TextOptions_TextRenderingMode = [System.Windows.Media.TextRenderingMode]::ClearType

    $stack.Children.Add($image) | Out-Null
    $stack.Children.Add($text) | Out-Null
    $window.Content = $stack
    $window.Show()
    $window.Activate() | Out-Null

    $dispatcherFrame = [System.Windows.Threading.DispatcherFrame]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($window.IsVisible -and ([DateTime]::UtcNow -lt $deadline)) {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [action]{}
        )

        $visibleProcessCount = 0
        try {
            $state = Read-CodexRtlState
            $statePreferredPort = if ($state -and $state.Port) { [int]$state.Port } else { 0 }
            $port = if ($PreferredPort -gt 0) {
                $PreferredPort
            } else {
                Get-CodexRtlLaunchPort -PreferredPort $statePreferredPort -LauncherKey $LauncherKey
            }
            if ($port -gt 0) {
                $visibleProcessCount = Get-CodexVisibleProcessCount -Port $port -LauncherKey $LauncherKey
            }
        } catch {
        }

        if ($visibleProcessCount -gt 0) {
            break
        }

        Start-Sleep -Milliseconds 150
    }

    try {
        $window.Close()
    } catch {
    }

    return $true
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
        [int]$DashboardProcessId,
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

        try {
            foreach ($windowHandle in @(Get-CodexVisibleWindowHandles -ProcessId $process.ProcessId)) {
                $windowTitle = Get-CodexNativeWindowTitle -WindowHandle $windowHandle
                $titleMatch = [regex]::Match([string]$windowTitle, '^(\d+)\..+$')
                if ($titleMatch.Success) {
                    $windowOrdinal = [int]$titleMatch.Groups[1].Value
                    if ($windowOrdinal -gt $maxOrdinal) {
                        $maxOrdinal = $windowOrdinal
                    }
                }
            }
        } catch {
        }
    }

    return [Math]::Max($managedBrowserProcesses.Count, $maxOrdinal) + 1
}

function Format-CodexUsageWindowTitle {
    param(
        [Parameter(Mandatory)][double]$UsedPercent,
        [Parameter(Mandatory)][long]$ResetsAt,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    $resetAt = [DateTimeOffset]::FromUnixTimeSeconds($ResetsAt)
    $remaining = $resetAt - $Now
    if ($remaining.TotalSeconds -le 0) {
        return ('Plus Codex - {0}% used, resets now' -f $UsedPercent.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture))
    }

    if ($remaining.TotalDays -ge 1) {
        $value = [Math]::Max(1, [int][Math]::Ceiling($remaining.TotalDays))
        $unit = if ($value -eq 1) { 'day' } else { 'days' }
    } elseif ($remaining.TotalHours -ge 1) {
        $value = [Math]::Max(1, [int][Math]::Ceiling($remaining.TotalHours))
        $unit = if ($value -eq 1) { 'hour' } else { 'hours' }
    } else {
        $value = [Math]::Max(1, [int][Math]::Ceiling($remaining.TotalMinutes))
        $unit = if ($value -eq 1) { 'minute' } else { 'minutes' }
    }

    return ('Plus Codex - {0}% used, resets in {1} {2}' -f
        $UsedPercent.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture),
        $value,
        $unit)
}

$script:CodexPlusRateLimitTitleCache = $null
$script:CodexPlusUsageChangedPaths = @()
$script:CodexPlusUsageRefreshRequested = $false
$script:CodexPlusUsageWatcher = $null
$script:CodexPlusUsageWatcherEvents = @()
$script:CodexPlusPrematureAlerted = @{}
$script:CodexPlusPrematurePending = [hashtable]::Synchronized(@{})
$script:CodexPlusChangedSessionPaths = [hashtable]::Synchronized(@{})

function Get-CodexSessionDisplayName {
    param([Parameter(Mandatory)][string]$SessionId)
    $indexPath = Join-Path $env:USERPROFILE '.codex\session_index.jsonl'
    if (-not (Test-Path -LiteralPath $indexPath)) { return $SessionId }
    foreach ($line in @(Get-Content -LiteralPath $indexPath -ErrorAction SilentlyContinue)) {
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ([string]$entry.id -eq $SessionId -and $entry.thread_name) { return [string]$entry.thread_name }
    }
    return $SessionId
}

function Update-CodexPrematureSessionState {
    param([Parameter(Mandatory)][string[]]$Paths)
    $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container)) { return @() }
    foreach ($path in @($Paths | Select-Object -Unique)) {
        if (-not $path.StartsWith($sessionsRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:CodexPlusPrematurePending.Remove($path); continue }
        $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $file -or $file.Extension -ne '.jsonl') { continue }
        $last = @(Get-Content -LiteralPath $file.FullName -Tail 4 -ErrorAction SilentlyContinue | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ } | Select-Object -Last 1)
        if ($last.Count -eq 0) { continue }
        $payload = $last[0].payload
        if (-not $payload) { continue }
        if ($payload.type -in @('task_complete', 'turn_aborted')) {
            $script:CodexPlusPrematurePending.Remove($path)
            continue
        }
        $project = if ($payload.cwd) { Split-Path -Leaf ([string]$payload.cwd) } else { 'unknown' }
        $sessionId = if ($file.BaseName -match '(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$') { $Matches.id } else { $file.BaseName }
        $script:CodexPlusPrematurePending[$path] = [pscustomobject]@{ name = Get-CodexSessionDisplayName -SessionId $sessionId; session = $sessionId; turn = if ($payload.turn_id) { [string]$payload.turn_id } else { '' }; project = $project; path = $file.FullName; last_type = [string]$payload.type; last_activity = $file.LastWriteTimeUtc }
    }
}

function Get-CodexPrematureSessionAlerts {
    $now = [DateTime]::UtcNow
    $alerts = @()
    foreach ($path in @($script:CodexPlusPrematurePending.Keys)) {
        $pending = $script:CodexPlusPrematurePending[$path]
        if (-not $pending) { continue }
        $ageSeconds = [int]($now - $pending.last_activity).TotalSeconds
        if ($ageSeconds -lt 120) { continue }
        $key = "$path|$($pending.last_activity.Ticks)"
        if ($script:CodexPlusPrematureAlerted.ContainsKey($key)) { continue }
        $script:CodexPlusPrematureAlerted[$key] = $true
        $pending | Add-Member -NotePropertyName age_seconds -NotePropertyValue $ageSeconds -Force
        $alerts += $pending
    }
    return $alerts
}

function Show-CodexPrematureSessionAlert {
    param([Parameter(Mandatory)]$Alert)
    $message = @"
Codex session may have stopped early.

Project: $($Alert.project)
Name: $($Alert.name)
Session: $($Alert.session)
Path: $($Alert.path)
Last event: $($Alert.last_type)
Age: $($Alert.age_seconds) seconds
Triggered by: No new session row was written for at least 120 seconds, and the last row was not task_complete or turn_aborted.
"@
    $popupScript = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object Windows.Forms.Form
$form.Text = 'Codex Plus session monitor'
$form.Size = New-Object Drawing.Size(680, 330)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.MinimizeBox = $false
$form.MaximizeBox = $false
$form.FormBorderStyle = 'FixedDialog'
$label = New-Object Windows.Forms.Label
$label.Text = __CODEX_MESSAGE__
$label.Dock = 'Fill'
$label.Padding = New-Object Windows.Forms.Padding(18)
$label.Font = New-Object Drawing.Font('Segoe UI', 10)
$label.AutoSize = $false
$label.Height = 240
$label.Anchor = 'Top,Left,Right'
$form.Controls.Add($label)
$button = New-Object Windows.Forms.Button
$button.Text = 'Dismiss'
$button.Width = 100
$button.Height = 32
$button.Left = 550
$button.Top = 255
$button.Add_Click({ $form.Close() })
$form.Controls.Add($button)
$form.AcceptButton = $button
[void]$form.ShowDialog()
'@
    $popupScript = $popupScript.Replace('__CODEX_MESSAGE__', ($message | ConvertTo-Json -Compress))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($popupScript))
    try { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null } catch { }
    $literal = (@{ name=$Alert.name; session=$Alert.session; turn=$Alert.turn; project=$Alert.project; path=$Alert.path; last_type=$Alert.last_type; age_seconds=$Alert.age_seconds; trigger='A new turn started after monitor startup and remained without task_complete or turn_aborted for at least 120 seconds.' } | ConvertTo-Json -Compress).Replace('\\', '\\\\').Replace('`"', '\\`"')
    $script:CodexPlusPrematureAlertPayload = $literal
}

function Start-CodexUsageSessionWatcher {
    if ($script:CodexPlusUsageWatcher) { return }
    $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container)) { return }
    $watcher = [System.IO.FileSystemWatcher]::new($sessionsRoot, '*.jsonl')
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, Size'
    $watcher.EnableRaisingEvents = $true
    $action = {
        $script:CodexPlusUsageRefreshRequested = $true
        $changedPath = [string]$Event.SourceEventArgs.FullPath
        if ($changedPath) { $script:CodexPlusChangedSessionPaths[$changedPath] = $true }
    }
    $script:CodexPlusUsageWatcherEvents = @(
        Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
        Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
        Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action
    )
    $script:CodexPlusUsageWatcher = $watcher
}

function Stop-CodexUsageSessionWatcher {
    foreach ($event in @($script:CodexPlusUsageWatcherEvents)) {
        Unregister-Event -SourceIdentifier $event.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $event.Id -Force -ErrorAction SilentlyContinue
    }
    $script:CodexPlusUsageWatcherEvents = @()
    if ($script:CodexPlusUsageWatcher) {
        $script:CodexPlusUsageWatcher.EnableRaisingEvents = $false
        $script:CodexPlusUsageWatcher.Dispose()
        $script:CodexPlusUsageWatcher = $null
    }
}

function Get-CodexLatestRateLimitSummary {
    param([string[]]$Paths = @())
    $sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
    $latest = if (@($Paths).Count -gt 0) {
        @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object { Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue } |
            Where-Object { $_.Extension -eq '.jsonl' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    } else {
        Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $latest) { return $null }

    $primary = $null
    # Usage refreshes inspect only the newest changed session and its last
    # ten JSONL records. Keep the previous usage cache when no token_count is
    # present in that bounded window.
    foreach ($line in Get-Content -LiteralPath $latest.FullName -Tail 10 -ErrorAction SilentlyContinue) {
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        $payload = if ($obj.payload -is [pscustomobject]) { $obj.payload } elseif ($obj.event_msg -is [pscustomobject]) { $obj.event_msg } else { $null }
        if ($payload -and $payload.rate_limits -and $payload.rate_limits.primary) {
            $primary = $payload.rate_limits.primary
        }
    }
    return $primary
}

function Get-CodexUsageWindowTitle {
    $now = [DateTimeOffset]::UtcNow
    $cache = $script:CodexPlusRateLimitTitleCache
    if ($cache -and ($now - $cache.fetched_at).TotalSeconds -lt 30) {
        if ($null -ne $cache.used_percent -and $null -ne $cache.resets_at) {
            return Format-CodexUsageWindowTitle -UsedPercent ([double]$cache.used_percent) -ResetsAt ([long]$cache.resets_at) -Now $now
        }
        return 'Plus Codex'
    }

    try {
        $changedPaths = @($script:CodexPlusUsageChangedPaths)
        $script:CodexPlusUsageChangedPaths = @()
        $primary = Get-CodexLatestRateLimitSummary -Paths $changedPaths
        $cache = [pscustomobject]@{
            fetched_at = $now
            used_percent = if ($primary) { $primary.used_percent } else { $null }
            resets_at = if ($primary) { $primary.resets_at } else { $null }
        }
        $script:CodexPlusRateLimitTitleCache = $cache
    } catch {
        if (-not $cache) {
            $script:CodexPlusRateLimitTitleCache = [pscustomobject]@{
                fetched_at = $now
                used_percent = $null
                resets_at = $null
            }
            return 'Plus Codex'
        }
        $cache.fetched_at = $now
        $script:CodexPlusRateLimitTitleCache = $cache
    }

    if ($null -ne $cache.used_percent -and $null -ne $cache.resets_at) {
        return Format-CodexUsageWindowTitle -UsedPercent ([double]$cache.used_percent) -ResetsAt ([long]$cache.resets_at) -Now $now
    }
    return 'Plus Codex'
}

function Get-CodexDesiredWindowTitle {
    param([int]$Ordinal = 0, [AllowEmptyString()][string]$ProjectName = '')

    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        if ($Ordinal -gt 0) {
            return "$Ordinal.$ProjectName"
        }
        return $ProjectName
    }

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

function Get-CodexNativeWindowTitle {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)

    if (-not ('CodexPlusNativeWindows' -as [type])) {
        Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CodexPlusNativeWindows {
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    public static IntPtr[] GetVisibleTopLevelWindows(int processId) {
        var handles = new List<IntPtr>();
        EnumWindows((hWnd, lParam) => {
            uint ownerProcessId;
            GetWindowThreadProcessId(hWnd, out ownerProcessId);
            if (ownerProcessId == (uint)processId && IsWindowVisible(hWnd)) {
                handles.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return handles.ToArray();
    }

    public static string GetWindowTitle(IntPtr hWnd) {
        var text = new StringBuilder(512);
        GetWindowText(hWnd, text, text.Capacity);
        return text.ToString();
    }

    public static bool MaximizeWindow(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero || IsZoomed(hWnd)) {
            return false;
        }
        return ShowWindow(hWnd, 3);
    }
}
'@
    }

    return [CodexPlusNativeWindows]::GetWindowTitle($WindowHandle)
}

function Get-CodexVisibleWindowHandles {
    param([Parameter(Mandatory)][int]$ProcessId)

    if (-not ('CodexPlusNativeWindows' -as [type])) {
        Get-CodexNativeWindowTitle -WindowHandle ([IntPtr]::Zero) | Out-Null
    }

    return @([CodexPlusNativeWindows]::GetVisibleTopLevelWindows($ProcessId) | ForEach-Object { $_ })
}

function Set-CodexNativeWindowMaximized {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)

    if ($WindowHandle -eq [IntPtr]::Zero) {
        return $false
    }

    if (-not ('CodexPlusNativeWindows' -as [type])) {
        Get-CodexNativeWindowTitle -WindowHandle ([IntPtr]::Zero) | Out-Null
    }

    return [CodexPlusNativeWindows]::MaximizeWindow($WindowHandle)
}

function Maximize-CodexPlusWindows {
    param(
        [Parameter(Mandatory)][int]$Port,
        [AllowEmptyString()][string]$LauncherKey
    )

    $matchingProcesses = @(
        Get-CodexDesktopProcesses | Where-Object {
            Test-CodexProcessHasRtlDebugPort -Process $_ -Port $Port
        }
    )
    if ($matchingProcesses.Count -eq 0) {
        return $false
    }

    if (-not $script:CodexPlusKnownWindowHandles) {
        $script:CodexPlusKnownWindowHandles = @{}
    }

    $currentWindowHandleKeys = @{}
    $maximized = $false
    foreach ($process in $matchingProcesses) {
        foreach ($windowHandle in @(Get-CodexVisibleWindowHandles -ProcessId $process.ProcessId)) {
            $handleKey = '{0}:{1}' -f $process.ProcessId, [int64]$windowHandle
            $currentWindowHandleKeys[$handleKey] = $true
            if (-not $script:CodexPlusKnownWindowHandles.ContainsKey($handleKey)) {
                $script:CodexPlusKnownWindowHandles[$handleKey] = $true
                if (Set-CodexNativeWindowMaximized -WindowHandle ([IntPtr]$windowHandle)) {
                    $maximized = $true
                }
            }
        }
    }

    foreach ($handleKey in @($script:CodexPlusKnownWindowHandles.Keys)) {
        if (-not $currentWindowHandleKeys.ContainsKey($handleKey)) {
            $script:CodexPlusKnownWindowHandles.Remove($handleKey)
        }
    }

    return $maximized
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
    if (-not $script:CodexPlusPrimaryWindowHandles) {
        $script:CodexPlusPrimaryWindowHandles = @{}
    }
    if (-not $script:CodexPlusWindowProjectNames) {
        $script:CodexPlusWindowProjectNames = @{}
    }
    if (-not $script:CodexPlusProjectWindowOrder) {
        $script:CodexPlusProjectWindowOrder = @()
    }
    $devToolsTargets = @(Get-CodexDevToolsTargets -Port $Port | Where-Object { Test-CodexDevToolsTarget -Target $_ })
    $usageTitle = Get-CodexUsageWindowTitle
    $projectTargetNames = @()
    $projectTargetNamesById = @{}
    foreach ($target in $devToolsTargets) {
        try {
            $usageTitleLiteral = ([string]$usageTitle | ConvertTo-Json -Compress)
            $usagePublish = New-CodexCdpCommand -Id 3 -Method 'Runtime.evaluate' -Params @{
                expression = "window.__CODEX_PLUS_USAGE_WINDOW_TITLE = $usageTitleLiteral; window.dispatchEvent(new Event('codex-plus-usage-updated'));"
                returnByValue = $true
            }
            Invoke-CodexCdpCommand -WebSocketDebuggerUrl $target.webSocketDebuggerUrl -Command $usagePublish | Out-Null
            $probe = New-CodexCdpCommand -Id 1 -Method 'Runtime.evaluate' -Params @{
                expression = "window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.name || ''"
                returnByValue = $true
            }
            $probeJson = @(Invoke-CodexCdpCommand -WebSocketDebuggerUrl $target.webSocketDebuggerUrl -Command $probe |
                Where-Object { $_ -is [string] } |
                Select-Object -Last 1)
            if ($probeJson.Count -eq 0) { continue }
            $probeResult = $probeJson[0] | ConvertFrom-Json
            $projectTargetName = [string]$probeResult.result.result.value
            if (-not [string]::IsNullOrWhiteSpace($projectTargetName)) {
                $projectTargetNames += $projectTargetName.Trim()
                if ($target.id) {
                    $projectTargetNamesById[[string]$target.id] = $projectTargetName.Trim()
                }
            }
        } catch {
        }
    }
    foreach ($process in $matchingProcesses) {
        $processOrdinal = Get-CodexProcessWindowTitleOrdinal -Process $process
        try {
            $liveProcess = Get-Process -Id $process.ProcessId -ErrorAction Stop
            if (-not $script:CodexPlusPrimaryWindowHandles.ContainsKey([string]$process.ProcessId) -and $liveProcess.MainWindowHandle -ne 0) {
                $script:CodexPlusPrimaryWindowHandles[[string]$process.ProcessId] = $liveProcess.MainWindowHandle
            }
            $primaryWindowHandle = if ($script:CodexPlusPrimaryWindowHandles.ContainsKey([string]$process.ProcessId)) {
                [IntPtr]$script:CodexPlusPrimaryWindowHandles[[string]$process.ProcessId]
            } else {
                $liveProcess.MainWindowHandle
            }
            $windowHandles = @(
                Get-CodexVisibleWindowHandles -ProcessId $process.ProcessId |
                    Sort-Object @{ Expression = { if ($_ -eq $primaryWindowHandle) { 0 } else { 1 } } }
            )
            if ($windowHandles.Count -eq 0 -and $primaryWindowHandle -ne 0) {
                $windowHandles = @($primaryWindowHandle)
            }
            if ($windowHandles.Count -eq 0) {
                continue
            }

            $secondaryWindowHandles = @($windowHandles | Where-Object { $_ -ne $primaryWindowHandle })
            $projectHandleSlots = if ($projectTargetNames.Count -eq $windowHandles.Count) {
                @($windowHandles)
            } elseif ($projectTargetNames.Count -lt $windowHandles.Count) {
                @($secondaryWindowHandles)
            } else {
                @($windowHandles)
            }
            if ($projectTargetNames.Count -gt 0) {
                $knownProjectHandleCount = @($projectHandleSlots | Where-Object {
                    $script:CodexPlusWindowProjectNames.ContainsKey([string]$_)
                }).Count
                $unassignedProjectHandles = @($projectHandleSlots | Where-Object {
                    -not $script:CodexPlusWindowProjectNames.ContainsKey([string]$_)
                })
                for ($projectIndex = 0; $projectIndex -lt $unassignedProjectHandles.Count; $projectIndex++) {
                    $targetIndex = $knownProjectHandleCount + $projectIndex
                    if ($targetIndex -ge $projectTargetNames.Count) { break }
                    $script:CodexPlusWindowProjectNames[[string]$unassignedProjectHandles[$projectIndex]] = $projectTargetNames[$targetIndex]
                }
            }

            foreach ($projectHandle in @($windowHandles | Where-Object {
                $script:CodexPlusWindowProjectNames.ContainsKey([string]$_)
            })) {
                $projectHandleKey = [string]$projectHandle
                if ($script:CodexPlusProjectWindowOrder -notcontains $projectHandleKey) {
                    $script:CodexPlusProjectWindowOrder += $projectHandleKey
                }
            }
            $visibleProjectHandleKeys = @($windowHandles | Where-Object {
                $script:CodexPlusWindowProjectNames.ContainsKey([string]$_)
            } | ForEach-Object { [string]$_ })
            $script:CodexPlusProjectWindowOrder = @($script:CodexPlusProjectWindowOrder | Where-Object {
                $visibleProjectHandleKeys -contains $_
            })
            $projectWindowCount = $script:CodexPlusProjectWindowOrder.Count

            $usedOrdinals = @()
            foreach ($windowHandle in $windowHandles) {
                $windowHandleKey = [string]$windowHandle
                $isProjectWindow = $script:CodexPlusWindowProjectNames.ContainsKey($windowHandleKey)
                $projectName = if ($isProjectWindow) {
                    [string]$script:CodexPlusWindowProjectNames[$windowHandleKey]
                } else {
                    ''
                }
                # Project windows share the same taskbar/window namespace as
                # regular windows. Their project name changes the title text,
                # but must not restart ordinal enumeration at 1 per project.
                $windowOrdinal = if ($windowHandle -eq $primaryWindowHandle) {
                    $processOrdinal
                } else {
                    $currentTitle = Get-CodexNativeWindowTitle -WindowHandle $windowHandle
                    $titleMatch = [regex]::Match([string]$currentTitle, '^(\d+)\..+$')
                    if ($titleMatch.Success) {
                        $candidateOrdinal = [int]$titleMatch.Groups[1].Value
                        if ($candidateOrdinal -gt 0 -and $candidateOrdinal -notin $usedOrdinals) {
                            $candidateOrdinal
                        } else {
                            Get-CodexNextWindowTitleOrdinal
                        }
                    } else {
                        Get-CodexNextWindowTitleOrdinal
                    }
                }

                if (-not $isProjectWindow -and $windowOrdinal -gt 0) {
                    $usedOrdinals += $windowOrdinal
                }
                $currentWindowTitle = Get-CodexNativeWindowTitle -WindowHandle $windowHandle
                $projectMatch = if (-not $isProjectWindow) {
                    [regex]::Match([string]$currentWindowTitle, '^Codex Plus Project:\s*(.+)$')
                } else {
                    $null
                }
                if (-not $isProjectWindow -and $projectMatch.Success) {
                    $script:CodexPlusWindowProjectNames[[string]$windowHandle] = $projectMatch.Groups[1].Value.Trim()
                }
                $desiredTitle = if (-not $isProjectWindow -and $windowHandle -eq $primaryWindowHandle) {
                    Get-CodexDesiredWindowTitle -Ordinal $processOrdinal
                } else {
                    Get-CodexDesiredWindowTitle -Ordinal $windowOrdinal -ProjectName $projectName
                }
                if ((Get-CodexNativeWindowTitle -WindowHandle $windowHandle) -ne $desiredTitle) {
                    if (Set-CodexNativeWindowTitle -WindowHandle $windowHandle -Title $desiredTitle) {
                        $updated = $true
                    }
                }
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

function Get-CodexDesktopProcessNames {
    param([AllowEmptyString()][string]$PreferredExeName)

    $allowedNames = @('ChatGPT.exe', 'Codex.exe')
    if (-not [string]::IsNullOrWhiteSpace($PreferredExeName) -and ($allowedNames -notcontains $PreferredExeName)) {
        $allowedNames = @($PreferredExeName) + $allowedNames
    }

    return @(
        $allowedNames |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )
}

function Get-CodexDesktopProcessNameFilter {
    param([string[]]$Names)

    $normalizedNames = @(
        @($Names) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )
    $clauses = foreach ($name in $normalizedNames) {
        "Name = '$($name.Replace("'", "''"))'"
    }

    return (@($clauses) -join ' OR ')
}

function Get-CodexDesktopProcesses {
    $installInfo = Get-CodexInstallInfo
    $preferredExeName = if ($installInfo.AppExe) { [System.IO.Path]::GetFileName($installInfo.AppExe) } else { $null }
    $processNames = Get-CodexDesktopProcessNames -PreferredExeName $preferredExeName
    $nameFilter = Get-CodexDesktopProcessNameFilter -Names $processNames
    if ([string]::IsNullOrWhiteSpace($nameFilter)) {
        return @()
    }

    try {
        return @(
            Get-CimInstance Win32_Process -Filter $nameFilter -OperationTimeoutSec 3 -ErrorAction Stop |
                Where-Object {
                    $_.ExecutablePath -and
                    $_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*\app\*.exe' -and
                    $_.ExecutablePath -notlike '*\WindowsApps\OpenAI.Codex_*\app\resources\*' -and
                    ($processNames -contains [System.IO.Path]::GetFileName($_.ExecutablePath))
                }
        )
    } catch {
        return @()
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
            $response = Invoke-RestMethod -Uri "$base/json/list" -UseBasicParsing -TimeoutSec 2
            return @($response | ForEach-Object { $_ })
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
        [int]$DashboardProcessId = 0,
        [int]$PollMilliseconds = 250,
        [int]$GracePolls = 3,
        [int]$MissingProcessGracePolls = 40,
        [int]$StartupWaitSeconds = 30
    )

    $startupDeadline = [DateTime]::UtcNow.AddSeconds($StartupWaitSeconds)
    $seenMatchingProcess = $false
    # Process cleanup is deliberately disarmed during startup. Electron may
    # create the instance processes well before it publishes a native window.
    $closeCleanupArmed = $false
    $missingVisibleWindowCount = 0
    $missingProcessCount = 0
    Start-CodexUsageSessionWatcher
    $seenProcessIds = [System.Collections.Generic.HashSet[int]]::new()
    $stopSeenProcesses = {
        foreach ($processId in @($seenProcessIds)) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
    }
    $stopDashboard = {
        if ($DashboardProcessId -gt 0) {
            Stop-Process -Id $DashboardProcessId -Force -ErrorAction SilentlyContinue
        }
        $dashboardProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -like '*dashboard-server.ps1*' -and $_.CommandLine -like '*-Port 3000*' -and ($LauncherKey -eq '' -or $_.CommandLine -like ('*' + $LauncherKey + '*'))
        }
        foreach ($dashboardProcess in @($dashboardProcesses)) {
            Stop-Process -Id ([int]$dashboardProcess.ProcessId) -Force -ErrorAction SilentlyContinue
        }
    }
    while ($true) {
        $matchingProcesses = @(
            Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessMatchesCodexPlusInstance -Process $_ -Port $Port -LauncherKey $LauncherKey
            }
        )
        if ($matchingProcesses.Count -eq 0) {
            if ((-not $seenMatchingProcess) -and ([DateTime]::UtcNow -lt $startupDeadline)) {
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }
            if (-not $seenMatchingProcess) {
                & $stopDashboard
                Stop-CodexUsageSessionWatcher
                return
            }

            if (-not $closeCleanupArmed) {
                # A browser process can be replaced while the first window is
                # still launching. Never terminate an observed process before
                # this instance has exposed its initial visible window.
                if ([DateTime]::UtcNow -ge $startupDeadline) {
                    & $stopDashboard
                    Stop-CodexUsageSessionWatcher
                    return
                }
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }

            # Process discovery can briefly return no rows while Electron replaces
            # its browser process or WMI/CIM is under load. Exiting on the first
            # empty sample permanently orphaned otherwise healthy Plus instances,
            # leaving no watchdog to terminate them after their last window closed.
            $missingProcessCount++
            if ($missingProcessCount -ge $MissingProcessGracePolls) {
                # The process can disappear from CIM before it has actually
                # exited.  Always clean up the processes observed for this
                # launcher instance before abandoning the watchdog.
                & $stopSeenProcesses
                & $stopDashboard
                return
            }
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }
        $missingProcessCount = 0
        foreach ($process in $matchingProcesses) {
            [void]$seenProcessIds.Add([int]$process.ProcessId)
        }
        if (-not $seenMatchingProcess) {
            $seenMatchingProcess = $true
        }

        $visibleProcessCount = Get-CodexVisibleProcessCount -Port $Port -LauncherKey $LauncherKey
        if ($visibleProcessCount -gt 0) {
            $closeCleanupArmed = $true
            $missingVisibleWindowCount = 0
            try {
                Maximize-CodexPlusWindows -Port $Port -LauncherKey $LauncherKey | Out-Null
            } catch {
            }
            try {
                Invoke-CodexPlusInjection -Port $Port | Out-Null
            } catch {
            }
            if ($script:CodexPlusUsageRefreshRequested) {
                $script:CodexPlusUsageRefreshRequested = $false
                $changedPaths = @($script:CodexPlusChangedSessionPaths.Keys)
                foreach ($changedPath in $changedPaths) { $script:CodexPlusChangedSessionPaths.Remove($changedPath) }
                $script:CodexPlusUsageChangedPaths = $changedPaths
                $script:CodexPlusRateLimitTitleCache = $null
                Update-CodexWindowTitles -Port $Port -LauncherKey $LauncherKey | Out-Null
                if ($changedPaths.Count -gt 0) {
                    Update-CodexPrematureSessionState -Paths $changedPaths
                }
            }
            foreach ($alert in @(Get-CodexPrematureSessionAlerts)) {
                Show-CodexPrematureSessionAlert -Alert $alert
                try {
                    $alertJson = $script:CodexPlusPrematureAlertPayload
                    $command = New-CodexCdpCommand -Id 91 -Method 'Runtime.evaluate' -Params @{ expression = "window.dispatchEvent(new CustomEvent('codex-plus-session-alert',{detail:$alertJson}));" }
                    foreach ($target in @(Get-CodexDevToolsTargets -Port $Port | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })) { Invoke-CodexCdpCommand -WebSocketDebuggerUrl $target.webSocketDebuggerUrl -Command $command | Out-Null }
                } catch { }
            }
        } else {
            if ($closeCleanupArmed) {
                $missingVisibleWindowCount++
            } else {
                $missingVisibleWindowCount = 0
            }
        }

        if ($missingVisibleWindowCount -ge $GracePolls) {
            Stop-CodexDesktopProcesses -Port $Port -LauncherKey $LauncherKey -CurrentInstanceOnly
            & $stopSeenProcesses
            & $stopDashboard
            return
        }

        Start-Sleep -Milliseconds $PollMilliseconds
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
        [Parameter(Mandatory)][string]$Payload,
        [switch]$SkipNewDocumentInstall
    )

    $commands = @()
    if (-not $SkipNewDocumentInstall) {
        $commands += New-CodexCdpCommand -Id 1 -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{
                source = $Payload
                runImmediately = $true
            }
    }
    $commands += New-CodexCdpCommand -Id 2 -Method 'Runtime.evaluate' -Params @{
            expression = $Payload
            awaitPromise = $true
            returnByValue = $true
        }

    foreach ($command in $commands) {
        Invoke-CodexCdpCommand -WebSocketDebuggerUrl $Target.webSocketDebuggerUrl -Command $command | Out-Null
    }

    $usageTitle = Get-CodexUsageWindowTitle
    $usageTitleLiteral = ([string]$usageTitle | ConvertTo-Json -Compress)
    $usagePublish = New-CodexCdpCommand -Id 3 -Method 'Runtime.evaluate' -Params @{
        expression = "window.__CODEX_PLUS_USAGE_WINDOW_TITLE = $usageTitleLiteral; window.dispatchEvent(new Event('codex-plus-usage-updated'));"
        returnByValue = $true
    }
    Invoke-CodexCdpCommand -WebSocketDebuggerUrl $Target.webSocketDebuggerUrl -Command $usagePublish | Out-Null
}

function Invoke-CodexPlusInjection {
    param([Parameter(Mandatory)][int]$Port)

    if (-not $script:CodexPlusInjectedTargetIds) {
        $script:CodexPlusInjectedTargetIds = @{}
    }

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
            $targetId = [string]$target.id
            if ($targetId -and $script:CodexPlusInjectedTargetIds.ContainsKey($targetId)) {
                continue
            }

            Invoke-CodexRtlInjectionForTarget -Target $target -Payload $payload
            if ($targetId) {
                $script:CodexPlusInjectedTargetIds[$targetId] = $true
            }
            # A newly opened project target exposes its project context as soon as
            # this injection completes. Sync native titles before moving on to
            # other targets so the taskbar does not wait for the whole batch.
            Update-CodexWindowTitles -Port $Port | Out-Null
            # A newly-created project target can finish adopting its pending
            # context just after Runtime.evaluate returns. Retry briefly so
            # the native taskbar title observes the project name as soon as it
            # becomes available, instead of leaving the window on its launch
            # title until the next polling cycle.
            Start-Sleep -Milliseconds 100
            Update-CodexWindowTitles -Port $Port | Out-Null
            Start-Sleep -Milliseconds 250
            Update-CodexWindowTitles -Port $Port | Out-Null
        } catch {
            Write-Warn "Codex Plus injection failed for target '$($target.title)': $($_.Exception.Message)"
        }
    }
    Update-CodexWindowTitles -Port $Port | Out-Null
    return $true
}
