param(
    [ValidateSet('Status','Register','Unregister')][string]$Action = 'Status',
    [AllowEmptyString()][string]$LauncherKey,
    [int]$Port,
    [AllowEmptyString()][string]$UserDataDirectory,
    [switch]$Raw
)

$ErrorActionPreference = 'Stop'
$requestedAction = $Action
$requestedLauncherKey = $LauncherKey
$requestedPort = $Port
$requestedUserDataDirectory = $UserDataDirectory
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'patch.ps1') -SkipMain

switch ($requestedAction) {
    'Status' {
        $result = Send-CodexPlusManagerCommand -Command @{ action = 'status' }
    }
    'Register' {
        if ([string]::IsNullOrWhiteSpace($requestedLauncherKey) -or $requestedPort -le 0) {
            throw 'Register requires -LauncherKey and -Port.'
        }
        if ([string]::IsNullOrWhiteSpace($requestedUserDataDirectory)) {
            $requestedUserDataDirectory = Get-CodexPlusUserDataDirectory -LauncherKey $requestedLauncherKey
        }
        $result = Register-CodexPlusManagerInstance -LauncherKey $requestedLauncherKey -Port $requestedPort -UserDataDirectory $requestedUserDataDirectory
    }
    'Unregister' {
        if ([string]::IsNullOrWhiteSpace($requestedLauncherKey)) { throw 'Unregister requires -LauncherKey.' }
        $result = Unregister-CodexPlusManagerInstance -LauncherKey $requestedLauncherKey
    }
}

if ($Raw) {
    $result | ConvertTo-Json -Depth 12 -Compress
} else {
    $result | ConvertTo-Json -Depth 12
}
