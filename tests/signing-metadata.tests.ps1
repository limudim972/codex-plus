$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) {
        throw "$Message Pattern '$Pattern' was not found."
    }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        throw "$Message Pattern '$Pattern' should not be present."
    }
}

$install = Get-Content (Join-Path $repoRoot 'install.ps1') -Raw
$patch = Get-Content (Join-Path $repoRoot 'patch.ps1') -Raw
$readme = Get-Content (Join-Path $repoRoot 'README.md') -Raw

$expectedRepoBase = 'https://raw.githubusercontent.com/limudim972/codex-plus/main'

Assert-Match $install ([regex]::Escape($expectedRepoBase)) 'install.ps1 should download from Codex Plus.'
Assert-Match $readme ([regex]::Escape('irm https://raw.githubusercontent.com/limudim972/codex-plus/main/install.ps1 | iex')) 'README should document the Windows PowerShell one-line installer.'
Assert-Match $readme 'Codex Plus' 'README should explain the Codex Plus shortcut behavior.'
Assert-Match $readme 'powershell\.exe' 'README should consistently direct users to Windows PowerShell.'
Assert-Match $install 'src/shared/logging\.ps1' 'install.ps1 should download the module tree needed by patch.ps1.'
Assert-Match $install 'New-Item -ItemType Directory' 'install.ps1 should create module directories in the temp patch folder.'
Assert-NotMatch $install '-NoExit' 'install.ps1 should close after it finishes instead of leaving an elevated console open.'
Assert-NotMatch $install 'patch\.ps1\.sig' 'install.ps1 should no longer depend on a signed patch artifact.'
Assert-Match $install 'Press Enter to close this window\.' 'install.ps1 should pause at the end with a clear close prompt.'
Assert-Match $install 'Launching Codex Plus from \$shortcutPath \.\.\.' 'install.ps1 should launch Codex Plus from the resolved shortcut after install completes.'
Assert-Match $install 'no launcher shortcut was found' 'install.ps1 should warn clearly when no shortcut is found.'
Assert-Match $install 'Start-Process -FilePath \$shortcutPath' 'install.ps1 should start the resolved shortcut path.'
Assert-Match $install 'Test-InstallerPortAvailable' 'install.ps1 should preflight an explicitly requested port.'
Assert-Match $install 'Requested Codex Plus port' 'install.ps1 should fail clearly when the requested port is occupied.'
Assert-Match $install 'CODEX_PLUS_REQUESTED_PORT' 'install.ps1 should forward the requested port through the Desktop launcher environment.'
Assert-Match $install 'CreateShortcut\(\$shortcutPath\)' 'install.ps1 should resolve the launcher target when it must pass an exact port.'
Assert-Match $install '\$shortcut\.TargetPath' 'install.ps1 should start the resolved launcher target with the requested port.'
Assert-Match $patch 'PreferredPort' 'patch.ps1 should accept the installer-selected port.'
Assert-Match $patch 'Launch-CodexRtl' 'patch.ps1 should expose the launcher entrypoint.'
Assert-Match $patch 'LauncherKey' 'patch.ps1 should accept a launcher identity for scoped relaunches.'
Assert-Match $install 'Codex Plus' 'install.ps1 should use Codex Plus branding.'
Assert-NotMatch $readme 'Public-key fingerprint' 'README should no longer document a signing fingerprint.'
Assert-NotMatch $readme 'verify-signature\.ps1' 'README should no longer document signature verification.'

foreach ($activeContent in @($install, $patch)) {
    Assert-NotMatch $activeContent (('cl' + 'aude')) 'Active updater/install code should not reference removed app code.'
    Assert-NotMatch $activeContent (('ai' + '-' + 'rtl' + '-' + 'fix')) 'Active updater/install code should not reference the old repo slug.'
}

Write-Host 'signing-metadata.tests.ps1 passed'
