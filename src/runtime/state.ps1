function Get-CodexRtlStateRoot {
    Join-Path $env:LOCALAPPDATA 'Codex Plus'
}

function Get-CodexRtlRuntimeRoot {
    Join-Path (Get-CodexRtlStateRoot) 'runtime'
}

function Get-CodexRtlStatePath {
    Join-Path (Get-CodexRtlStateRoot) 'state.json'
}

function Get-CodexRtlWorkingDirectory {
    $root = Get-CodexRtlStateRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    return $root
}

function Get-CodexLauncherIdentity {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    $normalizedPath = $ShortcutPath.Trim().Trim('"')
    try {
        $normalizedPath = [System.IO.Path]::GetFullPath($normalizedPath)
    } catch {
    }
    $normalizedPath = $normalizedPath.Replace('\\', '\').TrimEnd('\').ToLowerInvariant()

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedPath))
        return ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-CodexPlusUserDataDirectory {
    param([AllowEmptyString()][string]$LauncherKey)

    $profileRoot = Join-Path (Get-CodexRtlStateRoot) 'profile'
    $profilePath = if ([string]::IsNullOrWhiteSpace($LauncherKey)) {
        $profileRoot
    } else {
        Join-Path $profileRoot $LauncherKey
    }
    if (-not (Test-Path -LiteralPath $profilePath)) {
        New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
    }
    return $profilePath
}

function Read-CodexRtlState {
    $path = Get-CodexRtlStatePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $ownedArtifacts = @()
        if ($state.PSObject.Properties.Name -contains 'OwnedArtifacts') {
            $ownedArtifacts = @($state.OwnedArtifacts)
        } elseif ($state.PSObject.Properties.Name -contains 'ShortcutBackups') {
            $ownedArtifacts = @($state.ShortcutBackups | ForEach-Object { $_.OriginalPath } | Where-Object { $_ })
        }

        [pscustomobject]@{
            Version = if ($state.PSObject.Properties.Name -contains 'Version') { [int]$state.Version } else { 1 }
            Port = $state.Port
            PackageVersion = $state.PackageVersion
            InstallLocation = $state.InstallLocation
            AppExe = $state.AppExe
            RuntimeRoot = if ($state.RuntimeRoot) { $state.RuntimeRoot } else { Get-CodexRtlRuntimeRoot }
            LauncherScriptPath = if ($state.LauncherScriptPath) { $state.LauncherScriptPath } else { Get-CodexPlusLauncherScriptPath }
            ShortcutBackups = @($state.ShortcutBackups)
            OwnedArtifacts = @($ownedArtifacts)
            UpdatedAt = $state.UpdatedAt
        }
    } catch {
        Write-Warn "Codex Plus state is unreadable and will be replaced: $($_.Exception.Message)"
        return $null
    }
}

function Save-CodexRtlState {
    param([Parameter(Mandatory)]$State)

    $root = Get-CodexRtlStateRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-CodexRtlStatePath) -Encoding UTF8
}

function New-CodexRtlState {
    param(
        [Parameter(Mandatory)]$InstallInfo,
        [int]$Port = (Get-CodexRtlDefaultPort),
        [object[]]$ShortcutBackups = @(),
        [string[]]$OwnedArtifacts = @()
    )

    $allOwnedArtifacts = @(
        @($ShortcutBackups | ForEach-Object { $_.OriginalPath })
        $OwnedArtifacts
    ) | Where-Object { $_ } | Select-Object -Unique

    [pscustomobject]@{
        Version = 1
        Port = $Port
        PackageVersion = $InstallInfo.PackageVersion
        InstallLocation = $InstallInfo.InstallLocation
        AppExe = $InstallInfo.AppExe
        RuntimeRoot = Get-CodexRtlRuntimeRoot
        LauncherScriptPath = Get-CodexPlusLauncherScriptPath
        ShortcutBackups = @($ShortcutBackups)
        OwnedArtifacts = @($allOwnedArtifacts)
        UpdatedAt = [DateTimeOffset]::Now.ToString('o')
    }
}
