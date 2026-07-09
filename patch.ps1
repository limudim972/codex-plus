<#
.SYNOPSIS
    Codex Plus
.DESCRIPTION
    Installs and restores the local Codex Desktop RTL runtime.
#>
param(
    [string]$TrustedPubKey,
    [switch]$LaunchCodexRtl,
    [switch]$SkipMain
)

if ($env:OS -ne 'Windows_NT') {
    Write-Host "Codex Plus is Windows-only. Please run it on Windows 10/11." -ForegroundColor Red
    exit 1
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$RequiresElevation = (-not $LaunchCodexRtl)
if ((-not $SkipMain) -and $RequiresElevation -and (-not $IsAdmin)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($TrustedPubKey) { $args += @('-TrustedPubKey', $TrustedPubKey) }
        Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs `
            -ArgumentList $args
        Exit
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $InstallUrl = "https://raw.githubusercontent.com/limudim972/codex-plus/main/install.ps1"
    Invoke-Expression (Invoke-RestMethod $InstallUrl)
    Exit
}

$script:CodexRtlFixModuleManifest = [ordered]@{
    'src/shared/logging.ps1' = 'a1cbd3d75f31552a966ed81148ba46bbfb4860761ad4dc4a43b421c5ed5f8718'
    'src/shared/prompting.ps1' = '1f21230a4fc91d69a41e370d52768b02e70ab32d9f35fb64824c16ac0cc23202'
    'src/shared/asar.ps1' = 'efff1c7b3a904d6d1dd6dc7b8a2a229b38a5c3ec69c32c8b35f1eb4143fb9a7b'
    'src/codex/detection.ps1' = '9a8aa5aa1ed0c0e582b862f89164400bfd25db132fd4d0800e3517316a81bd74'
    'src/codex/rtl-payload.ps1' = 'f5236e71f33ecd3c04a0810ffc09da727f96e5f9f3468d0be8b5e5387fa99da0'
    'src/runtime/state.ps1' = '5c96cf3fe8a36c5aea393e3a5b1d0f20f622dc8454098bbfe72b9f0330976373'
    'src/runtime/files.ps1' = '8837c168c7d8974915bd8e93d13ed0aad3c597db7a49722d6b2714a362d41b54'
    'src/runtime/shortcuts.ps1' = '5c8a1ef9f287e1b7b660ae21b1ceaa6822652e9a30b74948a82f2a5f5cabdd03'
    'src/runtime/launch.ps1' = '88a4c80e7c5986f54dd187d1455cd67e013b240e55a06e183d4357af02397c44'
    'src/runtime/patching.ps1' = '2f9b107485341d9fc8772dd8168de978f6f053469bb5733269b6cbd02368718e'
    'src/ui/menu.ps1' = 'd94e5d4e76bc7ec296a08993681cd246fec3d2a000d97f6494cf68132afbda3e'
}

foreach ($module in $script:CodexRtlFixModuleManifest.Keys) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required module not found: $modulePath"
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $modulePath).Hash.ToLowerInvariant()
    $expectedHash = $script:CodexRtlFixModuleManifest[$module].ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Required module hash mismatch: $module"
    }
    . $modulePath
}

$script:CodexRtlPatchScriptPath = $PSCommandPath

if ($SkipMain) {
    return
}

if ($LaunchCodexRtl) {
    Launch-CodexRtl
    Exit
}

Show-Menu
