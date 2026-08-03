# Codex Plus installer.
#
param(
    [switch]$LocalDev,
    [ValidateRange(1024, 65535)]
    [int]$Port = 0
)

function Pause-ForInstallerExit {
    param([string]$Message = 'Press Enter to close this window.')

    if ($Host.Name -ne 'ConsoleHost') {
        return
    }

    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    try {
        [void](Read-Host)
    } catch {
    }
}

function Test-InstallerPortAvailable {
    param([Parameter(Mandatory)][int]$Port)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Parse('127.0.0.1'),
            $Port
        )
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Get-RandomInstallerPort {
    param(
        [int]$Minimum = 20000,
        [int]$Maximum = 45000,
        [int]$Attempts = 100
    )

    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $candidate = Get-Random -Minimum $Minimum -Maximum ($Maximum + 1)
        if (Test-InstallerPortAvailable -Port $candidate) {
            return $candidate
        }
    }

    throw "Could not find an available Codex Plus port between $Minimum and $Maximum after $Attempts attempts."
}

function Start-CodexPlusAfterInstall {
    param([int]$Port = 0)

    $shortcutCandidates = @(
        (Join-Path $env:USERPROFILE 'Desktop\Codex Plus.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex Plus.lnk')
    )
    $shortcutPath = $shortcutCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $shortcutPath) {
        Write-Host 'Codex Plus installed, but no launcher shortcut was found. Start it from the Start Menu.' -ForegroundColor Yellow
        return
    }

    Write-Host "Launching Codex Plus from $shortcutPath ..." -ForegroundColor Green
    Write-Host "Using requested Codex Plus port $Port." -ForegroundColor Green
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ([string]::IsNullOrWhiteSpace($shortcut.TargetPath)) {
        throw "Codex Plus shortcut target could not be resolved: $shortcutPath"
    }
    $launcherArguments = [string]$shortcut.Arguments
    if (-not [string]::IsNullOrWhiteSpace($launcherArguments)) { $launcherArguments += ' ' }
    $launcherArguments += [string]$Port
    $previousRequestedPort = [Environment]::GetEnvironmentVariable('CODEX_PLUS_REQUESTED_PORT', 'Process')
    try {
        $env:CODEX_PLUS_REQUESTED_PORT = [string]$Port
        Start-Process -FilePath $shortcut.TargetPath -ArgumentList $launcherArguments -WorkingDirectory $shortcut.WorkingDirectory | Out-Null
        # Keep the fallback environment alive while wscript.exe starts the
        # launcher and its PowerShell children.
        Start-Sleep -Seconds 10
    } finally {
        if ($null -eq $previousRequestedPort) {
            Remove-Item Env:CODEX_PLUS_REQUESTED_PORT -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_PLUS_REQUESTED_PORT = $previousRequestedPort
        }
    }

    # Keep this machine-readable so callers such as the local .bat launcher can
    # capture the exact port without a state file or a post-launch port scan.
    Write-Output "CODEX_PLUS_LAUNCH_PORT=$Port"
}

if ($env:OS -ne 'Windows_NT') {
    Write-Host "Codex Plus is Windows-only. Please run it on Windows 10/11." -ForegroundColor Red
    exit 1
}

$requestedPort = $Port
if ($requestedPort -le 0 -and -not [string]::IsNullOrWhiteSpace($env:CODEX_PLUS_REQUESTED_PORT)) {
    $parsedPort = 0
    if (-not [int]::TryParse($env:CODEX_PLUS_REQUESTED_PORT, [ref]$parsedPort)) {
        throw "CODEX_PLUS_REQUESTED_PORT '$($env:CODEX_PLUS_REQUESTED_PORT)' is not a valid TCP port."
    }
    if ($parsedPort -lt 1024 -or $parsedPort -gt 65535) {
        throw "CODEX_PLUS_REQUESTED_PORT '$parsedPort' is outside the valid TCP port range."
    }
    $requestedPort = $parsedPort
}

if ($requestedPort -le 0) {
    $requestedPort = Get-RandomInstallerPort
    Write-Host "Selected random Codex Plus port $requestedPort." -ForegroundColor Green
}

if ($requestedPort -gt 0 -and -not (Test-InstallerPortAvailable -Port $requestedPort)) {
    throw "Requested Codex Plus port $requestedPort is already in use. Choose another port and retry."
}

$RepoBase = 'https://raw.githubusercontent.com/limudim972/codex-plus/main'
$TmpRoot  = Join-Path $env:TEMP 'codex_rtl_fix_patch'
$TmpFile  = Join-Path $TmpRoot 'patch.ps1'
$LocalRepoRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Get-Location }
$SourceRoot = if ($LocalDev) { $LocalRepoRoot } else { $null }
$ModuleFiles = @(
    'src/shared/logging.ps1',
    'src/shared/prompting.ps1',
    'src/shared/asar.ps1',
    'src/codex/rtl-shared.ps1',
    'src/runtime/assets/codex-plus.ico',
    'src/runtime/dashboard-server.ps1',
    'src/runtime/global-manager.ps1',
    'src/codex/detection.ps1',
    'src/codex/new-window-button.ps1',
    'src/codex/rtl-payload.ps1',
    'src/codex/rtl-payload-Plan.ps1',
    'src/codex/payload-bundle.ps1',
    'src/codex/activity-onboarding-hider.ps1',
    'src/codex/context-badge.ps1',
    'src/codex/split-model-effort-selector.ps1',
    'src/codex/sidebar-paging.ps1',
    'src/runtime/state.ps1',
    'src/runtime/files.ps1',
    'src/runtime/shortcuts.ps1',
    'src/runtime/launch.ps1',
    'src/runtime/patching.ps1',
    'src/ui/menu.ps1'
)

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$client = New-Object System.Net.WebClient
if ($LocalDev) {
    $patchPath = Join-Path $SourceRoot 'patch.ps1'
    if (-not (Test-Path -LiteralPath $patchPath)) {
        Write-Host "Local patch not found: $patchPath" -ForegroundColor Red
        return
    }
} else {
    try {
        $patchBytes = $client.DownloadData("$RepoBase/patch.ps1")
    } catch {
        Write-Host ""
        Write-Host "Network error downloading patch: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Check connectivity and retry." -ForegroundColor Yellow
        return
    }
}

if ($LocalDev) {
    Write-Host "Launching local Codex Plus installer..." -ForegroundColor Green
    & (Join-Path $SourceRoot 'patch.ps1') -InstallCodexPlus
    Write-Host "Codex Plus installer finished." -ForegroundColor Green
    Start-CodexPlusAfterInstall -Port $requestedPort
} else {
    $content = [System.Text.Encoding]::UTF8.GetString($patchBytes)
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }

    try {
        if (-not (Test-Path -LiteralPath $TmpRoot)) {
            New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
        }

        foreach ($module in $ModuleFiles) {
            $moduleBytes = $client.DownloadData("$RepoBase/$module")
            $modulePath = Join-Path $TmpRoot $module
            $moduleDir = Split-Path -Parent $modulePath
            if (-not (Test-Path -LiteralPath $moduleDir)) {
                New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null
            }
            [System.IO.File]::WriteAllBytes($modulePath, $moduleBytes)
        }
    } catch {
        Write-Host ""
        Write-Host "Network error downloading required modules: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Check connectivity and retry." -ForegroundColor Yellow
        return
    }

    [System.IO.File]::WriteAllText($TmpFile, $content, [System.Text.UTF8Encoding]::new($true))
    Write-Host "Codex Plus downloaded ($($patchBytes.Length) bytes) and modules staged. Running installer..." -ForegroundColor Green
    & $TmpFile -InstallCodexPlus
    Write-Host "Codex Plus installer finished." -ForegroundColor Green
    Start-CodexPlusAfterInstall -Port $requestedPort
}
