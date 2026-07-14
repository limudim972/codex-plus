[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root 'dist\CodexPlus-Setup.exe' }
$output = [IO.Path]::GetFullPath($OutputPath)
$stage = Join-Path $env:TEMP ("codex-plus-iexpress-" + [guid]::NewGuid().ToString('N'))
$sed = Join-Path $env:TEMP ("codex-plus-iexpress-" + [guid]::NewGuid().ToString('N') + '.sed')
$files = @('install.ps1','patch.ps1') + @(Get-ChildItem (Join-Path $root 'src') -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
try {
  New-Item -ItemType Directory -Force $stage | Out-Null
  foreach ($relative in $files) { $dest=Join-Path $stage $relative; New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null; Copy-Item (Join-Path $root $relative) $dest }
  New-Item -ItemType Directory -Force (Split-Path $output -Parent) | Out-Null
  $lines = ($files | ForEach-Object -Begin {$i=0} -Process { "%FILE$i%="; $i++ }) -join "`r`n"
  $strings = ($files | ForEach-Object -Begin {$i=0} -Process { 'FILE{0}="{1}"' -f $i,$_; $i++ }) -join "`r`n"
  @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=1
RebootMode=N
TargetName=$output
FriendlyName=Codex Plus Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -LocalDev
PostInstallCmd=<None>
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$stage
[SourceFiles0]
$lines
[Strings]
$strings
"@ | Set-Content $sed -Encoding ASCII
  $p=Start-Process "$env:WINDIR\System32\iexpress.exe" -ArgumentList @('/N',$sed) -Wait -PassThru -WindowStyle Hidden
  if ($p.ExitCode -ne 0 -or -not (Test-Path $output)) { throw "IExpress failed with exit code $($p.ExitCode)" }
  Write-Host "Created $output" -ForegroundColor Green
} finally { Remove-Item $stage,$sed -Recurse -Force -ErrorAction SilentlyContinue }
