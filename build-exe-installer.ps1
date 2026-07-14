[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root 'dist\CodexPlus-Setup.exe' }
$stage = Join-Path $env:TEMP ("codex-plus-ps2exe-" + [guid]::NewGuid().ToString('N'))
$wrapper = Join-Path $stage 'setup-wrapper.ps1'
$files = @('install.ps1','patch.ps1') + @(Get-ChildItem (Join-Path $root 'src') -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
try {
  New-Item -ItemType Directory -Force $stage | Out-Null
  $payload = foreach ($relative in $files) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root $relative))
    $encoded = [Convert]::ToBase64String($bytes)
    "  @{ Path = '$relative'; Data = '$encoded' }"
  }
  @"
`$ErrorActionPreference = 'Stop'
`$root = Join-Path `$env:TEMP ('CodexPlus-Setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force `$root | Out-Null
try {
  `$payload = @(
$($payload -join "`r`n")
  )
  foreach (`$item in `$payload) {
    `$path = Join-Path `$root `$item.Path
    New-Item -ItemType Directory -Force (Split-Path `$path) | Out-Null
    [IO.File]::WriteAllBytes(`$path, [Convert]::FromBase64String(`$item.Data))
  }
  `$psi = [Diagnostics.ProcessStartInfo]::new()
  `$psi.FileName = 'powershell.exe'
  `$psi.UseShellExecute = `$false
  `$scriptPath = Join-Path `$root 'install.ps1'
  `$psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + `$scriptPath + '" -LocalDev'
  `$process = [Diagnostics.Process]::Start(`$psi)
  `$process.WaitForExit()
  if (`$process.ExitCode -ne 0) { throw "Installer exited with code `$(`$process.ExitCode)." }
  exit 0
} catch {
  Write-Host ''
  Write-Host 'Codex Plus installation failed:' -ForegroundColor Red
  Write-Host `$_.Exception.Message -ForegroundColor Yellow
  Write-Host ''
  Read-Host 'Press Enter to close'
  exit 1
} finally { Remove-Item `$root -Recurse -Force -ErrorAction SilentlyContinue }
"@ | Set-Content $wrapper -Encoding UTF8
  Import-Module ps2exe
  New-Item -ItemType Directory -Force (Split-Path $OutputPath -Parent) | Out-Null
  Invoke-PS2EXE -inputFile $wrapper -outputFile $OutputPath -x64 -conHost -title 'Codex Plus Setup' -product 'Codex Plus' -version '1.0.0.0'
  if (-not (Test-Path $OutputPath)) { throw 'PS2EXE did not create the installer.' }
  Write-Host "Created $OutputPath" -ForegroundColor Green
} finally { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
