$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'patch.ps1') -SkipMain

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ((@($Expected) -join ',') -ne (@($Actual) -join ',')) {
        throw "$Message Expected '$(@($Expected) -join ',')', got '$(@($Actual) -join ',')'."
    }
}

$oldLocalAppData = $env:LOCALAPPDATA
$oldStoppedProcesses = @()
$script:StoppedProcesses = @()
try {
    $env:LOCALAPPDATA = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-plus-cleanup-' + [guid]::NewGuid().ToString('N'))
    $launcherKey = 'cleanup-test'
    $profile = Get-CodexPlusUserDataDirectory -LauncherKey $launcherKey
    $mockAppExe = 'C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\ChatGPT.exe'
    $script:MockCodexProcesses = @(
        [pscustomobject]@{
            ProcessId = 101
            ParentProcessId = 1
            ExecutablePath = $mockAppExe
            CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\ChatGPT.exe" --remote-debugging-port=18420 --remote-debugging-address=127.0.0.1 --user-data-dir="{0}"' -f $profile
        },
        [pscustomobject]@{
            ProcessId = 102
            ParentProcessId = 101
            ExecutablePath = $mockAppExe
            CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\ChatGPT.exe" --type=renderer'
        },
        [pscustomobject]@{
            ProcessId = 103
            ParentProcessId = 102
            ExecutablePath = $mockAppExe
            CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\ChatGPT.exe" --type=utility'
        },
        [pscustomobject]@{
            ProcessId = 201
            ParentProcessId = 1
            ExecutablePath = $mockAppExe
            CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\ChatGPT.exe" --remote-debugging-port=18421 --remote-debugging-address=127.0.0.1 --user-data-dir="C:\Other\Codex"'
        },
        [pscustomobject]@{
            ProcessId = 202
            ParentProcessId = 201
            ExecutablePath = $mockAppExe
            CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex_fake\app\ChatGPT.exe" --type=renderer'
        }
    )

    function Get-CodexInstallInfo {
        [pscustomobject]@{ PackageFound = $true; AppExe = $mockAppExe }
    }
    function Get-CodexDesktopProcesses { @($script:MockCodexProcesses) }
    function Stop-Process {
        param([int]$Id, [switch]$Force)
        $script:StoppedProcesses += $Id
    }

    Stop-CodexDesktopProcesses -Port 18420 -LauncherKey $launcherKey -CurrentInstanceOnly -KnownProcessIds @(101)
    Assert-Equal @(103, 102, 101) $script:StoppedProcesses 'Cleanup should stop the Plus process tree from descendants to root.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
}

Write-Host 'process-cleanup.tests.ps1 passed'
