function Install-CodexRtlPatch {
    $installInfo = Get-CodexInstallInfo
    if (-not $installInfo.PackageFound -or -not $installInfo.AppExe -or -not (Test-Path -LiteralPath $installInfo.AppExe)) {
        throw 'Codex Desktop was not found.'
    }

    $sourceRoot = if ($PSScriptRoot) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { Split-Path -Parent (Get-CodexRtlPatchScriptPath) }
    $runtimeRoot = Install-CodexRtlRuntimeFiles -SourceRoot $sourceRoot
    $runtimePatchScript = Join-Path $runtimeRoot 'patch.ps1'

    $existingState = Read-CodexRtlState
    $preferredPort = if ($existingState -and $existingState.Port) { [int]$existingState.Port } else { 0 }
    $port = Get-CodexRtlLaunchPort -PreferredPort $preferredPort
    Install-CodexRtlLauncherScript -PatchScriptPath $runtimePatchScript | Out-Null
    Remove-CodexRtlOwnedShortcut -ShortcutPath (Get-CodexRtlShortcutPath) | Out-Null

    $ownedArtifacts = @()
    $shortcutInventory = @(Get-CodexShortcutInventory)
    $seedableShortcuts = @($shortcutInventory | Where-Object {
        Test-CodexShortcutSeedable -Shortcut $_
    })
    $skippedCodexShortcuts = @($shortcutInventory | Where-Object {
        (Test-CodexShortcutCandidate -Shortcut $_) -and -not (Test-CodexShortcutSeedable -Shortcut $_)
    })
    $createdOrRefreshedCount = 0
    foreach ($shortcut in $seedableShortcuts) {
        try {
            $shortcutSpec = New-CodexLauncherShortcutSpec -ShortcutPath $shortcut.Path -InstallInfo $installInfo
            if (Install-CodexParallelRtlShortcutIfPossible -SourceShortcut $shortcut -Spec $shortcutSpec) {
                $ownedArtifacts += Get-CodexSiblingRtlShortcutPath -ShortcutPath $shortcut.Path
                $createdOrRefreshedCount++
            } else {
                $skippedCodexShortcuts += $shortcut
            }
        } catch {
            $skippedCodexShortcuts += $shortcut
            Write-Warn "Codex Plus shortcut creation skipped for $($shortcut.Path): $($_.Exception.Message)"
        }
    }

    try {
        $startMenuShortcutSpec = New-CodexLauncherShortcutSpec -ShortcutPath (Get-CodexRtlShortcutPath) -InstallInfo $installInfo
        if (Install-CodexStartMenuRtlShortcut -Spec $startMenuShortcutSpec) {
            $ownedArtifacts += Get-CodexRtlShortcutPath
            $createdOrRefreshedCount++
        }
    } catch {
        Write-Warn "Codex Plus Start Menu shortcut creation skipped for $(Get-CodexRtlShortcutPath): $($_.Exception.Message)"
    }

    try {
        $desktopShortcutPath = Join-Path $env:USERPROFILE 'Desktop\Codex Plus.lnk'
        if (-not (Test-Path -LiteralPath $desktopShortcutPath) -or (Test-CodexRtlOwnedShortcut -ShortcutPath $desktopShortcutPath)) {
            $desktopSpec = New-CodexLauncherShortcutSpec -ShortcutPath $desktopShortcutPath -InstallInfo $installInfo
            New-CodexLauncherShortcut -ShortcutPath $desktopShortcutPath -Spec $desktopSpec
            $ownedArtifacts += $desktopShortcutPath
            $createdOrRefreshedCount++
        }
    } catch {
        Write-Warn "Codex Plus Desktop shortcut creation skipped for $env:USERPROFILE\Desktop\Codex Plus.lnk: $($_.Exception.Message)"
    }

    $state = New-CodexRtlState `
        -InstallInfo $installInfo `
        -Port $port `
        -ShortcutBackups @() `
        -OwnedArtifacts $ownedArtifacts
    Save-CodexRtlState -State $state

    Write-Host "Codex Plus launcher installed." -ForegroundColor Green
    Write-Host "Created or refreshed $createdOrRefreshedCount Codex Plus shortcut(s)." -ForegroundColor Green
    Write-Host "Skipped $($skippedCodexShortcuts.Count) candidate location(s)." -ForegroundColor Green
    Write-Host "Launch Codex using a Codex Plus shortcut." -ForegroundColor Green
}

function Restore-CodexRtlPatch {
    $state = Read-CodexRtlState
    $patchedRunningProcess = $null
    $restoreAppExe = $null
    if ($state -and $state.Port) {
        $patchedRunningProcess = @(
            Get-CodexDesktopProcesses | Where-Object {
                Test-CodexProcessHasRtlDebugPort -Process $_ -Port ([int]$state.Port)
            }
        ) | Select-Object -First 1
    }
    if ($patchedRunningProcess) {
        if ($state -and $state.AppExe -and (Test-Path -LiteralPath $state.AppExe)) {
            $restoreAppExe = $state.AppExe
        } else {
            $installInfo = Get-CodexInstallInfo
            if ($installInfo.PackageFound -and $installInfo.AppExe -and (Test-Path -LiteralPath $installInfo.AppExe)) {
                $restoreAppExe = $installInfo.AppExe
            }
        }
        Stop-CodexDesktopProcesses
    }

    $restored = @()
    if ($state -and $state.ShortcutBackups) {
        $restored = @(Restore-CodexShortcutBackups -Backups @($state.ShortcutBackups))
    }

    $ownedArtifacts = if ($state -and $state.OwnedArtifacts) { @($state.OwnedArtifacts) } else { @() }
    if ($ownedArtifacts.Count -eq 0) {
        $ownedArtifacts = @((Get-CodexRtlShortcutPath))
    }
    $removedOwnedShortcutCount = 0
    foreach ($ownedArtifact in $ownedArtifacts) {
        $existedBeforeRemoval = Test-Path -LiteralPath $ownedArtifact
        Remove-CodexRtlOwnedShortcut -ShortcutPath $ownedArtifact | Out-Null
        if ($existedBeforeRemoval -and (-not (Test-Path -LiteralPath $ownedArtifact))) {
            $removedOwnedShortcutCount += 1
        }
    }

    $launcherScriptPath = if ($state -and $state.LauncherScriptPath) { $state.LauncherScriptPath } else { Get-CodexPlusLauncherScriptPath }
    if ($launcherScriptPath -and (Test-Path -LiteralPath $launcherScriptPath)) {
        Remove-Item -LiteralPath $launcherScriptPath -Force
    }

    $statePath = Get-CodexRtlStatePath
    if (Test-Path -LiteralPath $statePath) {
        Remove-Item -LiteralPath $statePath -Force
    }

    if ($patchedRunningProcess -and $restoreAppExe) {
        Start-CodexNormally -AppExe $restoreAppExe
        Write-Host "Codex Plus runtime removed." -ForegroundColor Yellow
        Write-Host "Restored $($restored.Count) shortcut backup(s)." -ForegroundColor Yellow
        Write-Host "Removed $removedOwnedShortcutCount owned Codex Plus shortcut(s)." -ForegroundColor Yellow
        Write-Host "Restarted Codex in normal mode." -ForegroundColor Yellow
    } else {
        Write-Host "Codex Plus runtime removed." -ForegroundColor Yellow
        Write-Host "Restored $($restored.Count) shortcut backup(s)." -ForegroundColor Yellow
        Write-Host "Removed $removedOwnedShortcutCount owned Codex Plus shortcut(s)." -ForegroundColor Yellow
        Write-Host "Restart Codex normally if it is still open." -ForegroundColor Yellow
    }
}

function Launch-CodexRtl {
    param([AllowEmptyString()][string]$LauncherKey)

    $installInfo = Get-CodexInstallInfo
    if (-not $installInfo.PackageFound -or -not $installInfo.AppExe -or -not (Test-Path -LiteralPath $installInfo.AppExe)) {
        throw 'Codex Desktop was not found.'
    }

    if ([string]::IsNullOrWhiteSpace($LauncherKey)) {
        $LauncherKey = $env:CODEX_PLUS_LAUNCHER_KEY
    }
    $state = Read-CodexRtlState
    $preferredPort = if ($state -and $state.Port) { [int]$state.Port } else { 0 }
    $port = Get-CodexRtlLaunchPort -PreferredPort $preferredPort -LauncherKey $LauncherKey
    if (([string]::IsNullOrWhiteSpace($LauncherKey)) -and $state -and $state.Port -ne $port) {
        $state.Port = $port
        $state.UpdatedAt = [DateTimeOffset]::Now.ToString('o')
        Save-CodexRtlState -State $state
    }
    if (Invoke-CodexLaunchRecoveryCheck) {
        return
    }
    if ($env:CODEX_PLUS_DESKTOP_LAUNCH -eq '1') {
        Invoke-CodexGraphicsDriverCheck | Out-Null
    }
    Start-CodexForRtl -Inspection $installInfo -Port $port -LauncherKey $LauncherKey | Out-Null
    Start-Sleep -Seconds 5
    Invoke-CodexRtlInjection -Port $port | Out-Null
    Wait-CodexWindowTitleSync -Port $port -LauncherKey $LauncherKey | Out-Null
}
