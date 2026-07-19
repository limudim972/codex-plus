function Get-CodexProcessSuspensionState {
    param([Parameter(Mandatory)][int]$ProcessId)

    try {
        if (-not ('CodexPlus.NativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexPlus {
    public static class NativeMethods {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenThread(uint access, bool inheritHandle, uint threadId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("ntdll.dll")]
        public static extern int NtQueryInformationThread(
            IntPtr threadHandle,
            int threadInformationClass,
            out int threadInformation,
            int threadInformationLength,
            IntPtr returnLength);
    }
}
'@ -ErrorAction Stop
        }

        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $queried = 0
        $suspended = 0
        foreach ($thread in @($process.Threads)) {
            $handle = [CodexPlus.NativeMethods]::OpenThread(0x0040 -bor 0x0800, $false, [uint32]$thread.Id)
            if ($handle -eq [IntPtr]::Zero) { continue }
            try {
                [int]$suspendCount = 0
                $result = [CodexPlus.NativeMethods]::NtQueryInformationThread(
                    $handle, 35, [ref]$suspendCount, [Runtime.InteropServices.Marshal]::SizeOf([int]), [IntPtr]::Zero)
                if ($result -eq 0) {
                    $queried++
                    if ($suspendCount -gt 0) { $suspended++ }
                }
            } finally {
                [CodexPlus.NativeMethods]::CloseHandle($handle) | Out-Null
            }
        }

        [pscustomobject]@{
            ProcessId = $ProcessId
            ThreadsQueried = $queried
            ThreadsSuspended = $suspended
            AllThreadsSuspended = ($queried -gt 0 -and $suspended -eq $queried)
        }
    } catch {
        return $null
    }
}

function Get-CodexSuspendedHeadlessProcess {
    param([int]$MinimumSeconds = 5)

    foreach ($process in @(Get-CodexDesktopProcesses)) {
        # Electron creates normal hidden ChatGPT.exe children for GPU, renderer,
        # utility, and crashpad work. Only inspect the parent desktop process.
        if ([string]$process.CommandLine -match '\s--type=') { continue }
        if (Test-CodexProcessHasVisibleWindow -Process $process) { continue }
        $before = Get-CodexProcessSuspensionState -ProcessId ([int]$process.ProcessId)
        if (-not $before -or -not $before.AllThreadsSuspended) { continue }
        Start-Sleep -Seconds $MinimumSeconds
        $after = Get-CodexProcessSuspensionState -ProcessId ([int]$process.ProcessId)
        if ($after -and $after.AllThreadsSuspended) {
            return [pscustomobject]@{
                Process = $process
                DurationSeconds = $MinimumSeconds
                Suspension = $after
            }
        }
    }
    return $null
}

function Invoke-CodexLaunchRecoveryCheck {
    $stalled = Get-CodexSuspendedHeadlessProcess -MinimumSeconds 5
    if (-not $stalled) { return $false }

    $message = "Codex appears to be suspended and has no visible window for at least $($stalled.DurationSeconds) seconds.`n`nRecommended recovery:`n1. Uninstall Codex.`n2. Reboot Windows.`n3. Reinstall Codex from the Microsoft Store.`n`nCodex Plus will not start another Codex process until the suspended one is resolved."
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($message, 'Codex launch recovery required', 'OK', 'Error') | Out-Null
    } catch {
        Write-Warn $message
    }
    return $true
}

function Get-CodexGraphicsDriverStatus {
    try {
        $adapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic Display Adapter' } |
            Select-Object -First 1

        if (-not $adapter) {
            return [pscustomobject]@{
                Found = $false
                NeedsAttention = $true
                Name = 'Unknown graphics adapter'
                DriverVersion = ''
                DriverDate = $null
                UpdateUrl = 'https://www.amd.com/en/support'
                Reason = 'No usable graphics adapter was detected.'
            }
        }

        $recentFault = $false
        try {
            $recentFault = [bool](Get-WinEvent -FilterHashtable @{
                LogName = 'Application'
                StartTime = (Get-Date).AddDays(-7)
            } -ErrorAction Stop | Where-Object {
                $_.ProviderName -eq 'Windows Error Reporting' -and
                $_.Message -match 'Event Name: (LiveKernelEvent|AppHang)' -and
                $_.Message -match 'P1: (141|117|193|1b0)'
            } | Select-Object -First 1)
        } catch {
            # Event log access is optional; adapter health remains useful by itself.
        }

        $updateUrl = if ($adapter.Name -match 'Radeon|AMD') {
            'https://www.amd.com/en/support/download/drivers.html'
        } elseif ($adapter.Name -match 'NVIDIA|GeForce|Quadro') {
            'https://www.nvidia.com/Download/index.aspx'
        } elseif ($adapter.Name -match 'Intel') {
            'https://www.intel.com/content/www/us/en/support/detect.html'
        } else {
            'ms-settings:windowsupdate'
        }

        $driverDate = $null
        if ($adapter.DriverDate) {
            try { $driverDate = [Management.ManagementDateTimeConverter]::ToDateTime($adapter.DriverDate) } catch { }
            if (-not $driverDate) {
                try { $driverDate = [DateTime]$adapter.DriverDate } catch { }
            }
        }

        $statusText = [string]$adapter.Status
        $needsAttention = $statusText -and $statusText -ne 'OK' -or $recentFault
        $reason = if ($recentFault) {
            'Windows recently reported a graphics-driver timeout or app hang.'
        } elseif ($statusText -and $statusText -ne 'OK') {
            "Windows reports the adapter status as $statusText."
        } else {
            ''
        }

        return [pscustomobject]@{
            Found = $true
            NeedsAttention = [bool]$needsAttention
            Name = [string]$adapter.Name
            DriverVersion = [string]$adapter.DriverVersion
            DriverDate = $driverDate
            UpdateUrl = $updateUrl
            Reason = $reason
        }
    } catch {
        Write-Warn "Graphics driver check failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-CodexGraphicsDriverCheck {
    $status = Get-CodexGraphicsDriverStatus
    if (-not $status -or -not $status.NeedsAttention) { return $false }

    $cachePath = Join-Path (Get-CodexRtlStateRoot) 'graphics-driver-check.json'
    $fingerprint = "$($status.Name)|$($status.DriverVersion)|$($status.DriverDate)"
    $cache = $null
    if (Test-Path -LiteralPath $cachePath) {
        try { $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json } catch { }
    }
    if ($cache -and $cache.Fingerprint -eq $fingerprint -and $cache.LastPromptAt) {
        try {
            if (([DateTimeOffset]$cache.LastPromptAt).AddDays(7) -gt [DateTimeOffset]::Now) { return $false }
        } catch { }
    }

    $driverDateText = if ($status.DriverDate) { $status.DriverDate.ToString('yyyy-MM-dd') } else { 'unknown' }
    $message = "Codex detected a possible graphics-driver problem.`n`nAdapter: $($status.Name)`nDriver: $($status.DriverVersion) ($driverDateText)`n$($status.Reason)`n`nWould you like to open the official driver update page?"
    $answer = $null
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $answer = [System.Windows.MessageBox]::Show($message, 'Codex graphics driver check', 'YesNo', 'Warning')
    } catch {
        Write-Warn $message
    }

    [pscustomobject]@{
        Fingerprint = $fingerprint
        LastPromptAt = [DateTimeOffset]::Now.ToString('o')
        LastReason = $status.Reason
    } | ConvertTo-Json | Set-Content -LiteralPath $cachePath -Encoding UTF8

    if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-Process -FilePath $status.UpdateUrl
        return $true
    }
    return $false
}
