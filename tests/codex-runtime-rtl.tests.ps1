$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
. $patchScript -SkipMain

$script:Output = @()

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object,
        [ConsoleColor]$ForegroundColor
    )
    if ($null -ne $Object) {
        $script:Output += (($Object | ForEach-Object { "$_" }) -join ' ')
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$statePath = Get-CodexRtlStatePath
Assert-True ($statePath.EndsWith('Codex Plus\state.json')) 'State path should be under the per-user Codex Plus folder.'
Assert-True ((Get-CodexRtlRuntimeRoot).EndsWith('Codex Plus\runtime')) 'Runtime root should be under LocalAppData.'
Assert-True (-not [bool](Get-Command -Name Get-CodexRtlWatcherTaskName -CommandType Function -ErrorAction SilentlyContinue)) 'Codex runtime patch should not expose watcher task helpers.'
Assert-True (-not [bool](Get-Command -Name Start-CodexRtlWatcher -CommandType Function -ErrorAction SilentlyContinue)) 'Codex runtime patch should not expose a background watcher.'

$tmpRuntimeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-runtime-copy-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRuntimeRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRuntimeRoot 'LocalAppData'
    $runtimeRoot = Install-CodexRtlRuntimeFiles -SourceRoot $repoRoot
    $requiredRuntimeFiles = @(
        'patch.ps1',
        'src/shared/logging.ps1',
        'src/shared/prompting.ps1',
        'src/shared/asar.ps1',
        'src/codex/detection.ps1',
        'src/codex/new-chat-button.ps1',
        'src/codex/new-window-button.ps1',
        'src/codex/rtl-payload.ps1',
        'src/codex/split-model-effort-selector.ps1',
        'src/codex/project-selector-guard.ps1',
        'src/runtime/state.ps1',
        'src/runtime/files.ps1',
        'src/runtime/shortcuts.ps1',
        'src/runtime/launch.ps1',
        'src/runtime/global-manager.ps1',
        'src/runtime/patching.ps1',
        'src/ui/menu.ps1'
    )
    foreach ($requiredRuntimeFile in $requiredRuntimeFiles) {
        Assert-True (Test-Path -LiteralPath (Join-Path $runtimeRoot $requiredRuntimeFile)) "Runtime copy should include '$requiredRuntimeFile'."
    }
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRuntimeRoot) {
        Remove-Item -LiteralPath $tmpRuntimeRoot -Recurse -Force
    }
}

$state = New-CodexRtlState -InstallInfo ([pscustomobject]@{
    PackageVersion = '1.2.3'
    InstallLocation = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake'
    AppExe = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
}) -Port 18317 -ShortcutBackups @(
    [pscustomobject]@{
        OriginalPath = 'C:\Users\Test\Desktop\Codex.lnk'
        BackupPath = 'C:\Users\Test\AppData\Local\Codex Plus\backups\shortcuts\abc.lnk'
    }
)
Assert-Equal 1 $state.Version 'Codex RTL state should have an explicit manifest version.'
Assert-True ($state.RuntimeRoot.EndsWith('Codex Plus\runtime')) 'Codex RTL state should persist the runtime root.'
Assert-True ($state.LauncherScriptPath.EndsWith('Codex Plus\runtime\launch-codex-plus.vbs')) 'Codex RTL state should persist the launcher script path.'
Assert-Equal 1 @($state.OwnedArtifacts).Count 'Codex RTL state should track owned artifacts explicitly.'
Assert-Equal 'C:\Users\Test\Desktop\Codex.lnk' $state.OwnedArtifacts[0] 'Owned artifacts should include tracked shortcut paths.'

$tmpUserDataRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-user-data-test-{0}" -f ([guid]::NewGuid()))
$oldLocalAppDataForUserData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $tmpUserDataRoot
    $launcherShortcutPath = 'C:\Users\Test\Desktop\Codex Plus.lnk'
    $launcherKey = Get-CodexLauncherIdentity -ShortcutPath $launcherShortcutPath
    Assert-True ($launcherKey -match '^[0-9a-f]{64}$') 'Launcher identity should be a stable SHA-256 hex string.'
    Assert-Equal $launcherKey (Get-CodexLauncherIdentity -ShortcutPath $launcherShortcutPath) 'Launcher identity should be stable for the same shortcut path.'
    Assert-Equal (Join-Path $tmpUserDataRoot 'Codex Plus\profile') (Get-CodexPlusUserDataDirectory) 'Default Codex profile path should stay shared.'
    Assert-Equal (Join-Path $tmpUserDataRoot "Codex Plus\profile\$launcherKey") (Get-CodexPlusUserDataDirectory -LauncherKey $launcherKey) 'Launcher-specific profile path should be namespaced by launcher identity.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppDataForUserData
    if (Test-Path -LiteralPath $tmpUserDataRoot) {
        Remove-Item -LiteralPath $tmpUserDataRoot -Recurse -Force
    }
}

$launcherScript = New-CodexRtlLauncherScriptContent -PatchScriptPath (Join-Path (Get-CodexRtlRuntimeRoot) 'patch.ps1')
Assert-True ($launcherScript.Contains('powershell.exe')) 'VBS launcher should run PowerShell internally.'
Assert-True ($launcherScript.Contains('-LaunchCodexRtl')) 'VBS launcher should call the explicit Codex launch entrypoint.'
Assert-True ($launcherScript.Contains('-ShowLaunchSplash')) 'VBS launcher should start the launch splash helper before Codex appears.'
Assert-True ($launcherScript.Contains('WScript.Arguments(0)')) 'VBS launcher should forward the shortcut-specific launcher identity.'
Assert-True ($launcherScript.Contains('For argumentIndex = 1 To WScript.Arguments.Count - 1')) 'VBS launcher should accept an installer-selected port regardless of shortcut argument position.'
Assert-True ($launcherScript.Contains('-PreferredPort')) 'VBS launcher should forward an installer-selected port to PowerShell.'
Assert-True ($launcherScript.Contains('CODEX_PLUS_REQUESTED_PORT')) 'VBS launcher should inherit an installer-selected port from the Desktop launch environment.'
Assert-True ($launcherScript.Contains('CODEX_PLUS_LAUNCHER_KEY')) 'VBS launcher should pass the launcher identity through the process environment.'
Assert-True ($launcherScript -match 'command = command & .* -LauncherKey') 'VBS launcher should pass the scoped launcher identity to the main launch command.'
Assert-True ($launcherScript.Contains('WScript.Arguments(0)')) 'VBS launcher should forward the shortcut-specific launcher identity.'
Assert-True ($launcherScript.Contains('CODEX_PLUS_LAUNCHER_KEY')) 'VBS launcher should pass the launcher identity through the process environment.'
Assert-True ($launcherScript.Contains('Scriptlet.TypeLib')) 'VBS launcher should create a fresh instance identity for each shortcut launch.'
Assert-True ($launcherScript.Contains('instanceKey = launcherKey & "-"')) 'VBS launcher should derive each instance identity from the shortcut identity.'
Assert-True (-not $launcherScript.Contains('dashboard-server.ps1')) 'VBS launcher should leave the dashboard under the global manager.'
Assert-True ($launcherScript.Contains('Chr(34)')) 'VBS launcher should build the quoted patch path using Chr(34).'
Assert-True ($launcherScript -match 'command = "powershell\.exe .* -File " & Chr\(34\) & ".*" & Chr\(34\) & " -LaunchCodexRtl"') 'VBS launcher should concatenate the quoted patch path safely.'
Assert-True ($launcherScript.Contains(', 0, False')) 'VBS launcher should hide the window and not wait.'
Assert-Equal 0 ([regex]::Matches($launcherScript, '-StartCloseWatchdog').Count) 'VBS launcher should not create a per-window close watchdog.'

$tmpIconRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-icon-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path (Join-Path $tmpIconRoot 'app\resources') | Out-Null
$oldIconLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpIconRoot 'LocalAppData'
    $fakeIcon = Join-Path $tmpIconRoot 'app\resources\icon.ico'
    Set-Content -LiteralPath $fakeIcon -Value 'ico' -Encoding ASCII
    $fakeInstallInfoForIcon = [pscustomobject]@{
        InstallLocation = $tmpIconRoot
        AppExe = Join-Path $tmpIconRoot 'app\Codex.exe'
    }
    Assert-Equal $fakeIcon (Get-CodexIconLocation -InstallInfo $fakeInstallInfoForIcon) 'Icon location should prefer app\resources\icon.ico.'

    $fakeInstallInfoFallback = [pscustomobject]@{
        InstallLocation = 'C:\Missing\OpenAI.Codex'
        AppExe = 'C:\Missing\OpenAI.Codex\app\Codex.exe'
    }
    Assert-Equal "$($fakeInstallInfoFallback.AppExe),0" (Get-CodexIconLocation -InstallInfo $fakeInstallInfoFallback) 'Icon location should fall back to Codex.exe,0 before shell icons.'
} finally {
    $env:LOCALAPPDATA = $oldIconLocalAppData
    if (Test-Path -LiteralPath $tmpIconRoot) { Remove-Item -LiteralPath $tmpIconRoot -Recurse -Force }
}
$installBody = (Get-Command -Name Install-CodexRtlPatch -CommandType Function).ScriptBlock.ToString()
Assert-True ($installBody.Contains('OwnedArtifacts')) 'Patch flow should persist owned artifacts explicitly.'
Assert-True ($installBody.Contains('Codex Plus')) 'Patch flow should create sibling Codex Plus shortcuts.'
Assert-True (-not $installBody.Contains('Install-CodexPlusProtocolHandler')) 'Patch flow should not register an independent Codex Plus launch protocol.'
Assert-True (-not $installBody.Contains('-AllowRestart')) 'Patch flow should not restart or kill an existing Codex process during install.'
Assert-True (-not $installBody.Contains('Start-CodexForRtl')) 'Patch flow should not launch Codex during install.'
Assert-True (-not $installBody.Contains('Invoke-CodexRtlInjection')) 'Patch flow should not inject Codex during install.'
$launchBody = (Get-Command -Name Launch-CodexRtl -CommandType Function).ScriptBlock.ToString()
Assert-True ($launchBody.Contains('Start-CodexForRtl')) 'Codex launch should delegate to the approved-verb launch helper.'
Assert-True ($launchBody.Contains('Register-CodexPlusManagerInstance')) 'Codex launch should register with the independent manager before starting the app.'
Assert-True (-not [bool](Get-Command -Name Watch-CodexCloseToQuit -CommandType Function -ErrorAction SilentlyContinue)) 'The retired per-window polling watchdog should not be loaded.'
$devToolsBody = (Get-Command -Name Get-CodexDevToolsTargets -CommandType Function).ScriptBlock.ToString()
Assert-True ($devToolsBody.Contains('ForEach-Object { $_ }')) 'Codex DevTools target enumeration should flatten multiple page targets.'
$splashIconBody = (Get-Command -Name Get-CodexLaunchSplashIcon -CommandType Function).ScriptBlock.ToString()
Assert-True ($splashIconBody.Contains('Get-CodexIconLocation')) 'Launch splash should reuse the same icon source as the desktop launcher.'
Assert-True ($splashIconBody.Contains('Add-Type -AssemblyName System.Drawing')) 'Launch splash icon loading should explicitly load System.Drawing before extracting icons.'
$splashIconSourceBody = (Get-Command -Name Get-CodexLaunchSplashIconSource -CommandType Function).ScriptBlock.ToString()
Assert-True ($splashIconSourceBody.Contains('CreateBitmapSourceFromHIcon')) 'Launch splash should convert the Codex icon into a clean WPF image source.'
Assert-True ($splashIconSourceBody.Contains('FormatConvertedBitmap')) 'Launch splash should normalize the icon bitmap before recoloring it.'
Assert-True ($splashIconSourceBody.Contains('$pixels[$i] = 255')) 'Launch splash should recolor visible icon pixels to white.'
Assert-True ($splashIconSourceBody.Contains('$whiteBitmap.Freeze()')) 'Launch splash bitmap source should be frozen before it is handed to the WPF image control.'
$splashBody = (Get-Command -Name Show-CodexLaunchSplash -CommandType Function).ScriptBlock.ToString()
Assert-True ($splashBody.Contains('[System.Windows.Window]::new()')) 'Launch splash should render through WPF for cleaner transparency.'
Assert-True ($splashBody.Contains('AllowsTransparency = $true')) 'Launch splash should use true alpha transparency instead of a color key.'
Assert-True ($splashBody.Contains('Background = [System.Windows.Media.Brushes]::Transparent')) 'Launch splash background should stay fully transparent.'
Assert-True ($splashBody.Contains('[System.Windows.Controls.Image]')) 'Launch splash should render the Codex icon directly.'
Assert-True ($splashBody.Contains('Text = ''Plus''')) 'Launch splash should add a Plus wordmark next to the icon.'
Assert-True ($splashBody.Contains('$image.Width = 36')) 'Launch splash should keep the icon at the original compact size.'
Assert-True ($splashBody.Contains('$text.FontSize = 28')) 'Launch splash should keep the Plus label at the original compact size.'
Assert-True ($splashBody.Contains('DoubleAnimation')) 'Launch splash should animate the icon while Codex is loading.'
Assert-True ($splashBody.Contains('RepeatBehavior]::Forever')) 'Launch splash icon animation should loop until the Codex window is visible.'
Assert-True ($splashBody.Contains('Get-CodexVisibleProcessCount')) 'Launch splash should close itself when the real Codex window becomes visible.'
$desktopProcessNames = @(Get-CodexDesktopProcessNames)
Assert-Equal 2 @($desktopProcessNames).Count 'Desktop process lookup should include the two supported Codex executable names by default.'
Assert-Equal 'ChatGPT.exe' $desktopProcessNames[0] 'Desktop process lookup should prefer ChatGPT.exe first by default.'
Assert-Equal 'Codex.exe' $desktopProcessNames[1] 'Desktop process lookup should keep Codex.exe as a fallback process name.'
$scopedDesktopProcessNames = @(Get-CodexDesktopProcessNames -PreferredExeName 'CustomCodex.exe')
Assert-Equal 3 @($scopedDesktopProcessNames).Count 'Desktop process lookup should prepend a custom installed executable name without dropping the defaults.'
Assert-Equal 'CustomCodex.exe' $scopedDesktopProcessNames[0] 'Desktop process lookup should query the installed executable name first when it differs from the defaults.'
Assert-Equal "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" (Get-CodexDesktopProcessNameFilter -Names @('ChatGPT.exe', 'Codex.exe')) 'Desktop process lookup should build a WMI filter that only asks for the supported process names.'
$desktopProcessBody = (Get-Command -Name Get-CodexDesktopProcesses -CommandType Function).ScriptBlock.ToString()
Assert-True ($desktopProcessBody.Contains('-Filter $nameFilter')) 'Desktop process lookup should narrow the WMI query to the expected process names.'
Assert-True ($desktopProcessBody.Contains('-OperationTimeoutSec 3')) 'Desktop process lookup should bound the WMI query so splash helpers cannot hang indefinitely.'
Assert-True ($desktopProcessBody.Contains('catch')) 'Desktop process lookup should fail closed when the WMI query stalls or errors.'
$sidebarPayload = Get-CodexSidebarPagingPayload
Assert-True ($sidebarPayload.Contains('appendThreadTimestampToLabel')) 'Sidebar payload should keep the inline modified-time formatter centralized.'
Assert-True ($sidebarPayload.Contains("return elapsedMinutes + 'm'")) 'Sidebar payload should format modified times with concise relative minute labels.'
Assert-True ($sidebarPayload.Contains('THREAD_BASE_LABEL_ATTR')) 'Sidebar payload should preserve the original row label before appending modified time.'
Assert-True ($sidebarPayload.Contains('getLiveSidebarCatalog')) 'Sidebar payload should read thread data from the live Codex app state.'
Assert-True ($sidebarPayload.Contains('cachedBindings')) 'Sidebar payload should discover the live Codex thread bindings structurally.'
Assert-True ($sidebarPayload.Contains('threadKeys')) 'Sidebar payload should use live thread keys for ordering.'
Assert-True ($sidebarPayload.Contains('Array.from(liveCatalogCache?.records?.keys?.() || [])')) 'Sidebar payload should include binding-backed threads when the live key list lags.'
Assert-True ($sidebarPayload.Contains('threadAttentionStateByKey')) 'Sidebar payload should use the authoritative attention map for unread state.'
Assert-True ($sidebarPayload.Contains("resolvedTitle || (isUnread ? 'Unread thread' : '')")) 'Unread unloaded threads should remain visible until their native title mounts.'
Assert-True ($sidebarPayload.Contains('projectGroups')) 'Sidebar payload should use live project groups for project ordering.'
Assert-True ($sidebarPayload.Contains('threadRecencyAtByKey')) 'Sidebar payload should use live thread recency for timestamp fallbacks.'
Assert-True ($sidebarPayload.Contains('conversation.updatedAt')) 'Sidebar payload should use live conversation update times.'
Assert-True ($sidebarPayload.Contains('NATIVE_TIMESTAMP_ELEMENT_ATTR')) 'Sidebar payload should render timestamps as dedicated row elements.'
Assert-True ($sidebarPayload.Contains('inline-flex shrink-0 items-center whitespace-nowrap text-xs text-token-text-tertiary')) 'Sidebar payload should match the task timestamp flex styling.'
Assert-True ($sidebarPayload.Contains("titleHost.classList.toggle('pr-6'")) 'Sidebar payload should keep thread and task timestamps inset from the row edge.'
Assert-True ($sidebarPayload.Contains('ancestor.classList.remove(''pl-2'', ''pl-6'')')) 'Synthetic Recents rows should clear inherited project-thread indentation from their ancestors.'
Assert-True ($sidebarPayload.Contains('!ancestor.hasAttribute(SYNTHETIC_LIST_ATTR)')) 'Synthetic Recents indentation normalization should stop at the Recents list boundary.'
Assert-True ($sidebarPayload.Contains('THREAD_UNREAD_INDICATOR_ATTR')) 'Sidebar payload should identify owned unread indicators on synthetic rows.'
Assert-True ($sidebarPayload.Contains('syncThreadUnreadIndicator')) 'Sidebar payload should mirror unread indicators from matching native thread rows.'
Assert-True ($sidebarPayload.Contains('positionSyntheticStatusIndicator')) 'Synthetic status indicators should stay out of the title flex row so timestamps keep a shared edge.'
Assert-True ($sidebarPayload.Contains("indicator.style.position = 'absolute'")) 'Synthetic unread indicators should be absolutely positioned at the row edge.'
Assert-True ($sidebarPayload.Contains('positionNativeThreadStatusSlot')) 'Native status slots should not reserve flex width beside thread timestamps.'
Assert-True ($sidebarPayload.Contains('conversation.hasUnreadTurn !== undefined')) 'Synthetic unread state should honor an explicit live read state.'
Assert-True ($sidebarPayload.Contains('conversation.unreadCount !== undefined')) 'Synthetic unread state should honor an explicit live unread count.'
Assert-True (-not ($sidebarPayload.Contains('previous.hasUnreadTurn || conversation.hasUnreadTurn || conversation.unread'))) 'Synthetic unread state should not preserve a stale unread flag forever.'
Assert-True (-not ($sidebarPayload.Contains('Math.max(Number(previous.unreadCount || 0), Number(conversation.unreadCount || 0))'))) 'Synthetic unread state should not preserve a stale unread count forever.'
Assert-True ($sidebarPayload.Contains('isUnreadSyntheticThreadRow')) 'Sidebar payload should identify unread synthetic thread rows for visibility.'
Assert-True ($sidebarPayload.Contains('effectiveVisibleCount')) 'Sidebar payload should expand the visible Threads window for unread rows.'
Assert-True ($sidebarPayload.Contains('remainingHiddenRows')) 'Sidebar payload should keep non-unread rows behind the Threads pager.'
Assert-True ($sidebarPayload.Contains('__codexPlusLastPointerActivationAt')) 'Sidebar pager activation should guard pointer and click events across re-renders.'
Assert-True (-not ($sidebarPayload.Contains('Get-CodexRecentThreadSnapshot'))) 'Sidebar payload should not call the removed state DB thread snapshot.'
Assert-True (-not ($sidebarPayload.Contains('PROJECT_TIMESTAMPS'))) 'Sidebar payload should not embed project timestamp snapshots.'
Assert-True ($sidebarPayload.Contains('titleElement.textContent !== nextBaseLabel')) 'Sidebar payload should keep the timestamp separate from the thread title.'
Assert-True (-not ($sidebarPayload.Contains('data-codex-plus-thread-timestamp-suffix'))) 'Sidebar payload should render modified times inline instead of a separate suffix span.'

$roots = @(Get-CodexShortcutSearchRoots)
Assert-True ($roots -contains (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')) 'Shortcut search should include user Start Menu programs.'
Assert-True ($roots -contains (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')) 'Shortcut search should include all-users Start Menu programs.'
Assert-True ($roots -contains (Join-Path $env:USERPROFILE 'Desktop')) 'Shortcut search should include user Desktop.'
Assert-True ($roots -contains (Join-Path $env:PUBLIC 'Desktop')) 'Shortcut search should include public Desktop.'
Assert-True ($roots -contains (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')) 'Shortcut search should include normal taskbar pinned shortcut folder.'

$fakeCodexShortcut = [pscustomobject]@{
    Path = 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Codex.lnk'
    Name = 'Codex.lnk'
    Exists = $true
    IsLink = $true
    IsWritable = $true
    TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0.0_x64__2p2nqsd0c76g0\app\Codex.exe'
    Arguments = ''
}
$ambiguousShortcut = [pscustomobject]@{
    Path = 'C:\Users\Test\Desktop\Notes.lnk'
    Name = 'Notes.lnk'
    Exists = $true
    IsLink = $true
    IsWritable = $true
    TargetPath = 'C:\Windows\notepad.exe'
    Arguments = ''
}
$missingShortcut = [pscustomobject]@{
    Path = 'C:\Missing\Codex.lnk'
    Name = 'Codex.lnk'
    Exists = $false
    IsLink = $true
    IsWritable = $false
    TargetPath = ''
    Arguments = ''
}
$codexFolderOnlyShortcut = [pscustomobject]@{
    Path = 'C:\Users\Test\Documents\Codex\Notes.lnk'
    Name = 'Notes.lnk'
    Exists = $true
    IsLink = $true
    IsWritable = $true
    TargetPath = 'C:\Windows\notepad.exe'
    Arguments = ''
}
Assert-True (Test-CodexShortcutCandidate -Shortcut $fakeCodexShortcut) 'Writable Codex lnk shortcuts should be recognized as Codex shortcut candidates.'
Assert-True (-not (Test-CodexShortcutCandidate -Shortcut $ambiguousShortcut)) 'Ambiguous non-Codex shortcuts should not be recognized as Codex shortcut candidates.'
    Assert-True (Test-CodexShortcutSeedable -Shortcut $fakeCodexShortcut) 'Writable Codex lnk shortcuts should seed sibling Codex Plus shortcuts.'
    Assert-True (-not (Test-CodexShortcutSeedable -Shortcut $ambiguousShortcut)) 'Ambiguous non-Codex shortcuts should not seed sibling Codex Plus shortcuts.'
    Assert-True (-not (Test-CodexShortcutSeedable -Shortcut $missingShortcut)) 'Missing shortcuts should not seed sibling Codex Plus shortcuts.'
Assert-True (-not (Test-CodexShortcutSeedable -Shortcut $codexFolderOnlyShortcut)) 'A parent folder named Codex should not make an unrelated shortcut seedable.'
Assert-Equal 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Codex Plus.lnk' (Get-CodexSiblingRtlShortcutPath -ShortcutPath $fakeCodexShortcut.Path) 'Sibling Codex Plus path should be derived next to the source shortcut.'
Assert-Equal 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OpenAI\Codex Plus.lnk' (Get-CodexSiblingRtlShortcutPath -ShortcutPath 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OpenAI\Codex.lnk') 'Sibling Codex Plus path should stay inside nested Start Menu folders.'
Assert-Equal (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex Plus.lnk') (Get-CodexRtlShortcutPath) 'Canonical user Start Menu Codex Plus path should target the user Programs folder.'

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-shortcut-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRoot 'LocalAppData'
    $sourceShortcutPath = Join-Path $tmpRoot 'Codex.lnk'
    Set-Content -LiteralPath $sourceShortcutPath -Value 'original shortcut bytes' -Encoding ASCII
    $realShortcut = [pscustomobject]@{
        Path = $sourceShortcutPath
        Name = 'Codex.lnk'
        Exists = $true
        IsLink = $true
        IsWritable = $true
        TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        Arguments = ''
    }
    $rtlShortcutPath = Get-CodexSiblingRtlShortcutPath -ShortcutPath $sourceShortcutPath
    $realSpec = New-CodexLauncherShortcutSpec -ShortcutPath $sourceShortcutPath -InstallInfo ([pscustomobject]@{
        InstallLocation = $tmpRoot
        AppExe = Join-Path $tmpRoot 'Codex.exe'
    })
    Assert-Equal (Get-CodexLauncherIdentity -ShortcutPath $sourceShortcutPath) $realSpec.LauncherKey 'Shortcut spec should carry the launcher identity.'
    Assert-True ($realSpec.Arguments -match [regex]::Escape($realSpec.LauncherKey)) 'Shortcut spec should pass the launcher identity to the VBS launcher.'
    New-CodexParallelRtlShortcut -SourceShortcut $realShortcut -Spec $realSpec | Out-Null
    Assert-True (Test-Path -LiteralPath $rtlShortcutPath) 'Parallel Codex Plus shortcut should be created next to the source shortcut.'
    Assert-Equal 'original shortcut bytes' (Get-Content -LiteralPath $sourceShortcutPath -Raw).Trim() 'Creating a parallel Codex Plus shortcut should not modify the original Codex shortcut.'
    Assert-True (Test-CodexRtlOwnedShortcut -ShortcutPath $rtlShortcutPath) 'Created sibling Codex Plus shortcut should be Codex Plus-owned.'

    New-CodexParallelRtlShortcut -SourceShortcut $realShortcut -Spec $realSpec | Out-Null
    Assert-True (Test-Path -LiteralPath $rtlShortcutPath) 'Re-running patch should refresh an existing owned Codex Plus shortcut in place.'

    $foreignRoot = Join-Path $tmpRoot 'foreign'
    New-Item -ItemType Directory -Force -Path $foreignRoot | Out-Null
    $foreignSourceShortcutPath = Join-Path $foreignRoot 'Codex.lnk'
    Set-Content -LiteralPath $foreignSourceShortcutPath -Value 'foreign shortcut bytes' -Encoding ASCII
    $foreignRtlShortcutPath = Get-CodexSiblingRtlShortcutPath -ShortcutPath $foreignSourceShortcutPath
    Set-Content -LiteralPath $foreignRtlShortcutPath -Value 'not-owned' -Encoding ASCII
    $foreignShortcut = [pscustomobject]@{
        Path = $foreignSourceShortcutPath
        Name = 'Codex.lnk'
        Exists = $true
        IsLink = $true
        IsWritable = $true
        TargetPath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        Arguments = ''
    }
    Assert-True (-not (Install-CodexParallelRtlShortcutIfPossible -SourceShortcut $foreignShortcut -Spec $realSpec)) 'Patch should not overwrite a non-owned sibling Codex Plus shortcut.'
    Assert-Equal 'not-owned' (Get-Content -LiteralPath $foreignRtlShortcutPath -Raw).Trim() 'Patch should leave a non-owned sibling Codex RTL shortcut untouched.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

$tmpInstallRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-install-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpInstallRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
$oldAppData = $env:APPDATA
$oldProgramData = $env:ProgramData
$oldUserProfile = $env:USERPROFILE
$oldPublic = $env:PUBLIC
try {
    $env:LOCALAPPDATA = Join-Path $tmpInstallRoot 'LocalAppData'
    $env:APPDATA = Join-Path $tmpInstallRoot 'AppData\Roaming'
    $env:ProgramData = Join-Path $tmpInstallRoot 'ProgramData'
    $env:USERPROFILE = Join-Path $tmpInstallRoot 'UserProfile'
    $env:PUBLIC = Join-Path $tmpInstallRoot 'Public'
    $script:Output = @()
    $script:StartedProcesses = @()
    $script:MockCodexProcesses = @()

    $fakeInstallRoot = Join-Path $tmpInstallRoot 'WindowsApps\OpenAI.Codex_fake'
    $fakeAppExe = Join-Path $fakeInstallRoot 'app\Codex.exe'
    $fakeIcon = Join-Path $fakeInstallRoot 'app\resources\icon.ico'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeAppExe) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeIcon) | Out-Null
    Set-Content -LiteralPath $fakeAppExe -Value 'exe' -Encoding ASCII
    Set-Content -LiteralPath $fakeIcon -Value 'ico' -Encoding ASCII

    New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') | Out-Null

    function Get-CodexInstallInfo {
        [pscustomobject]@{
            PackageFound = $true
            PackageVersion = '1.2.3'
            InstallLocation = $fakeInstallRoot
            AppExe = $fakeAppExe
        }
    }
    function Install-CodexRtlRuntimeFiles { param([string]$SourceRoot) return (Get-CodexRtlRuntimeRoot) }
    function Get-CodexShortcutInventory { @() }
    function Read-CodexRtlState { $null }
    function Save-CodexRtlState { param($State) $script:SavedState = $State }
    function Wait-CodexWindowTitleSync { param([int]$Port, [string]$LauncherKey, [int]$TimeoutSeconds = 15) $true }
    function Start-CodexForRtl {
        param($Inspection, [int]$Port, [switch]$AllowRestart)
        $script:StartedProcesses += 'rtl'
        'started'
    }
    function Invoke-CodexPlusInjection { param([int]$Port) $true }
    Install-CodexRtlPatch

    $fallbackStartMenuShortcut = Get-CodexRtlShortcutPath
    Assert-True (Test-Path -LiteralPath $fallbackStartMenuShortcut) 'Patch should always create a user Start Menu Codex Plus shortcut even when no seedable Codex shortcut exists there.'
    Assert-True (Test-CodexRtlOwnedShortcut -ShortcutPath $fallbackStartMenuShortcut) 'Fallback user Start Menu Codex Plus shortcut should be Codex Plus-owned.'
    Assert-True (@($script:SavedState.OwnedArtifacts) -contains $fallbackStartMenuShortcut) 'Saved state should track the fallback user Start Menu Codex Plus shortcut.'
    Assert-True (($script:Output -join "`n") -match 'Codex Plus launcher installed\.') 'Patch wording should start with a clear success summary.'
    Assert-True (($script:Output -join "`n") -match 'Created or refreshed 2 Codex Plus shortcut') 'Patch wording should count the fallback Start Menu Codex Plus shortcut creation.'
    Assert-True (($script:Output -join "`n") -match 'Skipped 0 candidate location') 'Patch wording should report skipped shortcut locations clearly.'
    Assert-True (($script:Output -join "`n") -match 'Launch Codex using a Codex Plus shortcut') 'Patch wording should tell the user how to start the patched app.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:APPDATA = $oldAppData
    $env:ProgramData = $oldProgramData
    $env:USERPROFILE = $oldUserProfile
    $env:PUBLIC = $oldPublic
    if (Test-Path -LiteralPath $tmpInstallRoot) {
        Remove-Item -LiteralPath $tmpInstallRoot -Recurse -Force
    }
}

. $patchScript -SkipMain

$tmpRestoreRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-restore-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRestoreRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRestoreRoot 'LocalAppData'
    $script:Output = @()
    $script:StartedProcesses = @()
    $script:MockCodexProcesses = @(
        [pscustomobject]@{
            ProcessId = 321
            ExecutablePath = Join-Path $tmpRestoreRoot 'Codex.exe'
            CommandLine = '"C:\Fake\Codex.exe" --remote-debugging-port=18317 --remote-debugging-address=127.0.0.1'
        }
    )

    $launcherScriptPath = Get-CodexPlusLauncherScriptPath
    $launcherScriptDir = Split-Path -Parent $launcherScriptPath
    New-Item -ItemType Directory -Force -Path $launcherScriptDir | Out-Null
    Set-Content -LiteralPath $launcherScriptPath -Value 'launcher' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $tmpRestoreRoot 'Codex.exe') -Value 'exe' -Encoding ASCII

    $originalShortcutPath = Join-Path $tmpRestoreRoot 'Desktop\Codex.lnk'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $originalShortcutPath) | Out-Null
    Set-Content -LiteralPath $originalShortcutPath -Value 'original codex shortcut bytes' -Encoding ASCII

    $ownedShortcutPath = Join-Path $tmpRestoreRoot 'Desktop\Codex Plus.lnk'
    $ownedShortcutDir = Split-Path -Parent $ownedShortcutPath
    New-Item -ItemType Directory -Force -Path $ownedShortcutDir | Out-Null
    $ownedShortcutSpec = New-CodexLauncherShortcutSpec -ShortcutPath $ownedShortcutPath -InstallInfo ([pscustomobject]@{
        InstallLocation = $tmpRestoreRoot
        AppExe = Join-Path $tmpRestoreRoot 'Codex.exe'
    })
    New-CodexLauncherShortcut -ShortcutPath $ownedShortcutPath -Spec $ownedShortcutSpec

    function Get-CodexDesktopProcesses { @($script:MockCodexProcesses) }
    function Stop-CodexDesktopProcesses { $script:MockCodexProcesses = @() }
    function Start-Process {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [string]$WorkingDirectory
        )
        $script:StartedProcesses += [pscustomobject]@{
            FilePath = $FilePath
            ArgumentList = if ($PSBoundParameters.ContainsKey('ArgumentList')) { @($ArgumentList) } else { @() }
            HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
            WorkingDirectory = $WorkingDirectory
        }
    }

    $backupRoot = Join-Path $tmpRestoreRoot 'backups'
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

    $goodBackupPath = Join-Path $backupRoot 'good.lnk'
    Set-Content -LiteralPath $goodBackupPath -Value 'original good shortcut bytes' -Encoding ASCII
    $goodOriginalPath = Join-Path $tmpRestoreRoot 'Restored\Codex.lnk'

    $badBackupPath = Join-Path $backupRoot 'bad.lnk'
    Set-Content -LiteralPath $badBackupPath -Value 'original bad shortcut bytes' -Encoding ASCII
    $badParentPath = Join-Path $tmpRestoreRoot 'blocked-parent'
    Set-Content -LiteralPath $badParentPath -Value 'not a directory' -Encoding ASCII
    $badOriginalPath = Join-Path $badParentPath 'Codex.lnk'

    $state = [pscustomobject]@{
        Version = 1
        Port = 18317
        PackageVersion = '1.2.3'
        InstallLocation = $tmpRestoreRoot
        AppExe = Join-Path $tmpRestoreRoot 'Codex.exe'
        RuntimeRoot = Get-CodexRtlRuntimeRoot
        LauncherScriptPath = $launcherScriptPath
        ShortcutBackups = @(
            [pscustomobject]@{
                OriginalPath = $goodOriginalPath
                BackupPath = $goodBackupPath
            },
            [pscustomobject]@{
                OriginalPath = $badOriginalPath
                BackupPath = $badBackupPath
            }
        )
        OwnedArtifacts = @($ownedShortcutPath)
        UpdatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Save-CodexRtlState -State $state

    Restore-CodexRtlPatch

    Assert-Equal 'original codex shortcut bytes' (Get-Content -LiteralPath $originalShortcutPath -Raw).Trim() 'Restore patch should leave the original Codex shortcut untouched.'
    Assert-Equal 'original good shortcut bytes' (Get-Content -LiteralPath $goodOriginalPath -Raw).Trim() 'Restore patch should restore backups that can be copied successfully.'
    Assert-True (-not (Test-Path -LiteralPath $ownedShortcutPath)) 'Restore patch should still remove owned shortcuts after one backup restore fails.'
    Assert-True (-not (Test-Path -LiteralPath $launcherScriptPath)) 'Restore patch should still remove the launcher script after one backup restore fails.'
    Assert-True (-not (Test-Path -LiteralPath (Get-CodexRtlStatePath))) 'Restore patch should still remove the state file after one backup restore fails.'
    Assert-Equal 1 @($script:StartedProcesses).Count 'Restore should restart Codex normally when the patched RTL session is currently running.'
    Assert-Equal (Join-Path $tmpRestoreRoot 'Codex.exe') $script:StartedProcesses[0].FilePath 'Restore restart should use the normal Codex executable path.'
    Assert-True (-not $script:StartedProcesses[0].HasArgumentList) 'Restore restart should omit normal-launch ArgumentList entirely.'
    Assert-Equal 0 @($script:StartedProcesses[0].ArgumentList).Count 'Restore restart should not reuse RTL debug arguments.'
    Assert-True (($script:Output -join "`n") -match 'Codex Plus runtime removed\.') 'Restore wording should start with a clear success summary.'
    Assert-True (($script:Output -join "`n") -match 'Restored 1 shortcut backup') 'Restore wording should clearly count restored shortcut backups.'
    Assert-True (($script:Output -join "`n") -match 'Removed 1 owned Codex Plus shortcut') 'Restore wording should clearly count removed owned shortcuts.'
    Assert-True (($script:Output -join "`n") -match 'Restarted Codex in normal mode\.') 'Restore wording should mention the automatic normal restart on its own line.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRestoreRoot) {
        Remove-Item -LiteralPath $tmpRestoreRoot -Recurse -Force
    }
}

$tmpRestoreNoRestartRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-restore-no-restart-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpRestoreNoRestartRoot | Out-Null
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpRestoreNoRestartRoot 'LocalAppData'
    $script:Output = @()
    $script:StartedProcesses = @()
    $script:MockCodexProcesses = @(
        [pscustomobject]@{
            ProcessId = 654
            ExecutablePath = Join-Path $tmpRestoreNoRestartRoot 'Codex.exe'
            CommandLine = '"C:\Fake\Codex.exe"'
        }
    )

    $launcherScriptPath = Get-CodexPlusLauncherScriptPath
    $launcherScriptDir = Split-Path -Parent $launcherScriptPath
    New-Item -ItemType Directory -Force -Path $launcherScriptDir | Out-Null
    Set-Content -LiteralPath $launcherScriptPath -Value 'launcher' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $tmpRestoreNoRestartRoot 'Codex.exe') -Value 'exe' -Encoding ASCII

    $ownedShortcutPath = Join-Path $tmpRestoreNoRestartRoot 'Desktop\Codex Plus.lnk'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ownedShortcutPath) | Out-Null
    $ownedShortcutSpec = New-CodexLauncherShortcutSpec -ShortcutPath $ownedShortcutPath -InstallInfo ([pscustomobject]@{
        InstallLocation = $tmpRestoreNoRestartRoot
        AppExe = Join-Path $tmpRestoreNoRestartRoot 'Codex.exe'
    })
    New-CodexLauncherShortcut -ShortcutPath $ownedShortcutPath -Spec $ownedShortcutSpec

    function Get-CodexDesktopProcesses { @($script:MockCodexProcesses) }
    function Stop-CodexDesktopProcesses { $script:MockCodexProcesses = @() }
    function Start-Process {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [string]$WorkingDirectory
        )
        $script:StartedProcesses += [pscustomobject]@{
            FilePath = $FilePath
            ArgumentList = if ($PSBoundParameters.ContainsKey('ArgumentList')) { @($ArgumentList) } else { @() }
            HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
            WorkingDirectory = $WorkingDirectory
        }
    }

    Save-CodexRtlState -State ([pscustomobject]@{
        Version = 1
        Port = 18317
        PackageVersion = '1.2.3'
        InstallLocation = $tmpRestoreNoRestartRoot
        AppExe = Join-Path $tmpRestoreNoRestartRoot 'Codex.exe'
        RuntimeRoot = Get-CodexRtlRuntimeRoot
        LauncherScriptPath = $launcherScriptPath
        ShortcutBackups = @()
        OwnedArtifacts = @($ownedShortcutPath)
        UpdatedAt = [DateTimeOffset]::Now.ToString('o')
    })

    Restore-CodexRtlPatch

    Assert-Equal 0 @($script:StartedProcesses).Count 'Restore should not restart Codex when the current session is not the RTL-patched one.'
    Assert-True (($script:Output -join "`n") -match 'Codex Plus runtime removed\.') 'Restore wording should still start with a clear success summary when no restart happens.'
    Assert-True (($script:Output -join "`n") -match 'Restored 0 shortcut backup') 'Restore wording should report zero restored backups when none existed.'
    Assert-True (($script:Output -join "`n") -match 'Removed 1 owned Codex Plus shortcut') 'Restore wording should still report removed owned shortcuts when no restart happens.'
    Assert-True (($script:Output -join "`n") -match 'Restart Codex normally if it is still open\.') 'Restore wording should explain the manual normal restart when no patched RTL session was restarted automatically.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $tmpRestoreNoRestartRoot) {
        Remove-Item -LiteralPath $tmpRestoreNoRestartRoot -Recurse -Force
    }
}

$args = New-CodexRtlLaunchArguments -Port 18317
Assert-True ($args -contains '--remote-debugging-port=18317') 'Launch args should enable CDP on the chosen port.'
Assert-True ($args -contains '--remote-debugging-address=127.0.0.1') 'Launch args should bind CDP to loopback only.'
$argsWithOrdinal = New-CodexRtlLaunchArguments -Port 18317 -WindowTitleOrdinal 2
Assert-True ($argsWithOrdinal -contains '--codex-plus-window-title-ordinal=2') 'Launch args should carry the taskbar title ordinal when one is assigned.'

$tmpScopedArgsRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-launch-args-test-{0}" -f ([guid]::NewGuid()))
$oldLocalAppDataForLaunchArgs = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpScopedArgsRoot 'LocalAppData'
    $launcherKey = Get-CodexLauncherIdentity -ShortcutPath 'C:\Users\Test\Desktop\Codex Plus.lnk'
    $scopedArgs = New-CodexRtlLaunchArguments -Port 18317 -LauncherKey $launcherKey
    Assert-True ($scopedArgs -contains "--user-data-dir=$(Get-CodexPlusUserDataDirectory -LauncherKey $launcherKey)") 'Launcher-specific launch args should include the per-shortcut user data directory.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppDataForLaunchArgs
    if (Test-Path -LiteralPath $tmpScopedArgsRoot) {
        Remove-Item -LiteralPath $tmpScopedArgsRoot -Recurse -Force
    }
}

$managedProfileRoot = Normalize-CodexRtlMatchPath -Path (Join-Path (Get-CodexRtlStateRoot) 'profile')
$windowOrdinalProcess = [pscustomobject]@{
    ProcessId = 700
    CommandLine = ('"C:\Fake\Codex.exe" --user-data-dir="{0}\instance-a" --codex-plus-window-title-ordinal=3' -f $managedProfileRoot)
}
Assert-Equal 3 (Get-CodexProcessWindowTitleOrdinal -Process $windowOrdinalProcess) 'Managed process metadata should surface the assigned taskbar title ordinal.'
Assert-True (Test-CodexProcessIsCodexPlusManaged -Process $windowOrdinalProcess) 'Managed Codex Plus processes should be recognized from the profile root.'
Assert-Equal '1.Codex' (Get-CodexDesiredWindowTitle -Ordinal 1) 'Desired taskbar titles should prefix Codex with the ordinal.'
Assert-Equal 'codex-plus' (Get-CodexDesiredWindowTitle -ProjectName 'codex-plus') 'The first project window should initially use only the project name.'
Assert-Equal '2.codex-plus' (Get-CodexDesiredWindowTitle -Ordinal 2 -ProjectName 'codex-plus') 'Project windows should use the project name after the unique ordinal.'
$fixedNow = [DateTimeOffset]::Parse('2026-07-31T00:00:00Z')
$sixDayReset = $fixedNow.AddDays(6).ToUnixTimeSeconds()
$hourReset = $fixedNow.AddHours(3).AddMinutes(20).ToUnixTimeSeconds()
$minuteReset = $fixedNow.AddMinutes(12).AddSeconds(10).ToUnixTimeSeconds()
$sevenDayReset = $fixedNow.AddDays(7).ToUnixTimeSeconds()
Assert-Equal 'Plus Codex - 67% used · resets in 7 days, 0% passed' (Format-CodexUsageWindowTitle -UsedPercent 67 -ResetsAt $sevenDayReset -Now $fixedNow) 'Primary title should show usage, reset countdown, and elapsed time after the reset countdown.'
Assert-Equal 'Plus Codex - 67% used · resets in 4 days, 50% passed' (Format-CodexUsageWindowTitle -UsedPercent 67 -ResetsAt $sevenDayReset -Now $fixedNow.AddDays(3.5)) 'Primary title should show elapsed time at the midpoint of the seven-day window.'
Assert-Equal 'Plus Codex - 67% used · resets in 6 days, 14% passed' (Format-CodexUsageWindowTitle -UsedPercent 67 -ResetsAt $sixDayReset -Now $fixedNow) 'Primary title should calculate elapsed time from a seven-day window start.'
Assert-Equal 'Plus Codex - 67% used · resets in 4 hours, 98% passed' (Format-CodexUsageWindowTitle -UsedPercent 67 -ResetsAt $hourReset -Now $fixedNow) 'Primary title should show hours when the reset is less than a day away.'
Assert-Equal 'Plus Codex - 67% used · resets now, 100% passed' (Format-CodexUsageWindowTitle -UsedPercent 67 -ResetsAt $minuteReset -Now $fixedNow.AddMinutes(13.5)) 'Primary title should clamp elapsed time at the reset boundary.'

$script:MockCodexProcesses = @(
    [pscustomobject]@{
        ProcessId = 701
        ExecutablePath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        CommandLine = ('"C:\Fake\Codex.exe" --user-data-dir="{0}\instance-a" --codex-plus-window-title-ordinal=1' -f $managedProfileRoot)
    },
    [pscustomobject]@{
        ProcessId = 702
        ExecutablePath = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
        CommandLine = ('"C:\Fake\Codex.exe" --user-data-dir="{0}\instance-b" --codex-plus-window-title-ordinal=4' -f $managedProfileRoot)
    }
)
function Get-CodexDesktopProcesses { @($script:MockCodexProcesses) }
Assert-Equal 5 (Get-CodexNextWindowTitleOrdinal) 'Next taskbar title ordinal should advance past the highest live managed ordinal.'

$script:DirectStartProcessCalls = @()
function Start-Process {
    param(
        [string]$FilePath,
        [object[]]$ArgumentList,
        [string]$WorkingDirectory
    )
    if ($PSBoundParameters.ContainsKey('ArgumentList') -and @($ArgumentList).Count -eq 0) {
        throw 'ArgumentList should be omitted when no normal-launch arguments are needed.'
    }
    $script:DirectStartProcessCalls += [pscustomobject]@{
        FilePath = $FilePath
        ArgumentList = if ($PSBoundParameters.ContainsKey('ArgumentList')) { @($ArgumentList) } else { @() }
        HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
        WorkingDirectory = $WorkingDirectory
    }
}
Start-CodexNormally -AppExe 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe'
Assert-Equal 1 @($script:DirectStartProcessCalls).Count 'Normal launch should invoke Start-Process once.'
Assert-True (-not $script:DirectStartProcessCalls[0].HasArgumentList) 'Normal launch should omit ArgumentList entirely.'
Assert-Equal 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\Codex.exe' $script:DirectStartProcessCalls[0].FilePath 'Normal launch should use the Codex executable path.'
Assert-Equal 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app' $script:DirectStartProcessCalls[0].WorkingDirectory 'Normal launch should use the executable parent directory as the working directory.'

$tmpScopedLaunchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-scoped-launch-test-{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Force -Path $tmpScopedLaunchRoot | Out-Null
$oldLocalAppDataForScopedLaunch = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $tmpScopedLaunchRoot 'LocalAppData'
    $script:StartedProcesses = @()
    $script:StoppedProcesses = @()
    $script:ManagerRegistrations = @()

    $mockAppExe = Join-Path $tmpScopedLaunchRoot 'Codex.exe'
    Set-Content -LiteralPath $mockAppExe -Value 'exe' -Encoding ASCII

    $launcherKeyA = Get-CodexLauncherIdentity -ShortcutPath 'C:\Users\Test\Desktop\Scoped A.lnk'
    $launcherKeyB = Get-CodexLauncherIdentity -ShortcutPath 'C:\Users\Test\Desktop\Scoped B.lnk'
    $profileA = Get-CodexPlusUserDataDirectory -LauncherKey $launcherKeyA
    $profileB = Get-CodexPlusUserDataDirectory -LauncherKey $launcherKeyB

    $script:MockCodexProcesses = @(
        [pscustomobject]@{
            ProcessId = 111
            ExecutablePath = $mockAppExe
            CommandLine = ('"{0}" --remote-debugging-port=18420 --remote-debugging-address=127.0.0.1 --user-data-dir="{1}"' -f $mockAppExe, $profileA)
        },
        [pscustomobject]@{
            ProcessId = 222
            ExecutablePath = $mockAppExe
            CommandLine = ('"{0}" --remote-debugging-port=18421 --remote-debugging-address=127.0.0.1 --user-data-dir="{1}"' -f $mockAppExe, $profileB)
        }
    )

    function Get-CodexInstallInfo {
        [pscustomobject]@{
            PackageFound = $true
            AppExe = $mockAppExe
        }
    }

    function Get-CodexDesktopProcesses {
        @($script:MockCodexProcesses)
    }

    function Stop-Process {
        [CmdletBinding()]
        param(
            [int]$Id,
            [switch]$Force
        )

        $script:StoppedProcesses += $Id
        $script:MockCodexProcesses = @($script:MockCodexProcesses | Where-Object { $_.ProcessId -ne $Id })
    }

    function Start-CodexWithRtlDebug {
        param(
            [string]$AppExe,
            [int]$Port,
            [string]$LauncherKey,
            [int]$WindowTitleOrdinal = 0
        )

        $script:StartedProcesses += [pscustomobject]@{
            AppExe = $AppExe
            Port = $Port
            LauncherKey = $LauncherKey
            WindowTitleOrdinal = $WindowTitleOrdinal
        }
    }

    function Register-CodexPlusManagerInstance {
        param([string]$LauncherKey, [int]$Port, [string]$UserDataDirectory)
        $script:ManagerRegistrations += [pscustomobject]@{ LauncherKey=$LauncherKey; Port=$Port; UserDataDirectory=$UserDataDirectory }
        [pscustomobject]@{ ok=$true }
    }

    function Read-CodexRtlState {
        [pscustomobject]@{
            Port = 18317
        }
    }

    Assert-Equal 18420 (Get-CodexRtlLaunchPort -PreferredPort 18317 -LauncherKey $launcherKeyA) 'Launcher-specific launch should detect the matching current session port.'
    Launch-CodexRtl -LauncherKey $launcherKeyA
    Assert-Equal 0 @($script:StartedProcesses).Count 'Launcher-specific launch should not restart an already-running matching session.'
    Assert-Equal 0 @($script:StoppedProcesses).Count 'Launcher-specific launch should leave the already-running matching session open.'
    Assert-Equal 18420 @($script:ManagerRegistrations)[0].Port 'Launcher-specific launch should register the matching session port with the global manager.'
    Assert-Equal $profileA @($script:ManagerRegistrations)[0].UserDataDirectory 'Manager registration should include the exact scoped profile.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppDataForScopedLaunch
    if (Test-Path -LiteralPath $tmpScopedLaunchRoot) {
        Remove-Item -LiteralPath $tmpScopedLaunchRoot -Recurse -Force
    }
}

$pageTarget = [pscustomobject]@{
    type = 'page'
    url = 'app://codex/webview/index.html'
    title = 'Codex'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/1'
}
$devtoolsTarget = [pscustomobject]@{
    type = 'other'
    url = 'devtools://devtools/bundled/inspector.html'
    title = 'DevTools'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/2'
}
$remoteTarget = [pscustomobject]@{
    type = 'page'
    url = 'https://example.com/'
    title = 'Example'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/3'
}
$codexTitledRemoteTarget = [pscustomobject]@{
    type = 'page'
    url = 'https://docs.example.com/'
    title = 'Codex Documentation'
    webSocketDebuggerUrl = 'ws://127.0.0.1:18317/devtools/page/4'
}
Assert-True (Test-CodexDevToolsTarget -Target $pageTarget) 'Codex app page targets should be accepted.'
Assert-True (-not (Test-CodexDevToolsTarget -Target $devtoolsTarget)) 'Non-page DevTools targets should be rejected.'
Assert-True (-not (Test-CodexDevToolsTarget -Target $remoteTarget)) 'Unrelated web page targets should be rejected.'
Assert-True (-not (Test-CodexDevToolsTarget -Target $codexTitledRemoteTarget)) 'Non-app pages should be rejected even when their title contains Codex.'

$payload = Get-CodexRtlPayload
Assert-True ($payload.Contains('window.__CODEX_RTL_FIX_CODEX')) 'Payload should be idempotent.'
Assert-True ($payload.Contains('classifyDirection')) 'Payload should classify text direction.'
Assert-True ($payload.Contains('RTL_RE')) 'Payload should detect RTL codepoints.'
Assert-True ($payload.Contains('unicodeBidi')) 'Payload should use bidi-safe rendering.'
Assert-True ($payload.Contains('data-codex-rtl-fix')) 'Payload should mark only tool-owned changes.'
Assert-True ($payload.Contains('removeAttribute(''dir'')') -or $payload.Contains('removeAttribute("dir")')) 'Payload should clean stale broad dir attributes.'
Assert-True (-not ($payload -match "querySelectorAll\('\[data-thread-find-target=.*setAttribute\('dir', 'rtl'")) 'Payload should not force the conversation root to RTL.'
Assert-True (-not ($payload.Contains('numberCount > 0 && rtlCount > 0'))) 'Payload should not classify RTL text as mixed-LTR just because it contains numbers.'
Assert-True ($payload.Contains('function getMeaningfulText')) 'Payload should strip diagnostic prefixes before classifying block direction.'
Assert-True ($payload.Contains('function applyBlockDirection')) 'Payload should apply block direction through one helper.'
Assert-True ($payload.Contains('function processInlineTechnicalIslands')) 'Payload should isolate inline technical fragments explicitly.'
Assert-True ($payload.Contains('REQUEST_CARD_SELECTOR')) 'Payload should target native request cards.'
Assert-True ($payload.Contains('REQUEST_CARD_QUESTION_SELECTOR')) 'Request cards should expose a dedicated question selector.'
Assert-True ($payload.Contains('REQUEST_CARD_DESCRIPTION_SELECTOR')) 'Request cards should expose a dedicated option-description selector.'
Assert-True ($payload.Contains('function processRequestCards')) 'Payload should process request-card text direction separately from card layout.'
Assert-True ($payload.Contains('processRequestCards()')) 'Payload should apply RTL handling to request cards.'
Assert-True ($payload.Contains('TOOLTIP_SELECTOR')) 'Payload should target visible tooltips.'
Assert-True ($payload.Contains('function processTooltips')) 'Payload should process tooltip text direction.'
Assert-True ($payload.Contains('processTooltips()')) 'Payload should apply RTL handling to visible tooltips.'
Assert-True ($payload.Contains('function processLists')) 'Payload should process list structure explicitly.'
Assert-True ($payload.Contains('function processBlockquotes')) 'Payload should process blockquote structure explicitly.'
Assert-True ($payload.Contains('function processTables')) 'Payload should process markdown tables explicitly.'
Assert-True ($payload.Contains('processTables(bubble)')) 'Payload should patch tables inside user bubbles.'
Assert-True ($payload.Contains('processTables(root)')) 'Payload should patch tables inside conversation roots.'
Assert-True ($payload.Contains("applyBlockDirection(cell, direction, { forceLtr: tableDirection === 'rtl' })")) 'Payload should align table cells with the detected table direction.'
Assert-True ($payload.Contains('[data-thread-find-target="conversation"]')) 'Payload should keep the existing conversation-root targeting.'
Assert-True ($payload.Contains('span[data-thread-title="true"]')) 'Payload should target verified sidebar thread title spans.'
Assert-True ($payload.Contains('data-app-action-sidebar-project-row')) 'Payload should target verified sidebar project rows.'
Assert-True ($payload.Contains('data-app-action-sidebar-project-label')) 'Payload should target verified sidebar project labels.'
Assert-True ($payload.Contains('app-shell-header-context-menu-surface')) 'Payload should target the app header title surface.'
Assert-True ($payload.Contains('[data-user-message-bubble="true"]')) 'Payload should target verified user message bubbles directly.'
Assert-True ($payload.Contains('div.ProseMirror')) 'Payload should target ProseMirror composers and edit boxes.'
Assert-True ($payload.Contains('textarea')) 'Payload should target standard textareas for auto direction.'
Assert-True ($payload.Contains('[contenteditable="true"]')) 'Payload should keep quoted contenteditable composer support.'
Assert-True ($payload.Contains('[contenteditable=true]')) 'Payload should keep unquoted contenteditable composer support.'
Assert-True ($payload.Contains('ol, ul')) 'Payload should handle ordered and unordered list containers explicitly.'
Assert-True ($payload.Contains('input[type="checkbox"]')) 'Payload should account for task-list checkbox markers.'
Assert-True ($payload.Contains('data-codex-rtl-fix-style')) 'Payload should inject a dedicated stylesheet for technical inline fragments.'
Assert-True ($payload.Contains('unicode-bidi: isolate')) 'Payload stylesheet should isolate inline technical fragments safely.'
Assert-True (-not ($payload.Contains('unicode-bidi: isolate-override !important'))) 'Payload should avoid isolate-override because it flips Hebrew in mixed technical surfaces.'
Assert-True ($payload.Contains('border-left: 0 !important')) 'RTL blockquote styling should explicitly remove Codex left quote border.'
Assert-True ($payload.Contains('border-right: 0.25rem solid currentColor !important')) 'RTL blockquote styling should explicitly add the quote border on the right.'
Assert-True ($payload.Contains('padding-left: 0 !important')) 'RTL blockquote styling should explicitly clear left padding.'
Assert-True ($payload.Contains('padding-right: 1rem !important')) 'RTL blockquote styling should explicitly add right padding.'
foreach ($tableSelector in @('table', 'thead', 'tbody', 'tr', 'th', 'td')) {
    Assert-True ($payload.Contains("'$tableSelector'") -or $payload.Contains('"$tableSelector"')) "Payload skip selector should shield '$tableSelector' elements."
}
$textSelectorsOnly = ($payload -split 'const SKIP_SELECTOR')[0]
Assert-True (-not $textSelectorsOnly.Contains("'td'")) 'Payload text block targeting should not include table cells.'
Assert-True (-not $textSelectorsOnly.Contains("'th'")) 'Payload text block targeting should not include table headers.'
Assert-True ($payload.Contains('MutationObserver')) 'Payload should reapply after React DOM changes.'
Assert-True ($payload.Contains('records.every(mutationIsInsideComposer)')) 'Composer mutations should not rescan the full conversation on every keystroke.'
Assert-True ($payload.Contains("attributeFilter: ['dir', 'contenteditable', 'data-thread-title']")) 'RTL observation should ignore unrelated React attribute churn.'

$splitSelectorPayload = Get-CodexSplitModelEffortSelectorPayload
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-model-button')) 'Split selector should expose a dedicated model button.'
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-effort-button')) 'Split selector should expose a dedicated effort button.'
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-model-menu')) 'Split selector should expose an in-app model menu.'
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-effort-menu')) 'Split selector should expose an in-app effort menu.'
Assert-True ($splitSelectorPayload.Contains('document.body.append(modelMenu, effortMenu)')) 'Split selector menus should escape the transformed composer surface.'
Assert-True (-not ($splitSelectorPayload.Contains('<select'))) 'Split selector should not use a native select picker.'
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-speed-button')) 'Split selector should expose a dedicated speed button.'
Assert-True (-not ($splitSelectorPayload.Contains('data-codex-plus-speed-select'))) 'Speed control should not render a select dropdown.'
Assert-True ($splitSelectorPayload.Contains('serviceTierOptions')) 'Split selector should derive speed options from Codex service tier state.'
Assert-True ($splitSelectorPayload.Contains('onSelectServiceTier(nextTier.nativeValue)')) 'Split selector should use Codex native service tier callback values.'
Assert-True ($splitSelectorPayload.Contains('serviceTierDescription')) 'Speed control should expose the native service tier description.'
Assert-True ($splitSelectorPayload.Contains('speedButton.title = selectedServiceTier.description')) 'Speed control should show the service tier description on hover.'
Assert-True ($splitSelectorPayload.Contains('LIGHTNING_EMPTY')) 'Split selector should render an empty lightning icon for standard speed.'
Assert-True ($splitSelectorPayload.Contains('LIGHTNING_FULL')) 'Split selector should render a full lightning icon for fast speed.'
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-speed-active')) 'Speed control should expose an active-state marker.'
Assert-True ($splitSelectorPayload.Contains('stroke="#facc15"')) 'Fast speed should use a yellow lightning-shaped border.'
Assert-True ($splitSelectorPayload.Contains('supportedReasoningEfforts')) 'Split selector should derive effort options from the selected live model.'
Assert-True ($splitSelectorPayload.Contains('latest.onSelectModel(model.model || model.id, nextEffort)')) 'Split selector should use Codex native model and effort callback arguments.'
Assert-True ($splitSelectorPayload.Contains('latest.onSelectReasoningEffort(value)')) 'Split selector should use Codex native effort callback.'
Assert-True ($splitSelectorPayload.Contains('const CHEVRON')) 'Split selector should render a native-style chevron for each button.'
Assert-True ($splitSelectorPayload.Contains('window.setInterval(schedule, 2000)')) 'Split selector should periodically reconcile native Codex state without polling twice per second.'
Assert-True ($splitSelectorPayload.Contains('records.some(mutationTouchesSelector)')) 'Split selector should ignore mutations outside the model selector surface.'
Assert-True ($splitSelectorPayload.Contains('hideNativeTrigger')) 'Split selector should hide the original Codex model and effort trigger.'
Assert-True ($splitSelectorPayload.Contains('data-codex-plus-native-selector-hidden')) 'Split selector should mark the hidden native trigger for runtime verification.'
Assert-True ($splitSelectorPayload.Contains('role="listbox"')) 'Split selector should expose an in-app listbox menu.'

$projectSelectorGuardPayload = Get-CodexProjectSelectorGuardPayload
Assert-True ($projectSelectorGuardPayload.Contains('data-composer-navigation-target="workspace-project"')) 'Project selector guard should target the native composer project control.'
Assert-True ($projectSelectorGuardPayload.Contains('__CODEX_PLUS_PROJECT_WINDOW_CONTEXT')) 'Project selector guard should use the current project-window context.'
Assert-True ($projectSelectorGuardPayload.Contains('onPointerDown')) 'Project selector guard should open the native project menu through its React control.'
Assert-True ($projectSelectorGuardPayload.Contains('[role="option"],[cmdk-item]')) 'Project selector guard should support Codex project pickers rendered as command-menu options.'
Assert-True ($projectSelectorGuardPayload.Contains('button.click()')) 'Project selector guard should fall back to the native DOM click when React props expose no menu opener.'
Assert-True ($projectSelectorGuardPayload.Contains("dispatchEvent(new MouseEvent('click'")) 'Project selector guard should select the current project through the native menu item.'
Assert-True ($projectSelectorGuardPayload.Contains('data-codex-plus-project-selector-locked')) 'Project selector guard should publish a locked-state marker.'
Assert-True ($projectSelectorGuardPayload.Contains('pointer-events: none')) 'Project selector guard should make the current project control non-clickable.'
Assert-True ($projectSelectorGuardPayload.Contains('aria-label="Choose project"')) 'Project selector guard should identify the empty project state.'
Assert-True ($projectSelectorGuardPayload.Contains('content: "Task"')) 'Project selector guard should visually label the empty project state as Task.'
Assert-True ($projectSelectorGuardPayload.Contains('font-size: 0 !important')) 'Project selector guard should hide the native Choose project text without changing the DOM text.'
Assert-True ($projectSelectorGuardPayload.Contains("installStyle();`n    const context = projectWindowContext();")) 'Project selector guard should keep the Task label style active outside project windows.'
Assert-True ($projectSelectorGuardPayload.Contains('data-clear-project-button')) 'Project selector guard should target the project clear control.'
Assert-True ($projectSelectorGuardPayload.Contains('projectClearedByUser')) 'Project selector guard should remember when the user clears the project to return to a task.'
Assert-True ($projectSelectorGuardPayload.Contains('projectClearedByUser = true')) 'Project selector guard should allow the user to clear the project and keep the composer in Task mode.'
Assert-True ($projectSelectorGuardPayload.Contains('records.some(mutationTouchesGuard)')) 'Project selector guard should ignore unrelated composer and conversation mutations.'
Assert-True (-not ($projectSelectorGuardPayload.Contains('PROJECT_WINDOW_CLEAR_SELECTOR'))) 'Project selector guard should not hide the project clear X.'

$sidebarPagingPayload = Get-CodexSidebarPagingPayload
Assert-True ($sidebarPagingPayload.Contains("key: 'threads'")) 'Sidebar paging should define the synthetic Threads section.'
Assert-True ($sidebarPagingPayload.Contains("title: 'Recents'")) 'Sidebar paging should render a Recents heading.'
Assert-True ($sidebarPagingPayload.Contains('renameNativeRecentsHeading')) 'Sidebar paging should rename Codex''s native Recents heading to Tasks.'
Assert-True ($sidebarPagingPayload.Contains('element.closest(syntheticSectionSelector)')) 'Native Recents relabeling should skip the synthetic Recents section.'
Assert-True ($sidebarPagingPayload.Contains("minVisibleCount: 3")) 'Sidebar paging should keep at least three thread rows visible by default.'
Assert-True ($sidebarPagingPayload.Contains('getProjectTimestampMsForRow')) 'Sidebar paging should resolve project timestamps from live state.'
Assert-True ($sidebarPagingPayload.Contains('getProjectGroupTimestampMs')) 'Sidebar paging should centralize project metadata timestamp resolution.'
Assert-True ($sidebarPagingPayload.Contains('projectUpdatedAt')) 'Sidebar paging should read local project modification metadata.'
Assert-True ($sidebarPagingPayload.Contains('projectCreatedAt')) 'Sidebar paging should retain a local project creation fallback.'
Assert-True ($sidebarPagingPayload.Contains('isNativeSidebarPagerRow')) 'Sidebar paging should keep Codex''s native project pager out of the sortable row set.'
Assert-True ($sidebarPagingPayload.Contains('expandNativeProjectPager')) 'Sidebar paging should expand the native project list before sorting newly mounted projects.'
Assert-True ($sidebarPagingPayload.Contains('NATIVE_PROJECT_PAGER_MAX_EXPANSIONS')) 'Native project pagination should have a bounded expansion guard.'
Assert-True ($sidebarPagingPayload.Contains('sortSidebarRowsByRenderedTimestamp')) 'Sidebar paging should perform a final sort from the timestamps rendered on each project row.'
Assert-True ($sidebarPagingPayload.Contains('STARTUP_SORT_RETRY_DELAYS_MS')) 'Sidebar paging should retry project sorting while startup rows settle.'
Assert-True ($sidebarPagingPayload.Contains('window.setTimeout(schedule, delayMs)')) 'Startup project sorting retries should use the normal debounced reconciliation path.'
Assert-True ($sidebarPagingPayload.Contains('getReconciliationValue')) 'Sidebar paging should reuse expensive live catalog projections during one reconciliation.'
Assert-True ($sidebarPagingPayload.Contains("getReconciliationValue('recentThreadEntries'")) 'Sidebar paging should compute recent thread entries only once per reconciliation.'
Assert-True ($sidebarPagingPayload.Contains('getReconciliationRowValue')) 'Sidebar paging should cache repeated row metadata lookups during sorting and rendering.'
Assert-True ($sidebarPagingPayload.Contains('existingRowsByThreadId')) 'Synthetic Recents should index existing rows before rebuilding the live catalog view.'
Assert-True ($sidebarPagingPayload.Contains('existingRow || createSyntheticThreadRow')) 'Synthetic Recents should clone a native row only for a genuinely new thread.'
Assert-True ($sidebarPagingPayload.Contains("getReconciliationValue('liveSidebarCatalog'")) 'Sidebar paging should reuse one live catalog snapshot throughout a reconciliation.'
Assert-True ($sidebarPagingPayload.Contains('dirtyLiveCatalogBindings.add(binding)')) 'Live store subscriptions should invalidate only the binding that changed.'
Assert-True ($sidebarPagingPayload.Contains('refreshLiveThreadBinding(scope, binding)')) 'Sidebar refreshes should update dirty bindings incrementally instead of rescanning the entire store.'
Assert-True ($sidebarPagingPayload.Contains('LIVE_CATALOG_FULL_REFRESH_MS = 30000')) 'Full live catalog scans should be a low-frequency safety fallback.'
Assert-True ($sidebarPagingPayload.Contains('getRemoteProjectTimestampMsForRow')) 'Sidebar paging should fall back to remote project timestamps from React props.'
Assert-True ($sidebarPagingPayload.Contains('cloudEnvironment')) 'Sidebar paging should read the remote project cloud environment metadata.'
Assert-True ($sidebarPagingPayload.Contains("const titleElement = row.querySelector('[data-thread-title=""true""], .text-fade-truncate');")) 'Sidebar timestamps should target the inline title element, not the native row wrapper.'
Assert-True ($sidebarPagingPayload.Contains('timestampElement.parentElement !== titleHost')) 'Sidebar timestamps should be moved into the title flex row when a stale node already exists.'
Assert-True ($sidebarPagingPayload.Contains('sectionList.insertBefore(row, pager)')) 'Sidebar sorting should reorder the actual DOM rows before the pager.'
Assert-True ($sidebarPagingPayload.Contains('sortUnmanagedSidebarLists')) 'Sidebar sorting should cover lists outside the primary Projects and Tasks sections.'
Assert-True ($sidebarPagingPayload.Contains('hover:bg-token-list-hover-background')) 'Synthetic Threads fallback rows should keep hover styling.'
Assert-True ($sidebarPagingPayload.Contains('[data-app-action-sidebar-project-row]:hover { background-color: transparent !important; }')) 'Project names should not show a hover background.'
Assert-True ($sidebarPagingPayload.Contains('[data-radix-popper-content-wrapper]:has([class*="project-hover-card-row"])')) 'Project hover cards should remain suppressed across their popper wrapper.'
Assert-True ($sidebarPagingPayload.Contains('displayTitle')) 'Synthetic Threads labels should come from the live catalog display title.'
Assert-True ($sidebarPagingPayload.Contains("return title + ' (task)'")) 'Synthetic task threads should show a task suffix after the title.'
Assert-True ($sidebarPagingPayload.Contains("return title + ' (' + projectTitle + ')'")) 'Synthetic project threads should show the project name after the title.'
Assert-True ($sidebarPagingPayload.Contains('getNativePinnedThreadIds')) 'Synthetic Recents should read pinned state from native thread rows.'
Assert-True ($sidebarPagingPayload.Contains('[data-app-action-sidebar-thread-pinned="true"]')) 'Pinned detection should query Codex''s explicit pinned marker.'
Assert-True ($sidebarPagingPayload.Contains('const isPinned = nativePinnedThreadIds.has(id);')) 'Synthetic Recents should resolve native pinned state for each thread.'
Assert-True ($sidebarPagingPayload.Contains('if (isPinned) continue;')) 'Pinned threads should be excluded from synthetic Recents.'
Assert-True ($sidebarPagingPayload.Contains('const entriesByThreadId = new Map();')) 'Synthetic Recents should deduplicate catalog records by thread id.'
Assert-True ($sidebarPagingPayload.Contains("kind === 'project' && existing.kind === 'task'")) 'Project classification should win when one thread is reported as both project and task.'
Assert-True ($sidebarPagingPayload.Contains('Array.from(entriesByThreadId.values())')) 'Synthetic Recents should render the deduplicated thread entries.'
Assert-True ($sidebarPagingPayload.Contains('projectGroupByThreadId')) 'Synthetic Recents should index project ownership by normalized thread id before classifying entries.'
Assert-True ($sidebarPagingPayload.Contains('projectGroupByThreadId.get(id) || getProjectGroupForThreadKey')) 'Synthetic Recents should prefer the normalized project ownership index.'
Assert-True ($sidebarPagingPayload.Contains("if (projectWindowContext) return title")) 'Project-window thread labels should omit the project suffix without adding a task suffix.'
Assert-True ($sidebarPagingPayload.Contains('getProjectWindowContext')) 'Sidebar paging should detect project-window context.'
Assert-True ($sidebarPagingPayload.Contains('codexPlusProjectId')) 'Sidebar paging should read the project id from the startup URL.'
Assert-True ($sidebarPagingPayload.Contains('PAGE_START_TIME')) 'Project windows should distinguish the newly created page from the existing main page.'
Assert-True ($sidebarPagingPayload.Contains('tryClaimPendingProjectWindowContext')) 'Project windows should retry the shared context claim after startup.'
Assert-True ($sidebarPagingPayload.Contains('adoptProjectWindowContext')) 'Project windows should apply project metadata when the handoff becomes visible.'
Assert-True ($sidebarPagingPayload.Contains("kind !== 'project'")) 'Project windows should exclude projectless task threads.'
Assert-True ($sidebarPagingPayload.Contains('normalizeProjectId(projectGroup?.projectId || cwd) !== normalizeProjectId(projectWindowContext.id)')) 'Project windows should filter threads to the selected project.'
Assert-True ($sidebarPagingPayload.Contains("get('initialRoute')")) 'Sidebar paging should read encoded startup routes.'
Assert-True ($sidebarPagingPayload.Contains("homeUrl.searchParams.set('initialRoute', '/')")) 'Project windows should normalize their carrier route back to the home route.'
Assert-True ($sidebarPagingPayload.Contains('__CODEX_PLUS_PROJECT_WINDOW_CONTEXT')) 'Project context should remain available to the menu action after route normalization.'
Assert-True ($sidebarPagingPayload.Contains('reinforceProjectWindowMetadata')) 'Project-window metadata should remain visible to native title synchronization.'
Assert-True ($sidebarPagingPayload.Contains('codexPlusPendingProjectWindows')) 'Project windows should claim queued context from the shared Plus session.'
Assert-True ($sidebarPagingPayload.Contains("'Recents (' + projectWindowContext.name + ')'")) 'Project windows should name the synthetic section Recents with the project name.'
Assert-True ($sidebarPagingPayload.Contains("spec.key === 'projects'")) 'Project windows should hide the native Projects section.'
Assert-True ($sidebarPagingPayload.Contains("recentThreadEntries.length === 0 && !projectWindowContext")) 'Project windows should keep their named Threads section when the project has no threads.'
Assert-True ($sidebarPagingPayload.Contains('data-codex-plus-thread-id')) 'Synthetic Threads rows should retain the source thread id for click proxying.'
Assert-True ($sidebarPagingPayload.Contains('return Array.from(entriesByThreadId.values())')) 'Synthetic Threads should mirror the full live thread catalog without a recent-items cap.'
Assert-True ($sidebarPagingPayload.Contains('data-app-action-sidebar-thread-title')) 'Synthetic Threads should target the live Codex thread title element.'
Assert-True ($sidebarPagingPayload.Contains("data-codex-plus-sidebar-synthetic-section")) 'Sidebar paging should mark synthetic sections explicitly.'
Assert-True ($sidebarPagingPayload.Contains("data-codex-plus-sidebar-synthetic-list")) 'Synthetic Threads should mark their list so source lookups can skip it.'
Assert-True ($sidebarPagingPayload.Contains("data-codex-plus-source-list-label")) 'Synthetic Threads rows should preserve their source list label for click proxying.'
Assert-True ($sidebarPagingPayload.Contains('entry.sourceRowText || entry.title')) 'Synthetic thread labels should not replace the native source title used for click proxying.'
Assert-True ($sidebarPagingPayload.Contains('isPlaceholderThreadTitle')) 'Synthetic thread labels should recognize stale New chat/New task placeholders.'
Assert-True ($sidebarPagingPayload.Contains('isWorkingThreadStatus(record.threadRuntimeStatus)')) 'Synthetic thread labels should prefer the live conversation title while a thread is running.'
Assert-True ($sidebarPagingPayload.Contains('syncThreadToggleButton(headerButton, sectionContainer.hidden, threadsHeadingLabel);')) 'Project-window headers should resync their visible title after late context adoption.'
Assert-True ($sidebarPagingPayload.Contains('findSourceRowInList')) 'Synthetic Threads should auto-expand paged lists before proxying clicks.'
Assert-True ($sidebarPagingPayload.Contains('data-codex-plus-thread-navigation-pending')) 'Synthetic Threads should suppress duplicate navigation while a collapsed source section is being opened.'
Assert-True ($sidebarPagingPayload.Contains('getAppScopeFromSidebar')) 'Synthetic Threads should locate Codex''s mounted React app scope for direct navigation.'
Assert-True (-not $sidebarPagingPayload.Contains('getInternalNavigationModules')) 'Synthetic navigation should not wait for Codex private module imports.'
Assert-True (-not $sidebarPagingPayload.Contains('await import(')) 'Synthetic navigation and preloading should use mounted managers instead of importing the private app bundle.'
Assert-True ($sidebarPagingPayload.Contains('activateThreadSummary')) 'Synthetic Threads should activate an unloaded native thread summary before navigation.'
Assert-True ($sidebarPagingPayload.Contains('getReactRouterNavigatorFromSidebar')) 'Synthetic Threads should locate Codex''s internal React Router navigator.'
Assert-True ($sidebarPagingPayload.Contains("routerNavigator.push('/local/' + threadId)")) 'Synthetic Threads should navigate the main Codex view to the selected local thread.'
Assert-True ($sidebarPagingPayload.Contains('const manager = getThreadHydrationManager(scope)')) 'Synthetic navigation should use the mounted full manager without private module discovery.'
Assert-True ($sidebarPagingPayload.Contains('getReactThreadStatusState')) 'Synthetic Threads should read thread status from the native row React fiber.'
Assert-True ($sidebarPagingPayload.Contains('getReactFiberCandidates')) 'Synthetic Threads should inspect all live React fibers in a native row.'
Assert-True ($sidebarPagingPayload.Contains('getNativeThreadRows')) 'Synthetic Threads should discover native rows from the live sidebar DOM.'
Assert-True ($sidebarPagingPayload.Contains('data-codex-plus-thread-navigation-overlay')) 'Thread navigation should expose a dedicated main-surface loading overlay.'
Assert-True ($sidebarPagingPayload.Contains("setStatus('- Loading thread')")) 'Thread loading should publish its status to the badge.'
Assert-True (-not $sidebarPagingPayload.Contains('warmStartupThreadNavigation')) 'Startup should not import Codex private modules while the app module graph is still evaluating.'
Assert-True ($sidebarPagingPayload.Contains("window.addEventListener('load', beginStartupPreload")) 'Startup preloading should wait for the full app load event.'
Assert-True ($sidebarPagingPayload.Contains('THREAD_PRELOAD_START_DELAY_MS = 500')) 'Startup preloading should leave a short settling interval after full load.'
Assert-True ($sidebarPagingPayload.Contains('startupThreadPreloadPromises')) 'Startup should preload visible synthetic threads.'
Assert-True ($sidebarPagingPayload.Contains('THREAD_PRELOAD_SPINNER_ATTR')) 'Synthetic threads should show a loading indicator during preload.'
Assert-True ($sidebarPagingPayload.Contains('THREAD_PRELOAD_COMPLETE_ATTR')) 'Synthetic threads should retain a completed indicator after preload.'
Assert-True ($sidebarPagingPayload.Contains('positionSyntheticPreloadIndicator')) 'Preload indicators should be positioned on the left side of synthetic threads.'
Assert-True ($sidebarPagingPayload.Contains("indicator.style.left = '0px'")) 'Preload indicators should remain inside the visible row bounds.'
Assert-True ($sidebarPagingPayload.Contains("button.classList.add('pl-2')")) 'Synthetic thread rows should match the project-thread text inset without moving the preload indicator.'
Assert-True ($sidebarPagingPayload.Contains("button.style.paddingLeft = '8px'")) 'Synthetic thread rows should apply the small project-thread text inset explicitly.'
Assert-True ($sidebarPagingPayload.Contains("element.classList.contains('w-4')")) 'Synthetic thread rows should remove the inherited project-thread icon slot.'
Assert-True ($sidebarPagingPayload.Contains("titleElement.style.direction = 'ltr'")) 'Synthetic Recents titles should keep a stable visual starting edge across languages.'
Assert-True ($sidebarPagingPayload.Contains("titleElement.style.textAlign = 'left'")) 'Synthetic Recents titles should not inherit per-language right alignment.'
Assert-True ($sidebarPagingPayload.Contains("titleHost.style.paddingLeft = '24px'")) 'Synthetic Recents titles should reserve a fixed left inset for status indicators.'
Assert-True ($sidebarPagingPayload.Contains('applySyntheticThreadIndent(row);')) 'Synthetic thread rows should normalize the inset when existing rows are reused.'
Assert-True ($sidebarPagingPayload.Contains("aria-label', 'Preloading thread'")) 'Preload loading indicators should be accessible.'
Assert-True ($sidebarPagingPayload.Contains("aria-label', 'Thread preloaded'")) 'Preload completion indicators should be accessible.'
Assert-True ($sidebarPagingPayload.Contains('if (svg) svg.replaceWith(check)')) 'The preload check should replace the spinner graphic in the same centered slot.'
Assert-True (-not $sidebarPagingPayload.Contains('if (svg) svg.replaceChildren()')) 'The preload check should not retain an empty spinner SVG that shifts it toward the title.'
Assert-True ($sidebarPagingPayload.Contains('startupThreadPreloadCompletedIds.add(threadId)')) 'Each thread should transition to the completed indicator after preload.'
Assert-True ($sidebarPagingPayload.Contains("hydrationManager.hydrateBackgroundThreads([threadId], { includeTurns: true })")) 'Startup preloading should hydrate complete turns through Codex''s canonical background path.'
Assert-True (-not $sidebarPagingPayload.Contains('installThreadPreloadReadCache')) 'Startup preloading should not monkey-patch readThread and risk a self-referential hydration wait.'
Assert-True (-not $sidebarPagingPayload.Contains('startupThreadOriginalReadThread')) 'Startup preloading should leave Codex''s readThread method intact.'
Assert-True ($sidebarPagingPayload.Contains('startupThreadPreloadCompletedIds.has(threadId)')) 'Only fully hydrated synthetic preloads should bypass the redundant thread-loading overlay.'
Assert-True (-not $sidebarPagingPayload.Contains('getThreadResumeFunction')) 'Startup preloading should not depend on a private resume helper.'
Assert-True ($sidebarPagingPayload.Contains('getThreadHydrationManager')) 'Startup preloading should resolve the full app-server manager required for conversation hydration.'
Assert-True ($sidebarPagingPayload.Contains("typeof candidate.hydrateBackgroundThreads === 'function'")) 'The preload manager should expose Codex''s canonical background hydration path.'
Assert-True ($sidebarPagingPayload.Contains('typeof candidate.getThreadWorkspaceState')) 'The preload manager should be distinguished from the lightweight sidebar conversation manager.'
Assert-True ($sidebarPagingPayload.Contains('const hydratedTurns = hydratedConversation?.turns')) 'Preload completion should validate the conversation store consumed by the thread view.'
Assert-True ($sidebarPagingPayload.Contains('hydratedItemCount === 0')) 'Preload completion should reject empty placeholder turns.'
Assert-True ($sidebarPagingPayload.Contains('threadTurnCounts')) 'Live preload diagnostics should report hydrated turn counts.'
Assert-True ($sidebarPagingPayload.Contains('threadItemCounts')) 'Live preload diagnostics should report hydrated item counts.'
Assert-True (-not $sidebarPagingPayload.Contains('THREAD_PRELOAD_MIN_DISPLAY_MS')) 'Preload completion should not wait on renderer timers that may be throttled in background windows.'
Assert-True ($sidebarPagingPayload.Contains('THREAD_PRELOAD_TIMEOUT_MS = 15000')) 'Thread preloading should have a finite deadline.'
Assert-True ($sidebarPagingPayload.Contains('withThreadPreloadTimeout')) 'Background hydration operations should be bounded so their indicators cannot remain forever.'
Assert-True ($sidebarPagingPayload.Contains('preload: startupThreadPreloadState')) 'Live preload phase diagnostics should be exposed for verification.'
Assert-True ($sidebarPagingPayload.Contains('startupThreadPreloadFailedIds')) 'Failed preload attempts should not be retried on every sidebar refresh.'
Assert-True ($sidebarPagingPayload.Contains('threadId !== activeThreadId')) 'Startup preloading should skip the task that is already open.'
Assert-True ($sidebarPagingPayload.Contains('!workingThreadIds.has(threadId)')) 'Startup preloading should skip tasks that are currently working.'
Assert-True ($sidebarPagingPayload.Contains('syncStartupThreadPreloadIndicators')) 'Preload indicators should survive synthetic row rerenders.'
Assert-True ($sidebarPagingPayload.Contains('window.setTimeout(preloadStartupThreads, 0);')) 'Every synthetic-list refresh should preload newly visible threads, including rows revealed by Show more.'
Assert-True ($sidebarPagingPayload.Contains('!startupThreadPreloadCompletedIds.has(threadId)')) 'Incremental preloading should skip threads whose canonical history is already ready.'
Assert-True ($sidebarPagingPayload.Contains('!startupThreadPreloadActiveIds.has(threadId)')) 'Incremental preloading should not duplicate an active preload.'
Assert-True ($sidebarPagingPayload.Contains('for (const threadId of threadIds)')) 'Startup thread reads should run sequentially because Codex serializes thread/read work.'
Assert-True (-not $sidebarPagingPayload.Contains('Promise.all(threadIds.map')) 'Startup thread reads should not be launched as a competing parallel batch.'
Assert-True ($sidebarPagingPayload.Contains("if (sectionKey === 'threads') window.setTimeout(preloadStartupThreads, 0);")) 'The Threads Show more action should immediately preload newly revealed rows.'
Assert-True ($sidebarPagingPayload.Contains('createThreadNavigationOverlay')) 'Thread navigation should render the spinner in the main conversation area.'
Assert-True ($sidebarPagingPayload.Contains('startThreadNavigationLoadingMonitor')) 'Thread navigation should monitor native and synthetic thread activation.'
Assert-True ($sidebarPagingPayload.Contains('isThreadNavigationReady')) 'Thread navigation should remove the spinner after the target conversation renders.'
Assert-True ($sidebarPagingPayload.Contains('conversationText.length > 0')) 'Thread navigation should keep the spinner visible while the replacement conversation is still empty.'
Assert-True ($sidebarPagingPayload.Contains('THREAD_NAVIGATION_MIN_DISPLAY_MS')) 'Thread navigation should keep the spinner visible long enough to be noticed.'
Assert-True ($sidebarPagingPayload.Contains('SIDEBAR_POLL_INTERVAL_MS = 30000')) 'Sidebar fallback polling should stay infrequent because live store subscriptions drive normal updates.'
Assert-True ($sidebarPagingPayload.Contains('USER_ACTIVITY_SETTLE_MS = 500')) 'Sidebar reconciliation should wait until typing and scrolling have settled.'
Assert-True ($sidebarPagingPayload.Contains("['beforeinput', 'keydown', 'wheel', 'touchmove', 'scroll']")) 'Sidebar reconciliation should track the user interactions that are sensitive to main-thread jank.'
Assert-True ($sidebarPagingPayload.Contains('activityAge < USER_ACTIVITY_SETTLE_MS')) 'A scheduled sidebar refresh should defer while the user is actively typing or scrolling.'
Assert-True ($sidebarPagingPayload.Contains('if (threadNavigationState)')) 'Sidebar reconciliation should wait until an in-progress thread navigation has rendered.'
Assert-True ($sidebarPagingPayload.Contains('SIDEBAR_NAVIGATION_REFRESH_RETRY_MS')) 'Deferred sidebar reconciliation should retry after navigation without blocking the conversation render.'
Assert-True ($sidebarPagingPayload.Contains('authoritativeUnread')) 'Synthetic unread state should prefer the current native or live read state over stale indicators.'
Assert-True ($sidebarPagingPayload.Contains('unreadStateKnown')) 'Live thread records should preserve whether unread state was explicitly reported.'
Assert-True ($sidebarPagingPayload.Contains('if (authoritativeUnread === false)')) 'Synthetic unread indicators should be removed when the source thread is explicitly read.'
Assert-True ($sidebarPagingPayload.Contains('getWorkingThreadIds')) 'Synthetic Threads should collect working native thread ids from React state.'
Assert-True ($sidebarPagingPayload.Contains('getLiveSidebarCatalog(true)')) 'Synthetic Threads should force-refresh live working state when source lists are collapsed.'
Assert-True ($sidebarPagingPayload.Contains("statusState?.type === 'loading'")) 'Synthetic Threads should use Codex''s loading status for the working spinner.'
Assert-True ($sidebarPagingPayload.Contains('data-codex-plus-thread-working')) 'Synthetic Threads should publish working state separately from active selection state.'
Assert-True ($sidebarPagingPayload.Contains('data-codex-plus-thread-spinner')) 'Synthetic Threads should render a loading spinner for working threads.'
Assert-True ($sidebarPagingPayload.Contains('animate-spin')) 'Synthetic Threads should use Codex''s animated spinner styling.'
Assert-True ($sidebarPagingPayload.Contains('window.setInterval(schedule, SIDEBAR_POLL_INTERVAL_MS)')) 'Synthetic Threads should retain a low-frequency fallback poll while source lists are collapsed.'
Assert-True ($sidebarPagingPayload.Contains('getSyntheticThreadButton')) 'Synthetic Threads should anchor the spinner to the inner thread row.'
Assert-True ($sidebarPagingPayload.Contains('syncThreadSpinner')) 'Synthetic Threads should synchronize native and synthetic working-row spinners.'
Assert-True ($sidebarPagingPayload.Contains('threadRuntimeStatus')) 'Synthetic Threads should read live runtime status when a project source row is collapsed.'
Assert-True ($sidebarPagingPayload.Contains("status?.type === 'loading' || status?.type === 'active'")) 'Synthetic Threads should treat Codex active runtime state as working when a project source row is collapsed.'
Assert-True ($sidebarPagingPayload.Contains('hasUnreadTurn')) 'Synthetic Threads should read live unread state when a project source row is collapsed.'
Assert-True ($sidebarPagingPayload.Contains('recentConversations')) 'Synthetic Threads should collect unread state from Codex''s nested conversation manager.'
Assert-True ($sidebarPagingPayload.Contains('conversations instanceof Map')) 'Synthetic Threads should collect live conversations from Codex''s conversation map.'
Assert-True ($sidebarPagingPayload.Contains('nativeThreadUnreadIndicatorCache')) 'Synthetic Threads should retain native unread indicators across collapsed project rows.'
Assert-True ($sidebarPagingPayload.Contains('nativeThreadUnreadStateCache')) 'Synthetic Threads should retain native unread state across collapsed project rows.'
Assert-True ($sidebarPagingPayload.Contains("candidate.closest('[data-app-action-sidebar-thread-row]') || candidate")) 'Nested project threads should preserve their own native row instead of collapsing to the project list item.'
Assert-True ($sidebarPagingPayload.Contains('unreadStatePriority')) 'Synthetic unread state should retain the source priority used to resolve duplicate thread records.'
Assert-True ($sidebarPagingPayload.Contains('currentUnreadPriority')) 'Synthetic unread state should compare collection-backed and manager-backed duplicate records.'
Assert-True ($sidebarPagingPayload.Contains('collection-backed')) 'Synthetic unread state should prefer current thread collections over stale manager records.'
Assert-True ($sidebarPagingPayload.Contains('stale hasUnreadTurn=true')) 'Synthetic unread state should identify stale manager unread flags.'
Assert-True ($sidebarPagingPayload.Contains('subscribeToLiveThreadBindings')) 'Synthetic unread state should subscribe to Codex live thread binding changes.'
Assert-True ($sidebarPagingPayload.Contains('store.sub')) 'Synthetic unread state should use Codex store subscriptions for cross-view updates.'
Assert-True ($sidebarPagingPayload.Contains('requestSidebarRefresh = schedule')) 'Codex live thread changes should schedule a synthetic sidebar refresh.'
Assert-True ($sidebarPagingPayload.Contains('var(--vscode-textLink-foreground)')) 'Synthetic unread indicators should use Codex''s blue unread color.'
Assert-True ($sidebarPagingPayload.Contains('absolute right-0 top-0')) 'Synthetic unread indicators should use the native right-side status slot.'
Assert-True ($sidebarPagingPayload.Contains('keepSyntheticUnreadIndicatorVisible')) 'Synthetic unread indicators should remain visible while hovering a thread.'
Assert-True ($sidebarPagingPayload.Contains('nativeThreadWorkingCache')) 'Synthetic Threads should retain native working state across collapsed project rows.'
Assert-True ($sidebarPagingPayload.Contains('getNativeThreadTitleMap')) 'Synthetic Threads should prefer titles from the live native sidebar rows.'
Assert-True ($sidebarPagingPayload.Contains('nativeThreadTitleCache')) 'Synthetic Threads should retain verified native titles across project-list remounts.'
Assert-True ($sidebarPagingPayload.Contains('getProjectGroupForThreadKey')) 'Synthetic Threads should preserve project origin from live project groups.'
Assert-True ($sidebarPagingPayload.Contains('removeSyntheticThreadActions')) 'Synthetic Threads should omit native pin and archive hover actions.'
Assert-True ($sidebarPagingPayload.Contains('group-hover:min-w-12')) 'Synthetic Threads should remove the native hover action layout that shifts timestamps.'
Assert-True ($sidebarPagingPayload.Contains('expandSourceProject')) 'Synthetic Threads should open a collapsed project source section before proxying a click.'
Assert-True ($sidebarPagingPayload.Contains('waitForSourceRow')) 'Synthetic Threads should wait for a source row after opening a collapsed project source section.'
Assert-True ($sidebarPagingPayload.Contains("replace(/^(?:local|remote):/, '')")) 'Synthetic Threads should match state database thread ids with native host-prefixed sidebar ids.'
Assert-True (-not ($sidebarPagingPayload.Contains('sourceRow.hidden || sourceRow.getClientRects().length === 0'))) 'Synthetic Threads should click source rows even when their native row is hidden or has no layout rect.'
Assert-True ($sidebarPagingPayload.Contains('data-codex-plus-sidebar-action')) 'Synthetic Threads should expose a dedicated collapse action for the header toggle.'
Assert-True ($sidebarPagingPayload.Contains('group/section-toggle')) 'Synthetic Threads should reuse the project-style section toggle button.'
Assert-True ($sidebarPagingPayload.Contains('aria-expanded')) 'Synthetic Threads toggle should publish its open/closed state.'
Assert-True (-not ($sidebarPagingPayload.Contains('data-codex-plus-thread-timestamp-suffix'))) 'Sidebar paging should keep modified times inline instead of a separate suffix span.'

$payloadBundle = Get-CodexPlusPayloadBundle
Assert-True (-not ($payloadBundle.Contains('__CODEX_PLUS_WINDOW_TITLE'))) 'Injected payload bundle should not rewrite the webview title for taskbar labeling.'
Assert-True ($payloadBundle.Contains('__CODEX_RTL_SHARED_HELPERS')) 'Injected payload bundle should include the shared bidi helper payload.'
Assert-True ($payloadBundle.Contains('data-codex-plus-new-chat-button')) 'Injected payload bundle should include the dedicated composer new-chat payload.'
Assert-True ($payloadBundle.Contains('__CODEX_PLUS_SPLIT_MODEL_EFFORT_SELECTOR')) 'Injected payload bundle should include the split model and effort selectors.'
Assert-True ($payloadBundle.Contains('__CODEX_PLUS_PROJECT_SELECTOR_GUARD')) 'Injected payload bundle should include the project selector guard.'
$newChatPayload = Get-CodexNewChatButtonPayload
Assert-True ($newChatPayload.Contains('data-codex-plus-new-chat-button')) 'Composer footer should expose a dedicated new-chat action.'
Assert-True ($newChatPayload.Contains('data-codex-plus-commit-push-button')) 'Composer utility row should expose a dedicated commit-or-push action.'
Assert-True ($newChatPayload.Contains("const COMMIT_PUSH_LABEL = 'Commit or push'")) 'Commit-or-push action should use the native panel label.'
Assert-True ($newChatPayload.Contains('findVisibleCommitPushButton')) 'Commit-or-push action should proxy the visible native summary-panel button.'
Assert-True ($newChatPayload.Contains('triggerCommitOrPush')) 'Commit-or-push action should open the panel and invoke the native action.'
Assert-True ($newChatPayload.Contains('installCommitPushButton')) 'Commit-or-push action should be installed in the composer utility row.'
Assert-True ($newChatPayload.Contains('wirePersistentCommitPushButton')) 'Persistent composer rows should keep the commit-or-push action active.'
Assert-True ($newChatPayload.Contains('normalizeText(currentProjectName())')) 'Commit-or-push action should remain scoped to project composers.'
Assert-True ($newChatPayload.Contains("button.style.marginInlineStart = 'auto'")) 'Commit-or-push action should align itself to the right edge of the composer utility row.'
Assert-True ($newChatPayload.Contains('isCommitPushButtonAvailable')) 'Commit-or-push action should read the native disabled state before allowing activation.'
Assert-True ($newChatPayload.Contains('button.disabled = disabled')) 'Composer commit-or-push action should mirror the native disabled state.'
Assert-True ($newChatPayload.Contains("attributeFilter: ['disabled', 'aria-disabled', 'class']")) 'Commit-or-push availability should react to native state mutations.'
Assert-True ($newChatPayload.Contains('observeNativeCommitPushButton')) 'Commit-or-push availability should observe the native action instead of polling it.'
Assert-True ($newChatPayload.Contains('syncCommitPushAvailability')) 'Commit-or-push availability should synchronize composer copies after native mutations.'
Assert-True ($newChatPayload.Contains('div.col-start-1.row-start-2')) 'New chat button should still locate the composer access cell to hide the native control.'
Assert-True ($newChatPayload.Contains('findComposerAccessRow')) 'New chat button should locate the composer access row before hiding the native control.'
Assert-True ($newChatPayload.Contains('findComposerUtilityBarRow')) 'Composer new-chat button should locate the utility row before inserting the action.'
Assert-True ($newChatPayload.Contains('findComposerUtilityBarAnchor')) 'Composer new-chat button should identify the main chip anchor before placement.'
Assert-True ($newChatPayload.Contains("normalizeText(candidate.textContent) === 'main'")) 'Composer new-chat button should anchor itself after the main branch chip.'
Assert-True ($newChatPayload.Contains('hideNativeComposerNewChatButton')) 'Composer access row should hide the native + new-chat control when present.'
Assert-True ($newChatPayload.Contains('nativeButton.hidden = true')) 'Native + new-chat control should be hidden once the icon button is installed.'
Assert-True ($newChatPayload.Contains('createNewChatIcon')) 'Composer new-chat button should reuse the native icon styling.'
Assert-True ($newChatPayload.Contains('button.appendChild(icon)')) 'Composer new-chat button should render the icon before the label.'
Assert-True ($newChatPayload.Contains("button.title = 'Start a new chat'")) 'Composer new-chat button should present a descriptive tooltip.'
Assert-True ($newChatPayload.Contains("label.textContent = 'New chat'")) 'Composer new-chat button should render the visible label.'
Assert-True ($newChatPayload.Contains('text-token-text-primary')) 'Composer new-chat button should appear as an enabled, colored action.'
Assert-True ($newChatPayload.Contains('placeNewChatButton')) 'Composer new-chat button should centralize placement after the main chip.'
Assert-True ($newChatPayload.Contains('row.insertBefore(button, anchor.nextSibling)')) 'Composer new-chat button should be inserted after the main branch chip.'
Assert-True ($newChatPayload.Contains('triggerNewChat')) 'Composer new-chat button should proxy the native sidebar new-chat action.'
Assert-True ($newChatPayload.Contains('captureCurrentChatContext')) 'Composer new-chat button should snapshot the current project and selector state before opening a blank chat.'
Assert-True ($newChatPayload.Contains('restorePendingNewChatContext')) 'Composer new-chat button should replay the saved chat context after the native new chat opens.'
Assert-True ($newChatPayload.Contains('data-codex-plus-persistent-composer-utility-bar')) 'Composer context row should expose a dedicated marker after the native row is removed.'
Assert-True ($newChatPayload.Contains('data-composer-utility-bar-scroll-area')) 'Composer context persistence should capture the native utility bar before the first message hides it.'
Assert-True ($newChatPayload.Contains('data-above-composer-conversation-id')) 'Composer context persistence should key captured utility bars to the created conversation.'
Assert-True ($newChatPayload.Contains('codex-plus-composer-utility-bars-v2')) 'Composer context persistence should use a new storage version after changing snapshot structure.'
Assert-True ($newChatPayload.Contains('createPersistentUtilityBarSnapshot')) 'Composer context persistence should clone the native row without moving React-owned nodes.'
Assert-True ($newChatPayload.Contains('isComposerUtilityBarReady')) 'Composer context persistence should wait for the native utility row to finish rendering before cloning it.'
Assert-True ($newChatPayload.Contains('getComposerUtilityBarSignature')) 'Composer context persistence should detect changes while the native utility row is still assembling.'
Assert-True ($newChatPayload.Contains('persistentSnapshotStableSince')) 'Composer context persistence should wait for the native utility row to remain stable before cloning it.'
Assert-True ($newChatPayload.Contains('run-location')) 'Composer context persistence should include the native Local location control before caching the row.'
Assert-True ($newChatPayload.Contains('retryPersistentUtilityBarSnapshot')) 'Composer context persistence should retry while the native utility row is still being assembled.'
Assert-True ($newChatPayload.Contains("className.startsWith('hover:')")) 'The synthetic composer context row should remove copied hover styling.'
Assert-True ($newChatPayload.Contains("data-tooltip-visibility-target")) 'The synthetic composer context row should remove copied project hover tooltip hooks.'
Assert-True ($newChatPayload.Contains('installPersistentComposerUtilityBar')) 'Composer context persistence should restore the copied row above existing conversation composers.'
Assert-True ($newChatPayload.Contains('wirePersistentNewChatButton')) 'Composer context persistence should keep the copied new-chat control active.'
Assert-True ($newChatPayload.Contains("button.style.pointerEvents = 'auto'")) 'Copied new-chat control should remain clickable in the informational row.'
Assert-True ($newChatPayload.Contains('button.removeAttribute(''tabindex'')')) 'Copied new-chat control should stay keyboard-activatable in the informational row.'
Assert-True ($newChatPayload.Contains("candidate.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']'")) 'Installed buttons should ignore the informational copy when detecting live controls.'
Assert-True ($newChatPayload.Contains('findVisibleButtonByLabel')) 'Composer new-chat button should locate the visible panel toggles before restoring them.'
Assert-True ($newChatPayload.Contains('isToggleOpen')) 'Composer new-chat button should read open/closed toggle state before restoring panels.'
Assert-True ($newChatPayload.Contains('findBrowserWebview')) 'Composer new-chat button should locate the live browser webview before capturing its URL.'
Assert-True ($newChatPayload.Contains('isBrowserWebviewOpen')) 'Composer new-chat button should detect when the browser webview is actually open.'
Assert-True ($newChatPayload.Contains('findBrowserUrlInput')) 'Composer new-chat button should capture the browser URL input when the browser panel is open.'
Assert-True ($newChatPayload.Contains('pressBrowserAddressEnter')) 'Composer new-chat button should submit the browser address bar when it needs to reopen the webview.'
Assert-True ($newChatPayload.Contains('findBrowserTabButton')) 'Composer new-chat button should find the browser tab before reactivating it.'
Assert-True ($newChatPayload.Contains('readBrowserUrl')) 'Composer new-chat button should normalize the live browser URL before restoring it.'
Assert-True ($newChatPayload.Contains('Browser options')) 'Composer new-chat button should recognize the browser panel controls in the side panel.'
Assert-True ($newChatPayload.Contains('sidePanelOpen')) 'Composer new-chat button should persist the side panel open state with the pending context.'
Assert-True ($newChatPayload.Contains('browserPanelOpen')) 'Composer new-chat button should persist the browser panel open state with the pending context.'
Assert-True ($newChatPayload.Contains('browserSrc')) 'Composer new-chat button should persist the browser webview src for the next chat.'
Assert-True ($newChatPayload.Contains('sidePanelToggleAttemptedAt')) 'Composer new-chat button should avoid repeatedly toggling the side panel while it settles.'
Assert-True ($newChatPayload.Contains('browserPanelToggleAttemptedAt')) 'Composer new-chat button should avoid repeatedly toggling the browser panel while it settles.'
Assert-True ($newChatPayload.Contains('browserSrcAttemptedAt')) 'Composer new-chat button should avoid repeatedly resetting the browser src while it settles.'
Assert-True ($newChatPayload.Contains('restoreSidePanelState')) 'Composer new-chat button should replay the side panel after the new chat opens.'
Assert-True ($newChatPayload.Contains('restoreBrowserPanelState')) 'Composer new-chat button should replay the browser panel after the new chat opens.'
Assert-True ($newChatPayload.Contains('isPendingNewChatContextSatisfied')) 'Composer new-chat button should wait for panel and browser restoration before clearing context.'
Assert-True ($newChatPayload.Contains('currentProjectName')) 'Composer new-chat button should read the current project from the live composer surface.'
Assert-True ($newChatPayload.Contains('activeSyntheticThread')) 'Composer project detection should inspect the active synthetic thread before cached selection state.'
Assert-True ($newChatPayload.Contains('setTimeout(() => selectComposerProject(projectName), 120)')) 'Existing project threads should actively restore the composer project selection.'
Assert-True ($newChatPayload.Contains('findCurrentProjectButton() || findProjectChooserButton()')) 'Existing threads should open the Choose project control when no selected-project button exists.'
Assert-True ($newChatPayload.Contains('projectSelectionInFlight')) 'Project restoration should prevent duplicate chooser attempts while the option is loading.'
Assert-True ($newChatPayload.Contains('chooseProjectOption.expiresAt')) 'Project restoration should poll for a delayed option instead of clicking the chooser repeatedly.'
Assert-True ($newChatPayload.Contains("if (findProjectChooserButton()) return '';")) 'Project restoration should not treat a sidebar project as selected while the composer still shows Choose project.'
Assert-True ($newChatPayload.Contains('button[aria-label="Choose project"]')) 'Persistent composer project labels should include the blank chooser state.'
Assert-True ($newChatPayload.Contains("!button.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']')")) 'Project selection should not click the persistent informational utility-bar copy.'
Assert-True ($newChatPayload.Contains("getComputedStyle(button).pointerEvents !== 'none'")) 'Project selection should ignore non-interactive copied chooser buttons.'
Assert-True ($newChatPayload.Contains('readProjectButtonName')) 'Composer new-chat button should normalize project button labels before restoring them.'
Assert-True ($newChatPayload.Contains('findProjectChooserButton')) 'Composer new-chat button should find the blank-chat project chooser before restoring a project.'
Assert-True ($newChatPayload.Contains('getProjectOption')) 'Composer new-chat button should select the matching project from the chooser menu.'
Assert-True ($newChatPayload.Contains('button[aria-label="Choose project"]')) 'Composer new-chat button should target the blank-chat project chooser.'
Assert-True ($newChatPayload.Contains('data-composer-navigation-target="workspace-project"')) 'Composer new-chat button should use the composer project navigation target when restoring a project.'
Assert-True ($newChatPayload.Contains('role="option"')) 'Composer new-chat button should search project menu options by their rendered labels.'
Assert-True ($newChatPayload.Contains('window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT')) 'Composer new-chat button should persist the pending restore context on the window.'
Assert-True ($newChatPayload.Contains('PENDING_CONTEXT_STORAGE_KEY')) 'Composer new-chat context should survive navigation through session storage.'
Assert-True ($newChatPayload.Contains('sessionStorage.setItem(PENDING_CONTEXT_STORAGE_KEY')) 'Composer new-chat context should be saved before the native navigation.'
Assert-True ($newChatPayload.Contains('sessionStorage.getItem(PENDING_CONTEXT_STORAGE_KEY)')) 'Composer new-chat context should be restored after navigation.'
Assert-True ($newChatPayload.Contains('modelSelectionAttemptedAt')) 'Composer new-chat button should avoid hammering the model selector while it is re-rendering.'
Assert-True ($newChatPayload.Contains('effortSelectionAttemptedAt')) 'Composer new-chat button should avoid hammering the effort selector while it is re-rendering.'
Assert-True ($newChatPayload.Contains('onSelectModel')) 'Composer new-chat button should restore the original model through the live selector controller.'
Assert-True ($newChatPayload.Contains('onSelectReasoningEffort')) 'Composer new-chat button should restore the original effort through the live selector controller.'
Assert-True ($newChatPayload.Contains('window.setInterval(restorePendingNewChatContext, RESTORE_POLL_INTERVAL_MS)')) 'Composer new-chat button should keep retrying restoration until the new chat settles.'
Assert-True ($newChatPayload.Contains('RESTORE_TIMEOUT_MS')) 'Composer new-chat button should abandon stale restore work after a bounded timeout.'
$reminderHiderPayload = Get-CodexFullAccessReminderHiderPayload
Assert-True ($reminderHiderPayload.Contains('record.addedNodes')) 'Reminder hiding should scan only newly added mutation subtrees.'
Assert-True ($reminderHiderPayload.Contains('createTreeWalker')) 'Reminder hiding should use a linear text-node walk instead of repeatedly reading nested container text.'
Assert-True ($reminderHiderPayload.Contains('normalize(textNode.nodeValue)')) 'Reminder hiding should avoid layout-forcing innerText reads.'
Assert-True (-not ($reminderHiderPayload.Contains('element.innerText'))) 'Reminder hiding should never force layout for every element after a composer mutation.'
$newWindowPayload = Get-CodexNewWindowButtonPayload
Assert-True ($newWindowPayload.Contains('data-codex-plus-shared-window-button')) 'New window payload should expose a dedicated shared-window marker.'
Assert-True ($newWindowPayload.Contains('data-codex-plus-usage-dashboard-button')) 'New window payload should expose a dedicated dashboard marker.'
Assert-True (-not ($newWindowPayload.Contains('data-codex-plus-new-chat-button'))) 'New window payload should not own the composer new-chat control.'
Assert-True (-not ($newWindowPayload.Contains('Composer utility bar'))) 'New window payload should stay focused on the window controls.'
Assert-True (-not ($newWindowPayload.Contains('installComposerNewChatButtons'))) 'New window payload should not install composer-specific controls.'
Assert-True ($newWindowPayload.Contains("dashboardButton.textContent = 'Usage Dashboard'")) 'Dashboard button should use an ASCII-only label without a glyph prefix.'
Assert-True ($newWindowPayload.Contains("http://127.0.0.1:3000/")) 'Dashboard button should open the local PowerShell service URL.'
Assert-True ($newWindowPayload.Contains('records.some(mutationTouchesInstallSurface)')) 'Window controls should ignore mutations outside their header and sidebar surfaces.'
Assert-True ($newWindowPayload.Contains('hasInstalledButtons()')) 'New window payload should recover when its installed flag is stale but the DOM buttons are missing.'
Assert-True ($newWindowPayload.Contains('open-in-new-window')) 'New window payload should use Codex''s supported open-in-new-window message.'
Assert-True ($newWindowPayload.Contains('data-codex-plus-project-window-button')) 'New window payload should add a project-row new-window action.'
Assert-True ($newWindowPayload.Contains('codexPlusProjectId')) 'New window payload should carry the project id.'
Assert-True ($newWindowPayload.Contains('codexPlusProjectName')) 'New window payload should carry the project name.'
Assert-True ($newWindowPayload.Contains('[role="menubar"][aria-label="Application menu"]')) 'Top-menu controls should target the native application menubar.'
Assert-True ($newWindowPayload.Contains("document.querySelector(MENU_GROUP_SELECTOR)")) 'Top-menu controls should work when the menubar is outside the header tint wrapper.'
Assert-True ($newWindowPayload.Contains('Codex validates this native route')) 'New-window requests should use a route accepted by the native validator.'
Assert-True ($newWindowPayload.Contains("return threadId ? '/local/'")) 'New-window requests should use a valid local conversation route.'
Assert-True ($newWindowPayload.Contains("const path = context?.id && context?.name ? getProjectStartupPath(context) : '/';")) 'Project new-window payload should use the native bridge home route only when no project context exists.'
Assert-True ($newWindowPayload.Contains('createdAt: Date.now()')) 'Project new-window payload should timestamp the handoff for the newly created page.'
Assert-True ($newWindowPayload.Contains('codexPlusPendingProjectWindows')) 'Project context should be queued through the shared Plus session.'
Assert-True ($newWindowPayload.Contains('currentProjectContext')) 'Menu new-window action should resolve the current project.'
Assert-True ($newWindowPayload.Contains('__CODEX_PLUS_PROJECT_WINDOW_CLICK_GUARD')) 'Project new-window actions should survive native row rerenders through delegated click handling.'
Assert-True ($newWindowPayload.Contains("setStatus('- Launching '")) 'New-window launch should publish its status to the badge.'
Assert-True (-not ($newWindowPayload.Contains('New Plus'))) 'New window payload should not expose the removed independent Plus button.'
$launchSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\launch.ps1')
$managerSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\global-manager.ps1')
Assert-True ($managerSource.Contains('$hourly = $now.AddHours(1)')) 'Usage title should refresh hourly so elapsed-time percentage stays current.'
$dashboardSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\dashboard-server.ps1')
Assert-True ($launchSource.Contains('Get-Content -LiteralPath $indexPath -Encoding UTF8')) 'Session display names should be read as UTF-8 so Hebrew names remain intact.'
Assert-True ($launchSource.Contains('name = Get-CodexSessionDisplayName -SessionId $sessionId')) 'Premature-session alerts should resolve the session display name from the session index.'
Assert-True ($launchSource.Contains('function Get-CodexSessionDiagnostic')) 'Premature-session alerts should reconstruct diagnostic context from the full JSONL session.'
Assert-True ($launchSource.Contains('record_line')) 'Premature-session alerts should include the physical JSONL line number.'
Assert-True ($launchSource.Contains('record_timestamp')) 'Premature-session alerts should include the last record timestamp.'
Assert-True ($launchSource.Contains('record_id')) 'Premature-session alerts should include the last record id when available.'
$tmpSessionIndexRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-session-index-utf8-{0}" -f ([guid]::NewGuid()))
$oldUserProfileForSessionIndex = $env:USERPROFILE
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tmpSessionIndexRoot '.codex') | Out-Null
    $sessionIdForNameTest = '019fc830-9d8b-7cf2-a813-9960cb9b1b95'
    $sessionNameForEncodingTest = ([char]0x05D4) + ([char]0x05EA) + ([char]0x05D0) + ([char]0x05DD) + ' ' +
        ([char]0x05EA) + ([char]0x05D5) + ([char]0x05DB) + ([char]0x05DF) + ' ' +
        ([char]0x05DC) + ([char]0x05DE) + ([char]0x05E1) + ([char]0x05DA) + ' ' +
        ([char]0x05E8) + ([char]0x05D7) + ([char]0x05D1)
    $sessionIndexPathForNameTest = Join-Path $tmpSessionIndexRoot '.codex\session_index.jsonl'
    @{ id=$sessionIdForNameTest; thread_name=$sessionNameForEncodingTest } | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $sessionIndexPathForNameTest -Encoding UTF8
    $env:USERPROFILE = $tmpSessionIndexRoot
    Assert-Equal $sessionNameForEncodingTest (Get-CodexSessionDisplayName -SessionId $sessionIdForNameTest) 'Session display name lookup should preserve Hebrew UTF-8 text.'
} finally {
    $env:USERPROFILE = $oldUserProfileForSessionIndex
    if (Test-Path -LiteralPath $tmpSessionIndexRoot) { Remove-Item -LiteralPath $tmpSessionIndexRoot -Recurse -Force }
}
$tmpDiagnosticPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-session-diagnostic-{0}.jsonl" -f ([guid]::NewGuid()))
try {
    @(
        (@{ type='session_meta'; payload=@{ id='session-diagnostic-id'; cwd='C:\Users\Noam\Documents\code\rest worktree\rest' } } | ConvertTo-Json -Compress)
        (@{ type='event_msg'; timestamp='2026-08-03T15:17:32.000Z'; payload=@{ type='task_started'; turn_id='turn-diagnostic-id' } } | ConvertTo-Json -Compress)
        (@{ type='response_item'; timestamp='2026-08-03T15:17:33.000Z'; payload=@{ type='reasoning'; id='record-diagnostic-id' } } | ConvertTo-Json -Compress)
    ) | Set-Content -LiteralPath $tmpDiagnosticPath -Encoding UTF8
    $diagnostic = Get-CodexSessionDiagnostic -Path $tmpDiagnosticPath
    Assert-Equal 'rest' $diagnostic.project 'Session diagnostics should derive the project from cwd.'
    Assert-Equal 'C:\Users\Noam\Documents\code\rest worktree\rest' $diagnostic.cwd 'Session diagnostics should retain cwd.'
    Assert-Equal 'turn-diagnostic-id' $diagnostic.turn 'Session diagnostics should retain the most recent turn id.'
    Assert-Equal 3 $diagnostic.record_line 'Session diagnostics should report the physical JSONL line number.'
    Assert-Equal 'record-diagnostic-id' $diagnostic.record_id 'Session diagnostics should report the last record id.'
    Assert-Equal 'reasoning' $diagnostic.last_type 'Session diagnostics should report the last payload type.'
} finally {
    if (Test-Path -LiteralPath $tmpDiagnosticPath) { Remove-Item -LiteralPath $tmpDiagnosticPath -Force }
}
Assert-True (-not $launchSource.Contains('[int]$PollMilliseconds = 250')) 'The retired 250ms close-watchdog poll should be removed.'
Assert-True ($managerSource.Contains('[Threading.WaitHandle]::WaitAny')) 'The manager event loop should block on event handles and scheduled one-shot work.'
Assert-True ($managerSource.Contains('-MessageData $shared')) 'File and process event handlers should receive the shared synchronized state explicitly.'
Assert-True ($managerSource.Contains('[Collections.Concurrent.ConcurrentQueue[object]]')) 'Event callbacks should publish into one thread-safe queue.'
Assert-True ($managerSource.Contains('Target.setDiscoverTargets')) 'Each managed instance should maintain browser-level CDP target discovery.'
Assert-True ($managerSource.Contains("DelayMilliseconds 250 -Kind 'close-check'")) 'Native window destruction should use one event-triggered grace check.'
Assert-True ($managerSource.Contains("'native-window-event'")) 'Native window events should drive close handling.'
Assert-True (-not $managerSource.Contains('PollMilliseconds')) 'The global manager should not expose a recurring polling interval.'
Assert-True ($dashboardSource.Contains('$listener.GetContext()')) 'The dashboard should block until an HTTP request arrives.'
Assert-True (-not $dashboardSource.Contains('.Wait($PollMilliseconds)')) 'The dashboard should not wake on a polling timer.'
Assert-True ($launchSource.Contains('ShowWindow(IntPtr hWnd, int command)')) 'Native window handling should expose the Windows maximize operation.'
Assert-True ($launchSource.Contains('MaximizeWindow(IntPtr hWnd)')) 'Native window handling should maximize only the managed window handle.'
Assert-True ($launchSource.Contains('function Maximize-CodexPlusWindows')) 'The Plus runtime should have a managed-window maximize helper.'
Assert-True ($managerSource.Contains('Maximize-CodexPlusWindows -Port $Instance.Port -LauncherKey $Instance.Key')) 'The global manager should maximize newly event-discovered Plus windows.'
Assert-True ($launchSource.Contains('$script:CodexPlusKnownWindowHandles')) 'Window maximization should retain per-handle state.'
Assert-True ($launchSource.Contains('$currentWindowHandleKeys')) 'Window maximization should distinguish closed windows from minimized windows.'
$maximizeBody = (Get-Command -Name Maximize-CodexPlusWindows -CommandType Function).ScriptBlock.ToString()
Assert-True ($maximizeBody.Contains('Test-CodexProcessHasRtlDebugPort -Process $_ -Port $Port')) 'Window maximization should target only the process that owns the watched launch port.'
Assert-True ($launchSource.Contains('A newly opened project target exposes its project context')) 'Native titles should be synchronized after each newly injected target.'
Assert-True ($launchSource.Contains('Retry briefly so') -and $launchSource.Contains('native taskbar title observes the project name')) 'Native titles should be retried after a new project target adopts its context.'
Assert-True ($managerSource.Contains('@(100,250,500,1000)')) 'Native title settling should use bounded event-triggered retries.'
Assert-True ($launchSource.Contains('Update-CodexWindowTitles -Port $Port -LauncherKey $LauncherKey')) 'Native title retries should stay scoped to the launched Codex Plus instance.'
Assert-True ($launchSource.Contains('__CODEX_PLUS_USAGE_WINDOW_TITLE')) 'Native title synchronization should publish the same usage title to the app header.'
Assert-True ($launchSource.Contains('Get-CodexPrematureSessionAlerts')) 'Runtime should monitor stale sessions for missing terminal events.'
Assert-True ($launchSource.Contains('Update-CodexPrematureSessionState')) 'Task monitor should update pending state only for changed session paths.'
Assert-True ($launchSource.Contains('CodexPlusPrematurePending')) 'Task monitor should retain changed files until they finish or become inactive.'
Assert-True ($launchSource.Contains('[DateTime]::Parse([string]$last[0].timestamp).ToUniversalTime()')) 'Premature-session activity should prefer the latest JSONL record timestamp over file mtime.'
Assert-True ($launchSource.Contains('$diagnostic.record_timestamp')) 'Premature-session alerts should re-read the latest JSONL timestamp before alerting.'
Assert-True ($launchSource.Contains('$script:CodexPlusChangedSessionPaths')) 'Session monitor should track changed session paths from the file watcher.'
Assert-True ($launchSource.Contains('-Tail 4')) 'Task monitor should read only the last few records of a changed session.'
Assert-True ($managerSource.Contains('SourceEventArgs.FullPath')) 'The global session watcher should pass the changed file path through the shared queue.'
Assert-True ($launchSource.Contains('$script:CodexPlusUsageChangedPaths')) 'Usage refresh should reuse changed session paths.'
Assert-True ($launchSource.Contains('Get-CodexLatestRateLimitSummary -Paths')) 'Usage monitor should read rate-limit data from changed sessions.'
Assert-True ($launchSource.Contains('Get-Content -LiteralPath $latest.FullName -Tail 10')) 'Usage monitor should inspect only the last ten records of the newest changed session.'
Assert-True ($managerSource.Contains('codex-plus-session-alert')) 'Runtime manager should publish premature-session alerts to Codex pages.'
Assert-True ($launchSource.Contains('System.Windows.Forms')) 'Premature-session alerts should use a native Windows form.'
Assert-True ($launchSource.Contains("$button.Text = 'Dismiss'")) 'Windows session alert should provide a dismiss button.'
Assert-True ($launchSource.Contains('ShowDialog')) 'Windows session alert should remain open until dismissed.'
$contextBadgePayload = Get-CodexContextBadgePayload
Assert-True ($contextBadgePayload.Contains('readWindowTitle')) 'Context badge should read the current window title context.'
Assert-True ($contextBadgePayload.Contains('__CODEX_PLUS_NATIVE_WINDOW_TITLE')) 'Context badge should display the synchronized native window title.'
Assert-True ($contextBadgePayload.Contains('__CODEX_PLUS_PROJECT_WINDOW_CONTEXT')) 'Context badge should include the project title in project windows.'
Assert-True ($contextBadgePayload.Contains('readUsageText')) 'Context badge should read the usage title published by the launcher.'
Assert-True ($contextBadgePayload.Contains("['Plus', title, statusText, usage || percent]")) 'Context badge should display Plus, status, title, and usage when available.'
Assert-True ($contextBadgePayload.Contains('codex-plus-usage-updated')) 'Context badge should refresh when the launcher updates the usage title.'
Assert-True ($contextBadgePayload.Contains('data-codex-plus-session-alert')) 'Codex UI should render a premature-session alert.'
Assert-True ($contextBadgePayload.Contains('Dismiss')) 'Premature-session alert should provide a dismiss button.'
Assert-True ($contextBadgePayload.Contains("copy.textContent = 'Copy'")) 'Premature-session alert should provide a copy button.'
Assert-True ($contextBadgePayload.Contains('Project:')) 'Premature-session alert should show the project.'
Assert-True ($contextBadgePayload.Contains('CWD:')) 'Premature-session alert should show the working directory.'
Assert-True ($contextBadgePayload.Contains('Record: line')) 'Premature-session alert should show the JSONL line and record identity.'
Assert-True ($contextBadgePayload.Contains('Record timestamp:')) 'Premature-session alert should show the record timestamp.'
Assert-True ($contextBadgePayload.Contains('Triggered by:')) 'Premature-session alert should explain its trigger.'
Assert-True ($contextBadgePayload.Contains('setStatus(nextStatus)')) 'Context badge should expose a live status setter.'
Assert-True ($contextBadgePayload.Contains('records.some(mutationTouchesBadgeSource)')) 'Context badge should ignore unrelated composer and conversation mutations.'
$sharedPayload = Get-CodexRtlSharedPayload
Assert-True ($sharedPayload.Contains('ensureHelpers')) 'Shared bidi payload should expose the helpers on a shared window namespace.'
Assert-True ($sharedPayload.Contains('classifyDirection')) 'Shared bidi payload should own the direction classifier used by multiple surfaces.'
$planPayload = Get-CodexRtlPayloadPlan
Assert-True ($planPayload.Contains('__CODEX_RTL_SHARED_HELPERS')) 'Plan payload should consume the shared bidi helpers instead of redefining its own classifier.'
Assert-True ($planPayload.Contains("textAlign !== 'start'")) 'Plan payload should keep the plan surface aligned to the natural block start edge.'
Assert-True ($planPayload.Contains('hasNestedTextBlock')) 'Plan payload should avoid flattening nested mixed-direction blocks.'
Assert-True ($planPayload.Contains('records.some(mutationTouchesPlan)')) 'Plan RTL should ignore mutations outside the Plan panel.'
$sidebarPayload = Get-CodexSidebarPagingPayload
Assert-True ($sidebarPayload.Contains('Recent Codex builds accept the open-in-new-window message')) 'Project handoff should document the normalized new-window route fallback.'
Assert-True ($sidebarPayload.Contains('|| (!startupRoute)')) 'Project handoff should consume a recent queued context when the native window strips the route.'

$nodeCommand = Get-Command -Name node -ErrorAction SilentlyContinue
if ($nodeCommand) {
    $payloadTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rtl-payload-{0}.js" -f ([guid]::NewGuid().ToString('N')))
    $runnerTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rtl-runner-{0}.js" -f ([guid]::NewGuid().ToString('N')))
    try {
        Set-Content -LiteralPath $payloadTempPath -Value ($sharedPayload + "`n" + $payload) -Encoding UTF8
        Set-Content -LiteralPath $runnerTempPath -Encoding UTF8 -Value @'
const fs = require('fs');
const vm = require('vm');
const payload = fs.readFileSync(process.argv[2], 'utf8');

const context = {
  console,
  window: { setTimeout: (fn) => fn() },
  document: {
    readyState: 'loading',
    addEventListener: () => {},
    querySelectorAll: () => [],
    head: {
      querySelector: () => null,
      appendChild: () => {}
    },
    createElement: () => ({
      setAttribute: () => {},
      style: {},
      textContent: ''
    })
  },
  MutationObserver: function MutationObserver() {
    return {
      observe: () => {},
      disconnect: () => {}
    };
  }
};

vm.runInNewContext(payload, context);
const classify = context.window.__CODEX_RTL_FIX_CODEX.classifyDirection;
const cases = [
  ['rtl', '\u05e2\u05d1\u05e8\u05d9\u05ea \u05e2\u05dd \u05de\u05e1\u05e4\u05e8 \u05e4\u05e0\u05d9\u05de\u05d9 123 \u05d1\u05d0\u05de\u05e6\u05e2 \u05d4\u05de\u05e9\u05e4\u05d8'],
  ['rtl', 'A03. Hebrew then English: \u05e9\u05dc\u05d5\u05dd LoginActivity update README'],
  ['rtl', '50 \u05d5\u05e8\u05d9\u05d0\u05e6\u05d9\u05d5\u05ea \u05e7\u05e6\u05e8\u05d5\u05ea \u05d1\u05de\u05d9\u05d5\u05d7\u05d3'],
  ['rtl', '\u05db\u05d5\u05ea\u05e8\u05ea \u05e2\u05dd inline code \u05d5-English'],
  ['rtl', 'H05. Compare dir="rtl" \u05de\u05d5\u05dc dir="auto" \u05d1\u05ea\u05d5\u05da \u05de\u05e9\u05e4\u05d8 \u05e2\u05d1\u05e8\u05d9.'],
  ['ltr', 'Please review \u05e9\u05dc\u05d5\u05dd world'],
  ['ltr', 'English only ID-1234']
];

for (const [expected, input] of cases) {
  const actual = classify(input);
  if (actual !== expected) {
    throw new Error(`${input}: expected ${expected}, got ${actual}`);
  }
}
'@
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $nodeOutput = & $nodeCommand.Path $runnerTempPath $payloadTempPath 2>&1 | ForEach-Object { "$_" }
            $nodeExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }
        if ($nodeExitCode -ne 0) {
            throw "Payload classifier behavior check failed:`n$($nodeOutput | Out-String)"
        }
    } finally {
        foreach ($tempPath in @($payloadTempPath, $runnerTempPath)) {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
    }
}

$cdpBody = (Get-Command -Name Invoke-CodexRtlInjectionForTarget -CommandType Function).ScriptBlock.ToString()
Assert-True ($cdpBody.Contains('Page.addScriptToEvaluateOnNewDocument')) 'Injection should install the payload for future documents.'
Assert-True ($cdpBody.Contains('Runtime.evaluate')) 'Injection should also evaluate the payload in the current document.'

$injectionSource = Get-Content -Raw (Join-Path $repoRoot 'src\runtime\launch.ps1')
Assert-True ($injectionSource.Contains('CodexPlusInjectedTargetIds.ContainsKey')) 'Injection should remember targets that already received the payload.'
Assert-True ($injectionSource.Contains('continue')) 'Injection should skip targets that already received the payload.'

$cdpCommandBody = (Get-Command -Name Invoke-CodexCdpCommand -CommandType Function).ScriptBlock.ToString()
Assert-True ($cdpCommandBody.Contains('while (-not $result.EndOfMessage)')) 'CDP command responses should keep reading until EndOfMessage.'
Assert-True ($cdpCommandBody.Contains('WebSocketMessageType]::Close')) 'CDP command responses should reject close frames while reading.'

Write-Host 'codex-runtime-rtl.tests.ps1 passed'
