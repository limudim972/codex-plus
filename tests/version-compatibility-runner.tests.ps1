$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $repoRoot 'tools\test-codex-version-compatibility.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $runnerPath) 'The version compatibility runner should exist under tools.'
$runner = Get-Content -LiteralPath $runnerPath -Raw

Assert-True (-not $runner.Contains('Start-Process')) 'The compatibility runner must attach to a user-launched instance and never launch Codex itself.'
Assert-True ($runner.Contains('Pass -Port with the debug port')) 'The compatibility runner should require an explicit fresh-instance debug port.'
Assert-True ($runner.Contains('ExpectedProfile')) 'The compatibility runner should verify the port/profile pair when an expected profile is supplied.'
Assert-True ($runner.Contains('Get-CodexInstallInfo')) 'The compatibility runner should read the installed Codex package version.'
Assert-True ($runner.Contains('SourceFingerprint')) 'The compatibility runner should include the Codex Plus source fingerprint in its pass record.'
Assert-True ($runner.Contains('compatibility.json')) 'The compatibility runner should store its version pass record separately from launcher state.'
Assert-True ($runner.Contains('sidebar-thread-navigation')) 'The live contract should resolve the bundled sidebar navigation asset.'
Assert-True ($runner.Contains('app-server-manager-signals')) 'The live contract should resolve the bundled app-server asset.'
Assert-True ($runner.Contains('activateThreadSummary')) 'The live contract should verify the app-server activation method.'
Assert-True ($runner.Contains('__reactFiber$')) 'The live contract should verify current React fiber access.'
Assert-True ($runner.Contains("typeof props?.navigator?.push === 'function'")) 'The live contract should verify React Router navigation.'
Assert-True ($runner.Contains('invoke-codex-devtools-mouse.ps1')) 'The navigation smoke test should use a real CDP mouse click.'
Assert-True ($runner.Contains('data-codex-plus-sidebar-synthetic-row')) 'The navigation smoke test should target the synthetic Recents row.'
Assert-True ($runner.Contains('data-app-action-sidebar-thread-active')) 'The navigation smoke test should verify the selected synthetic thread became active.'
Assert-True ($runner.Contains('projectStayedClosed')) 'The navigation smoke test should verify the source project stayed closed.'
Assert-True ($runner.Contains("Result = 'passed'")) 'The runner should record only an explicit passing result.'

Write-Host 'version-compatibility-runner.tests.ps1 passed'
