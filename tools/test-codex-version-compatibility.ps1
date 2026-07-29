param(
    [int]$Port,
    [AllowEmptyString()][string]$ExpectedProfile,
    [switch]$OfflineOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $repoRoot 'patch.ps1'
$devToolsScript = Join-Path $PSScriptRoot 'invoke-codex-devtools.ps1'
$mouseScript = Join-Path $PSScriptRoot 'invoke-codex-devtools-mouse.ps1'

. $patchScript -SkipMain

function Assert-CodexCompatibility {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-CodexPlusSourceFingerprint {
    $files = @(
        Get-Item -LiteralPath $patchScript
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Recurse -File -Filter '*.ps1'
    ) | Sort-Object FullName

    $manifest = foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\').Replace('\', '/')
        '{0}:{1}' -f $relativePath, (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest -join "`n"))
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Invoke-CodexOfflineCompatibilityTests {
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.tests.ps1' | Sort-Object Name)
    Assert-CodexCompatibility ($tests.Count -gt 0) 'No Codex Plus tests were found.'

    foreach ($test in $tests) {
        Write-Host ("[offline] {0}" -f $test.Name) -ForegroundColor Cyan
        & powershell.exe -NoProfile -File $test.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "Offline compatibility test failed: $($test.Name)"
        }
    }
}

function Invoke-CodexLiveExpression {
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$TargetId,
        [Parameter(Mandatory)][string]$Expression
    )

    $raw = & powershell.exe -NoProfile -File $devToolsScript -Port $DebugPort -Id $TargetId -Expression $Expression 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Codex DevTools expression failed:`n$($raw | Out-String)"
    }
    $response = ($raw | Out-String) | ConvertFrom-Json
    if ($response.result.exceptionDetails) {
        throw "Codex DevTools expression raised an exception: $($response.result.exceptionDetails.text)"
    }
    return $response.result.result.value
}

function Invoke-CodexLiveMouseClick {
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$TargetId,
        [Parameter(Mandatory)][double]$X,
        [Parameter(Mandatory)][double]$Y
    )

    & powershell.exe -NoProfile -File $mouseScript -Port $DebugPort -Id $TargetId -X $X -Y $Y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Codex DevTools mouse click failed at ($X, $Y)."
    }
}

function Get-CodexCompatibilityMainTargetId {
    param([Parameter(Mandatory)][int]$DebugPort)

    $targets = @(Wait-CodexDevToolsTargets -Port $DebugPort -TimeoutSeconds 10 |
        Where-Object { (Test-CodexDevToolsTarget -Target $_) -and ([string]$_.url -eq 'app://-/index.html') })
    if ($targets.Count -ne 1) { return '' }
    return [string]$targets[0].id
}

function Get-CodexCompatibilityInstance {
    param([Parameter(Mandatory)][int]$DebugPort)

    $matches = @(
        Get-CodexDesktopProcesses |
            Where-Object { Test-CodexProcessIsBrowserProcess -Process $_ } |
            Where-Object { (Get-CodexProcessRtlDebugPort -Process $_) -eq $DebugPort }
    )
    Assert-CodexCompatibility ($matches.Count -eq 1) "Expected exactly one Codex Plus browser process on port $DebugPort; found $($matches.Count)."

    $process = $matches[0]
    [pscustomobject]@{
        ProcessId = [int]$process.ProcessId
        Port = $DebugPort
        Profile = Get-CodexProcessUserDataDirectory -Process $process
        CommandLine = [string]$process.CommandLine
    }
}

function Wait-CodexCompatibilitySurface {
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$TargetId,
        [int]$TimeoutSeconds = 45
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $state = Invoke-CodexLiveExpression -DebugPort $DebugPort -TargetId $TargetId -Expression @'
JSON.stringify({
  paging: Boolean(window.__CODEX_PLUS_SIDEBAR_PAGING?.observer),
  rtl: Boolean(window.__CODEX_RTL_FIX_CODEX?.observer),
  main: Boolean(document.querySelector('main')),
  sidebar: Boolean(document.querySelector('[data-app-action-sidebar-scroll]')),
  recents: document.querySelectorAll('[data-codex-plus-sidebar-synthetic-row="threads"]').length
})
'@ | ConvertFrom-Json
            if ($state.paging -and $state.rtl -and $state.main -and $state.sidebar -and $state.recents -gt 0) {
                return $state
            }
        } catch {
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Codex Plus did not mount its injected sidebar and RTL surfaces on port $DebugPort within $TimeoutSeconds seconds."
}

function Get-CodexLiveContract {
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$TargetId
    )

    $expression = @'
(async () => {
  const getFiber = (element) => {
    const key = element && Object.keys(element).find((candidate) => candidate.startsWith('__reactFiber$'));
    return key ? element[key] : null;
  };
  const getFiberFromSubtree = (element) => {
    const direct = getFiber(element);
    if (direct) return direct;
    for (const descendant of Array.from(element?.querySelectorAll('*') || [])) {
      const fiber = getFiber(descendant);
      if (fiber) return fiber;
    }
    return null;
  };
  const candidates = [
    ...Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-id]')),
    ...Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
  ];
  let scope = null;
  let navigator = null;
  let routerLocation = null;
  for (const candidate of candidates) {
    let fiber = getFiberFromSubtree(candidate);
    let depth = 0;
    while (fiber && depth < 200) {
      const props = fiber.memoizedProps;
      if (!navigator && props?.location && typeof props?.navigator?.push === 'function') {
        navigator = props.navigator;
        routerLocation = props.location;
      }
      let hook = fiber.memoizedState;
      let hookDepth = 0;
      while (!scope && hook && hookDepth < 100) {
        const value = hook.memoizedState?.current;
        if (value?.node?.store && typeof value.get === 'function' && typeof value.set === 'function') {
          scope = value;
        }
        hook = hook.next;
        hookDepth += 1;
      }
      fiber = fiber.return;
      depth += 1;
    }
    if (scope && navigator) break;
  }

  const moduleSourceUrls = [
    ...Array.from(document.scripts).map((script) => script.src),
    ...Array.from(document.querySelectorAll('link[rel="modulepreload"]')).map((link) => link.href)
  ].filter(Boolean);
  const mainScriptUrl = moduleSourceUrls[0] || '';
  let navigationAsset = '';
  let appServerAsset = '';
  let assetSourceUrl = mainScriptUrl;
  let navigation = null;
  let appServer = null;
  let moduleError = '';
  if (moduleSourceUrls.length) {
    try {
      const sourceTexts = await Promise.all(moduleSourceUrls.map(async (sourceUrl) => ({
        sourceUrl,
        source: await (await fetch(sourceUrl)).text()
      })));
      const findAsset = (prefix) => {
        for (const candidate of sourceTexts) {
          const markerIndex = candidate.source.indexOf(prefix + '-');
          if (markerIndex < 0) continue;
          const extensionIndex = candidate.source.indexOf('.js', markerIndex);
          if (extensionIndex < 0) continue;
          assetSourceUrl = candidate.sourceUrl;
          return candidate.source.slice(markerIndex, extensionIndex + 3);
        }
        return '';
      };
      navigationAsset = findAsset('sidebar-thread-navigation');
      appServerAsset = findAsset('app-server-manager-signals');
      if (navigationAsset && appServerAsset) {
        [navigation, appServer] = await Promise.all([
          import(new URL(navigationAsset, assetSourceUrl).href),
          import(new URL(appServerAsset, assetSourceUrl).href)
        ]);
      }
    } catch (error) {
      moduleError = String(error);
    }
  }

  let manager = null;
  let managerError = '';
  try {
    manager = scope && appServer?.c ? scope.get(appServer.c, 'local') : null;
  } catch (error) {
    managerError = String(error);
  }
  if (!manager && scope?.node?.familyBindings?.entries) {
    // Codex 26.721 folds the app-server manager into an enumerable signal
    // family instead of exposing the old app-server binding chunk.
    for (const [family, members] of scope.node.familyBindings.entries()) {
      for (const [key] of members?.entries?.() || []) {
        try {
          const candidate = scope.get(family, key);
          if (candidate && typeof candidate.activateThreadSummary === 'function') {
            manager = candidate;
            break;
          }
        } catch {
        }
      }
      if (manager) break;
    }
  }

  return JSON.stringify({
    globals: {
      rtlShared: Boolean(window.__CODEX_RTL_SHARED_HELPERS),
      rtl: Boolean(window.__CODEX_RTL_FIX_CODEX?.observer),
      plan: Boolean(window.__CODEX_PLUS_RTL_PLAN?.observer),
      paging: Boolean(window.__CODEX_PLUS_SIDEBAR_PAGING?.observer),
      modelSelector: Boolean(window.__CODEX_PLUS_SPLIT_MODEL_EFFORT_SELECTOR),
      projectGuard: Boolean(window.__CODEX_PLUS_PROJECT_SELECTOR_GUARD?.observer),
      contextBadge: Boolean(window.__CODEX_PLUS_CONTEXT_BADGE?.observer)
    },
    dom: {
      main: Boolean(document.querySelector('main')),
      sidebar: Boolean(document.querySelector('[data-app-action-sidebar-scroll]')),
      syntheticList: Boolean(document.querySelector('[data-codex-plus-sidebar-synthetic-list="threads"]')),
      syntheticRows: document.querySelectorAll('[data-codex-plus-sidebar-synthetic-row="threads"]').length
    },
    react: {
      scope: Boolean(scope),
      navigator: Boolean(navigator),
      pathname: String(routerLocation?.pathname || '')
    },
    modules: {
      mainScript: Boolean(mainScriptUrl),
      navigationAsset,
      appServerAsset,
      navigationFunction: typeof navigation?.t,
      appServerBinding: typeof appServer?.c,
      optionalPrepare: typeof appServer?.Et,
      manager: Boolean(manager),
      bundleManager: Boolean(manager && !appServer),
      activateThreadSummary: typeof manager?.activateThreadSummary,
      getConversation: typeof manager?.getConversation,
      moduleError,
      managerError
    }
  });
})()
'@
    return (Invoke-CodexLiveExpression -DebugPort $DebugPort -TargetId $TargetId -Expression $expression) | ConvertFrom-Json
}

function Assert-CodexLiveContract {
    param([Parameter(Mandatory)]$Contract)

    foreach ($property in @('rtlShared', 'rtl', 'plan', 'paging', 'modelSelector', 'projectGuard', 'contextBadge')) {
        Assert-CodexCompatibility ([bool]$Contract.globals.$property) "Injected Codex Plus global '$property' is missing."
    }
    Assert-CodexCompatibility ([bool]$Contract.dom.main) 'The Codex main surface is missing.'
    Assert-CodexCompatibility ([bool]$Contract.dom.sidebar) 'The Codex sidebar surface is missing.'
    Assert-CodexCompatibility ([bool]$Contract.dom.syntheticList) 'The synthetic Recents list is missing.'
    Assert-CodexCompatibility ([int]$Contract.dom.syntheticRows -gt 0) 'The synthetic Recents list has no thread rows.'
    Assert-CodexCompatibility ([bool]$Contract.react.scope) 'Codex React app scope could not be resolved.'
    Assert-CodexCompatibility ([bool]$Contract.react.navigator) 'Codex React Router navigator could not be resolved.'
    if (-not $Contract.modules.bundleManager) {
        Assert-CodexCompatibility (-not [string]::IsNullOrWhiteSpace([string]$Contract.modules.navigationAsset)) 'The sidebar-thread-navigation asset could not be resolved.'
        Assert-CodexCompatibility (-not [string]::IsNullOrWhiteSpace([string]$Contract.modules.appServerAsset)) 'The app-server-manager-signals asset could not be resolved.'
        Assert-CodexCompatibility ($Contract.modules.navigationFunction -eq 'function') 'The sidebar navigation export is no longer callable.'
        Assert-CodexCompatibility ($Contract.modules.appServerBinding -eq 'object') 'The app-server manager binding changed shape.'
    }
    Assert-CodexCompatibility ([bool]$Contract.modules.manager) 'The local app-server manager could not be resolved.'
    Assert-CodexCompatibility ($Contract.modules.activateThreadSummary -eq 'function') 'activateThreadSummary is no longer callable.'
    Assert-CodexCompatibility ([string]::IsNullOrWhiteSpace([string]$Contract.modules.moduleError)) "Codex module import failed: $($Contract.modules.moduleError)"
    Assert-CodexCompatibility ([string]::IsNullOrWhiteSpace([string]$Contract.modules.managerError)) "Codex manager lookup failed: $($Contract.modules.managerError)"
}

function Get-CodexSyntheticNavigationTarget {
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$TargetId
    )

    $expression = @'
JSON.stringify((() => {
  const normalize = (value) => String(value || '').trim().toLowerCase().replace(/^(?:local|remote):/, '');
  const projectRows = Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'));
  const isProjectClosed = (projectId) => {
    const normalized = normalize(projectId);
    const projectRow = projectRows.find((row) => {
      const direct = row.getAttribute('data-app-action-sidebar-project-id');
      const nested = row.querySelector('[data-app-action-sidebar-project-id]')?.getAttribute('data-app-action-sidebar-project-id');
      return normalize(direct || nested) === normalized;
    });
    if (!projectRow) return { closed: true, present: false, expanded: false };
    const expanded = projectRow.getAttribute('aria-expanded') === 'true'
      || projectRow.getAttribute('data-app-action-sidebar-project-collapsed') === 'false';
    return { closed: !expanded, present: true, expanded };
  };
  const rows = Array.from(document.querySelectorAll('[data-codex-plus-sidebar-synthetic-row="threads"]'));
  for (const row of rows) {
    const threadId = normalize(row.getAttribute('data-codex-plus-thread-id'));
    const projectId = row.getAttribute('data-codex-plus-source-project-id') || '';
    const sourceText = row.getAttribute('data-codex-plus-source-row-text') || '';
    const projectState = isProjectClosed(projectId);
    const button = row.querySelector('[role="button"]');
    const rect = button?.getBoundingClientRect();
    if (
      threadId
      && projectId
      && sourceText
      && projectState.closed
      && row.getAttribute('data-app-action-sidebar-thread-active') !== 'true'
      && !row.hidden
      && rect
      && rect.width > 0
      && rect.height > 0
    ) {
      return {
        threadId,
        projectId,
        sourceText,
        projectState,
        rowText: row.innerText,
        x: rect.x + rect.width / 2,
        y: rect.y + rect.height / 2,
        beforeMainText: document.querySelector('main')?.innerText || ''
      };
    }
  }

  const list = document.querySelector('[data-codex-plus-sidebar-synthetic-list="threads"]');
  const showMore = Array.from(list?.querySelectorAll('button') || []).find((button) => button.innerText.trim() === 'Show more' && !button.hidden);
  const pagerRect = showMore?.getBoundingClientRect();
  return {
    threadId: '',
    pager: pagerRect && pagerRect.width > 0 && pagerRect.height > 0
      ? { x: pagerRect.x + pagerRect.width / 2, y: pagerRect.y + pagerRect.height / 2 }
      : null
  };
})())
'@

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $result = (Invoke-CodexLiveExpression -DebugPort $DebugPort -TargetId $TargetId -Expression $expression) | ConvertFrom-Json
        if ($result.threadId) { return $result }
        if (-not $result.pager) { break }
        Invoke-CodexLiveMouseClick -DebugPort $DebugPort -TargetId $TargetId -X $result.pager.x -Y $result.pager.y
        Start-Sleep -Milliseconds 300
    }
    throw 'No visible, inactive synthetic project thread with a closed source project was available for the live navigation test.'
}

function Wait-CodexSyntheticNavigation {
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$TargetId,
        [Parameter(Mandatory)]$NavigationTarget,
        [int]$TimeoutSeconds = 20
    )

    $targetJson = $NavigationTarget | ConvertTo-Json -Depth 8 -Compress
    $targetJsonBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($targetJson))
    $expression = @"
JSON.stringify((() => {
  const target = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$targetJsonBase64'), (value) => value.charCodeAt(0))));
  const normalize = (value) => String(value || '').trim().toLowerCase().replace(/^(?:local|remote):/, '');
  const row = Array.from(document.querySelectorAll('[data-codex-plus-sidebar-synthetic-row]'))
    .filter((candidate) => candidate.getAttribute('data-codex-plus-sidebar-synthetic-row') === 'threads')
    .find((candidate) => normalize(candidate.getAttribute('data-codex-plus-thread-id')) === normalize(target.threadId));
  const mainText = document.querySelector('main')?.innerText || '';
  const projectRows = Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'));
  const projectRow = projectRows.find((candidate) => {
    const direct = candidate.getAttribute('data-app-action-sidebar-project-id');
    const nested = candidate.querySelector('[data-app-action-sidebar-project-id]')?.getAttribute('data-app-action-sidebar-project-id');
    return normalize(direct || nested) === normalize(target.projectId);
  });
  const projectExpanded = projectRow && (
    projectRow.getAttribute('aria-expanded') === 'true'
    || projectRow.getAttribute('data-app-action-sidebar-project-collapsed') === 'false'
  );
  const active = row?.getAttribute('data-app-action-sidebar-thread-active') === 'true';
  const mainChanged = mainText.trim() && mainText !== target.beforeMainText;
  const titleVisible = mainText.toLowerCase().includes(String(target.sourceText || '').toLowerCase());
  const projectStayedClosed = target.projectState.present
    ? Boolean(projectRow) && !projectExpanded
    : !projectRow;
  return {
    ready: Boolean(active && mainChanged && titleVisible && projectStayedClosed),
    active,
    mainChanged: Boolean(mainChanged),
    titleVisible,
    projectStayedClosed,
    mainText: mainText.slice(0, 800)
  };
})())
"@

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastResult = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        # A real synthetic-row click can reload the renderer in newer Codex
        # builds, which replaces the DevTools target id. Re-resolve the exact
        # main app target while polling instead of pinning the pre-click id.
        $currentTargetId = Get-CodexCompatibilityMainTargetId -DebugPort $DebugPort
        if ([string]::IsNullOrWhiteSpace($currentTargetId)) { $currentTargetId = $TargetId }
        try {
            $lastResult = (Invoke-CodexLiveExpression -DebugPort $DebugPort -TargetId $currentTargetId -Expression $expression) | ConvertFrom-Json
        } catch {
            Start-Sleep -Milliseconds 250
            continue
        }
        if ($lastResult.ready) { return $lastResult }
        Start-Sleep -Milliseconds 250
    }
    $details = if ($lastResult) { $lastResult | ConvertTo-Json -Depth 8 -Compress } else { 'no result' }
    throw "Synthetic thread navigation did not complete successfully: $details"
}

Invoke-CodexOfflineCompatibilityTests

$installInfo = Get-CodexInstallInfo
Assert-CodexCompatibility ([bool]$installInfo.PackageFound) 'Codex Desktop is not installed.'
Assert-CodexCompatibility (-not [string]::IsNullOrWhiteSpace([string]$installInfo.PackageVersion)) 'The installed Codex package version could not be read.'
$sourceFingerprint = Get-CodexPlusSourceFingerprint

if ($OfflineOnly) {
    Write-Host "Offline compatibility tests passed for Codex $($installInfo.PackageVersion)." -ForegroundColor Green
    return
}

Assert-CodexCompatibility ($Port -gt 0) 'Pass -Port with the debug port of the fresh Codex Plus instance launched from this chat.'

$recordPath = Join-Path (Get-CodexRtlStateRoot) 'compatibility.json'
$existingRecord = $null
if (Test-Path -LiteralPath $recordPath) {
    try { $existingRecord = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } catch { }
}
if ((-not $Force) -and $existingRecord -and
    [string]$existingRecord.PackageVersion -eq [string]$installInfo.PackageVersion -and
    [string]$existingRecord.SourceFingerprint -eq $sourceFingerprint) {
    Write-Host "Codex $($installInfo.PackageVersion) with this Codex Plus source already passed the live compatibility gate at $($existingRecord.VerifiedAt)." -ForegroundColor Green
    return
}

$instance = Get-CodexCompatibilityInstance -DebugPort $Port
if (-not [string]::IsNullOrWhiteSpace($ExpectedProfile)) {
    $expected = Normalize-CodexRtlMatchPath -Path $ExpectedProfile
    $actual = Normalize-CodexRtlMatchPath -Path $instance.Profile
    Assert-CodexCompatibility ($actual -eq $expected) "Port $Port belongs to profile '$($instance.Profile)', not expected profile '$ExpectedProfile'."
}

$targets = @(Wait-CodexDevToolsTargets -Port $Port -TimeoutSeconds 45 | Where-Object { Test-CodexDevToolsTarget -Target $_ })
# Recent Codex builds expose a second app:// page for the avatar overlay. The
# main renderer remains the target whose URL is exactly app://-/index.html.
$mainTargets = @($targets | Where-Object { [string]$_.url -eq 'app://-/index.html' })
if ($mainTargets.Count -eq 1) {
    $target = $mainTargets[0]
} else {
    Assert-CodexCompatibility ($targets.Count -eq 1) "Expected one main app:// Codex target on port $Port; found $($targets.Count) app targets and $($mainTargets.Count) exact main targets."
    $target = $targets[0]
}

Write-Host "[live] Codex $($installInfo.PackageVersion), port $Port, profile $($instance.Profile)" -ForegroundColor Cyan
Wait-CodexCompatibilitySurface -DebugPort $Port -TargetId $target.id | Out-Null
$contract = Get-CodexLiveContract -DebugPort $Port -TargetId $target.id
Assert-CodexLiveContract -Contract $contract

$navigationTarget = Get-CodexSyntheticNavigationTarget -DebugPort $Port -TargetId $target.id
Write-Host "[live] Opening synthetic thread '$($navigationTarget.sourceText)' while project '$($navigationTarget.projectId)' is closed." -ForegroundColor Cyan
Invoke-CodexLiveMouseClick -DebugPort $Port -TargetId $target.id -X $navigationTarget.x -Y $navigationTarget.y
$navigationResult = Wait-CodexSyntheticNavigation -DebugPort $Port -TargetId $target.id -NavigationTarget $navigationTarget

$record = [pscustomobject]@{
    SchemaVersion = 1
    PackageVersion = [string]$installInfo.PackageVersion
    SourceFingerprint = $sourceFingerprint
    Result = 'passed'
    VerifiedAt = [DateTimeOffset]::Now.ToString('o')
    ProcessId = $instance.ProcessId
    Port = $Port
    Profile = $instance.Profile
    TargetId = [string]$target.id
    NavigationThreadId = [string]$navigationTarget.threadId
    NavigationTitle = [string]$navigationTarget.sourceText
    Checks = @(
        'offline-suite',
        'injected-globals',
        'sidebar-dom',
        'react-app-scope',
        'react-router-navigator',
        'bundled-navigation-modules',
        'local-app-server-manager',
        'closed-project-synthetic-thread-navigation'
    )
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding UTF8

Write-Host "Codex $($installInfo.PackageVersion) passed the complete compatibility gate." -ForegroundColor Green
Write-Host "Recorded: $recordPath" -ForegroundColor Green
