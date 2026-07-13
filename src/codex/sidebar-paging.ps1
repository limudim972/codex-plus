function Get-CodexSidebarPagingPayload {
    @'
(function () {
  const SECTION_SELECTOR = '[class*="group/nav-section-title"]';
  const PAGE_SIZE = 3;
  const RECENT_WINDOW_MS = 24 * 60 * 60 * 1000;
  const RECENT_THREAD_LIMIT = 12;
  const SYNTHETIC_SECTION_ATTR = 'data-codex-plus-sidebar-synthetic-section';
  const SYNTHETIC_LIST_ATTR = 'data-codex-plus-sidebar-synthetic-list';
  const SYNTHETIC_ROW_ATTR = 'data-codex-plus-sidebar-synthetic-row';
  const SOURCE_LIST_ATTR = 'data-codex-plus-source-list-label';
  const SOURCE_TEXT_ATTR = 'data-codex-plus-source-row-text';
  const NAVIGATION_PENDING_ATTR = 'data-codex-plus-thread-navigation-pending';
  const THREAD_SPINNER_ATTR = 'data-codex-plus-thread-spinner';
  const PAGER_ATTR = 'data-codex-plus-sidebar-pager';
  const ACTION_ATTR = 'data-codex-plus-sidebar-action';
  const STATE_ATTR = 'data-codex-plus-sidebar-loaded';
  const COLLAPSED_ATTR = 'data-codex-plus-sidebar-collapsed';
  const THREAD_BASE_LABEL_ATTR = 'data-codex-plus-thread-base-label';
  const THREAD_TIMESTAMP_ATTR = 'data-codex-plus-thread-timestamp-label';
  const THREAD_UPDATED_ATTR = 'data-codex-plus-thread-updated-ms';
  const THREADS_HEADER_ATTR = 'data-codex-plus-sidebar-threads-header';
  const THREADS_CONTAINER_ATTR = 'data-codex-plus-sidebar-threads-container';
  const BUTTON_CLASS = 'border-token-border no-drag cursor-interaction flex items-center gap-1 border whitespace-nowrap select-none focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 rounded-full text-token-muted-foreground enabled:hover:bg-transparent data-[state=open]:bg-transparent hover:text-token-foreground border-transparent px-2 py-0.5 text-sm leading-[18px] text-token-description-foreground hover:text-token-foreground -ml-[9px]';
  const LEGACY_TIMESTAMP_SUFFIX_SELECTOR = 'span[aria-hidden="true"].pointer-events-none.select-none.whitespace-nowrap.text-token-description-foreground';
  let internalNavigationModulesPromise = null;
  const nativeThreadTitleCache = new Map();
  let liveCatalogScope = null;
  let liveCatalogStateBinding = null;
  let liveCatalogCache = null;
  let liveCatalogThreadSignature = '';
  let liveCatalogLastRefreshMs = 0;

  const SECTION_SPECS = [
    { key: 'threads', title: 'Threads', minVisibleCount: 3, synthetic: true },
    { key: 'projects', title: 'Projects', minVisibleCount: 2 },
    { key: 'tasks', labels: ['Tasks', 'Chats'], minVisibleCount: 0 }
  ];

  function normalizeText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function textOf(element) {
    return normalizeText(element?.innerText || '');
  }

  function getSidebarSectionTitle(scopeDoc, label) {
    return Array.from(scopeDoc.querySelectorAll(SECTION_SELECTOR)).find((title) => textOf(title) === label) || null;
  }

  function getSidebarSectionListByLabel(scopeDoc, labels) {
    const normalizedLabels = (Array.isArray(labels) ? labels : [labels]).map((label) => normalizeText(label)).filter(Boolean);
    if (normalizedLabels.length === 0) return null;

    return Array.from(scopeDoc.querySelectorAll('[role="list"]')).find((list) => {
      const ariaLabel = normalizeText(list.getAttribute('aria-label'));
      return ariaLabel && normalizedLabels.includes(ariaLabel);
    }) || null;
  }

  function getNonSyntheticSidebarSectionListByLabel(scopeDoc, labels) {
    const normalizedLabels = (Array.isArray(labels) ? labels : [labels]).map((label) => normalizeText(label)).filter(Boolean);
    if (normalizedLabels.length === 0) return null;

    return Array.from(scopeDoc.querySelectorAll('[role="list"]')).find((list) => {
      const ariaLabel = normalizeText(list.getAttribute('aria-label'));
      return ariaLabel && normalizedLabels.includes(ariaLabel) && !list.hasAttribute(SYNTHETIC_LIST_ATTR);
    }) || null;
  }

  function getSidebarSectionLists(scopeDoc, predicate) {
    return Array.from(scopeDoc.querySelectorAll('[role="list"]')).filter((list) => {
      const ariaLabel = normalizeText(list.getAttribute('aria-label'));
      return ariaLabel && predicate(ariaLabel, list);
    });
  }

  function getSectionShellFromTitle(title) {
    return title?.parentElement || null;
  }

  function getSidebarSectionList(title) {
    const sectionContainer = title?.parentElement?.children?.[1];
    if (!sectionContainer) return null;

    const directList = sectionContainer.firstElementChild?.firstElementChild;
    if (directList && directList.getAttribute('role') === 'list') {
      return directList;
    }

    const fallbackList = sectionContainer.querySelector('[role="list"]');
    return fallbackList && fallbackList.getAttribute('role') === 'list' ? fallbackList : null;
  }

  function resolveSidebarSectionList(spec) {
    const directList = getSidebarSectionListByLabel(document, spec.labels);
    if (directList) return directList;

    if (!spec.title) return null;
    const heading = getSidebarSectionTitle(document, spec.title);
    return getSidebarSectionList(heading);
  }

  function getSidebarRows(sectionList) {
    return Array.from(sectionList?.children || []).filter((row) => row.getAttribute('role') === 'listitem' && !row.hasAttribute(PAGER_ATTR));
  }

  function normalizeProjectId(value) {
    return String(value || '').trim().replace(/\//g, '\\').replace(/\\+$/g, '').toLowerCase();
  }

  function normalizeThreadId(value) {
    return String(value || '').trim().toLowerCase().replace(/^(?:local|remote):/, '');
  }

  function getProjectIdForRow(row) {
    if (!row) return '';
    const direct = row.getAttribute('data-app-action-sidebar-project-id');
    if (direct) return direct;
    const nested = row.querySelector('[data-app-action-sidebar-project-id]');
    return nested ? nested.getAttribute('data-app-action-sidebar-project-id') : '';
  }

  function getThreadIdForRow(row) {
    if (!row) return '';
    const direct = row.getAttribute('data-app-action-sidebar-thread-id');
    if (direct) return direct;
    const nested = row.querySelector('[data-app-action-sidebar-thread-id]');
    return nested ? nested.getAttribute('data-app-action-sidebar-thread-id') : '';
  }

  // Remote project rows keep their metadata in React props, not in the DOM.
  function getReactFiberForElement(element) {
    if (!element) return null;
    const fiberKey = Object.keys(element).find((key) => key.startsWith('__reactFiber$'));
    return fiberKey ? element[fiberKey] : null;
  }

  function getReactFiberCandidates(element) {
    const fibers = [];
    const seen = new Set();
    const add = (candidate) => {
      const fiber = getReactFiberForElement(candidate);
      if (fiber && !seen.has(fiber)) {
        seen.add(fiber);
        fibers.push(fiber);
      }
    };

    add(element);
    for (const descendant of Array.from(element?.querySelectorAll('*') || [])) {
      add(descendant);
    }
    return fibers;
  }

  function getReactThreadStatusState(row) {
    for (const fiber of getReactFiberCandidates(row)) {
      let currentFiber = fiber;
      let fiberDepth = 0;
      while (currentFiber && fiberDepth < 40) {
        const statusState = currentFiber.memoizedProps?.statusState;
        if (statusState && typeof statusState.type === 'string') {
          return statusState;
        }
        currentFiber = currentFiber.return;
        fiberDepth += 1;
      }
    }
    return null;
  }

  function getNativeThreadRows() {
    const rows = new Set();
    const candidates = document.querySelectorAll(
      '[data-app-action-sidebar-thread-row], [data-app-action-sidebar-thread-id]'
    );
    for (const candidate of Array.from(candidates)) {
      if (candidate.closest('[' + SYNTHETIC_ROW_ATTR + '="threads"]')) continue;
      const row = candidate.closest('[role="listitem"]') || candidate;
      if (getThreadIdForRow(row)) {
        rows.add(row);
      }
    }
    return Array.from(rows);
  }

  function getWorkingThreadIds() {
    const workingThreadIds = new Set();
    for (const row of getNativeThreadRows()) {
      const threadId = normalizeThreadId(getThreadIdForRow(row));
      const statusState = getReactThreadStatusState(row);
      if (threadId && statusState?.type === 'loading') {
        workingThreadIds.add(threadId);
      }
    }
    return workingThreadIds;
  }

  function getReactFiberFromSubtree(element) {
    const directFiber = getReactFiberForElement(element);
    if (directFiber) return directFiber;

    for (const descendant of Array.from(element?.querySelectorAll('*') || [])) {
      const fiber = getReactFiberForElement(descendant);
      if (fiber) return fiber;
    }
    return null;
  }

  function getAppScopeFromFiber(fiber) {
    let currentFiber = fiber;
    let fiberDepth = 0;
    while (currentFiber && fiberDepth < 40) {
      let hook = currentFiber.memoizedState;
      let hookDepth = 0;
      while (hook && hookDepth < 80) {
        const memoizedState = hook.memoizedState;
        const candidate = memoizedState?.current;
        if (
          candidate
          && candidate.node?.store
          && typeof candidate.get === 'function'
          && typeof candidate.set === 'function'
        ) {
          return candidate;
        }
        hook = hook.next;
        hookDepth += 1;
      }
      currentFiber = currentFiber.return;
      fiberDepth += 1;
    }
    return null;
  }

  function getAppScopeFromSidebar() {
    const candidates = [
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-id]')),
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
    ];

    for (const candidate of candidates) {
      const scope = getAppScopeFromFiber(getReactFiberFromSubtree(candidate));
      if (scope) return scope;
    }
    return null;
  }

  function getReactRouterNavigatorFromSidebar() {
    const candidates = [
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-id]')),
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
    ];

    for (const candidate of candidates) {
      let currentFiber = getReactFiberFromSubtree(candidate);
      let fiberDepth = 0;
      while (currentFiber && fiberDepth < 160) {
        const props = currentFiber.memoizedProps;
        const navigator = props?.navigator;
        if (
          props?.location
          && navigator
          && typeof navigator.push === 'function'
        ) {
          return navigator;
        }
        currentFiber = currentFiber.return;
        fiberDepth += 1;
      }
    }
    return null;
  }

  function getReactRouterLocationFromSidebar() {
    const candidates = [
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-id]')),
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
    ];

    for (const candidate of candidates) {
      let currentFiber = getReactFiberFromSubtree(candidate);
      let fiberDepth = 0;
      while (currentFiber && fiberDepth < 160) {
        const props = currentFiber.memoizedProps;
        if (props?.location?.pathname && props?.navigator?.push) {
          return props.location;
        }
        currentFiber = currentFiber.return;
        fiberDepth += 1;
      }
    }
    return null;
  }

  function normalizeLiveThreadKey(value) {
    return String(value || '').trim().toLowerCase();
  }

  function isLiveThreadCatalog(value) {
    return Boolean(
      value
      && Array.isArray(value.threadKeys)
      && Array.isArray(value.projectGroups)
      && value.threadRecencyAtByKey
      && typeof value.threadRecencyAtByKey.get === 'function'
    );
  }

  function getLiveThreadCatalogState(scope) {
    const cachedBindings = scope?.node?.cachedBindings;
    if (
      !cachedBindings
      || typeof cachedBindings.entries !== 'function'
      || typeof scope?.get !== 'function'
    ) {
      return null;
    }

    if (liveCatalogScope === scope && liveCatalogStateBinding) {
      try {
        const state = scope.get(liveCatalogStateBinding);
        if (isLiveThreadCatalog(state)) {
          return { state, cachedBindings };
        }
      } catch {
      }
      liveCatalogStateBinding = null;
    }

    for (const [binding] of cachedBindings.entries()) {
      let state = null;
      try {
        state = scope.get(binding);
      } catch {
        continue;
      }
      if (!isLiveThreadCatalog(state)) continue;

      liveCatalogScope = scope;
      liveCatalogStateBinding = binding;
      return { state, cachedBindings };
    }

    return null;
  }

  function getLiveThreadRecordKey(task, conversation) {
    const explicitKey = normalizeLiveThreadKey(task?.key || conversation?.key);
    if (explicitKey) return explicitKey;

    const threadId = normalizeLiveThreadKey(conversation?.id);
    if (!threadId) return '';
    const hostId = normalizeLiveThreadKey(task?.kind || conversation?.hostId || 'local') || 'local';
    return hostId + ':' + threadId;
  }

  function addLiveThreadRecord(records, bindings, value, binding) {
    const task = value?.task || value;
    const conversation = task?.conversation;
    if (!conversation || !conversation.id) return;

    const key = getLiveThreadRecordKey(task, conversation);
    if (!key) return;

    records.set(key, {
      key,
      id: String(conversation.id),
      title: normalizeText(conversation.title),
      cwd: normalizeText(conversation.cwd),
      updatedAt: conversation.updatedAt,
      createdAt: conversation.createdAt,
      source: normalizeText(conversation.source || task?.source),
      kind: normalizeText(task?.kind || conversation.hostId)
    });
    bindings.set(key, binding);
  }

  function collectLiveThreadValue(records, bindings, value, binding) {
    if (Array.isArray(value)) {
      for (const item of value) {
        addLiveThreadRecord(records, bindings, item, binding);
      }
      return;
    }
    addLiveThreadRecord(records, bindings, value, binding);
  }

  function refreshLiveThreadBindings(catalog, forceScan) {
    const { state, cachedBindings, scope } = catalog;
    const threadKeys = Array.isArray(state.threadKeys)
      ? state.threadKeys.map(normalizeLiveThreadKey).filter(Boolean)
      : [];
    const threadSignature = threadKeys.join('|');
    const shouldScan = Boolean(
      forceScan
      || !liveCatalogCache
      || liveCatalogCache.scope !== scope
      || liveCatalogThreadSignature !== threadSignature
      || liveCatalogCache.bindingCount !== cachedBindings.size
    );

    if (shouldScan) {
      const records = new Map();
      const bindings = new Map();
      for (const [binding] of cachedBindings.entries()) {
        let value = null;
        try {
          value = scope.get(binding);
        } catch {
          continue;
        }
        collectLiveThreadValue(records, bindings, value, binding);
      }
      liveCatalogCache = {
        scope,
        records,
        bindings,
        bindingCount: cachedBindings.size
      };
      liveCatalogThreadSignature = threadSignature;
      liveCatalogLastRefreshMs = Date.now();
      return;
    }

    if (Date.now() - liveCatalogLastRefreshMs < 250) return;

    for (const [key, binding] of liveCatalogCache.bindings.entries()) {
      let value = null;
      try {
        value = scope.get(binding);
      } catch {
        continue;
      }
      collectLiveThreadValue(liveCatalogCache.records, liveCatalogCache.bindings, value, binding);
    }
    liveCatalogLastRefreshMs = Date.now();
  }

  function getLiveSidebarCatalog() {
    const scope = getAppScopeFromSidebar();
    if (!scope) return null;

    if (liveCatalogScope !== scope) {
      liveCatalogScope = scope;
      liveCatalogStateBinding = null;
      liveCatalogCache = null;
      liveCatalogThreadSignature = '';
      liveCatalogLastRefreshMs = 0;
    }

    const stateResult = getLiveThreadCatalogState(scope);
    if (!stateResult) return null;

    const catalog = {
      scope,
      state: stateResult.state,
      cachedBindings: stateResult.cachedBindings
    };
    refreshLiveThreadBindings(catalog, false);
    return {
      scope,
      state: stateResult.state,
      threadKeys: Array.isArray(stateResult.state.threadKeys)
        ? stateResult.state.threadKeys.map(normalizeLiveThreadKey).filter(Boolean)
        : [],
      records: liveCatalogCache?.records || new Map(),
      projectGroups: Array.isArray(stateResult.state.projectGroups) ? stateResult.state.projectGroups : []
    };
  }

  function getActiveThreadId() {
    const activeRow = Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-active="true"]'))
      .find((row) => !row.closest('[' + SYNTHETIC_ROW_ATTR + '="threads"]'));
    const activeId = normalizeThreadId(activeRow?.getAttribute('data-app-action-sidebar-thread-id'));
    if (activeId) return activeId;

    const pathname = String(getReactRouterLocationFromSidebar()?.pathname || '');
    const match = pathname.match(/^\/local\/([^/?#]+)/i);
    if (!match) return '';
    try {
      return normalizeThreadId(decodeURIComponent(match[1]));
    } catch {
      return normalizeThreadId(match[1]);
    }
  }

  function createThreadSpinner() {
    const overlay = document.createElement('div');
    overlay.setAttribute(THREAD_SPINNER_ATTR, 'true');
    overlay.className = 'flex shrink-0 items-center justify-end absolute right-0 top-0 z-10 flex h-full min-w-[52px] items-center justify-end gap-2 pr-1';

    const slot = document.createElement('span');
    slot.className = 'flex h-5 min-w-5 items-center justify-center';
    const spinner = document.createElement('div');
    spinner.className = 'relative flex size-5 shrink-0 items-center justify-center text-token-foreground/70';
    const animated = document.createElement('div');
    animated.className = 'animate-spin inline-flex h-fit w-fit items-center justify-center leading-none contain-layout contain-paint contain-style';
    animated.style.animationDelay = '-540ms';
    animated.style.animationDuration = '2000ms';
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', '24');
    svg.setAttribute('height', '24');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    svg.setAttribute('class', 'icon-xs shrink-0');

    const fadedPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    fadedPath.setAttribute('opacity', '0.3');
    fadedPath.setAttribute('d', 'M18 12C18 8.68629 15.3137 6 12 6C8.68629 6 6 8.68629 6 12C6 15.3137 8.68629 18 12 18C15.3137 18 18 18 18 12ZM20 12C20 16.4183 16.4183 20 12 20C7.58172 20 4 16.4183 4 12C4 7.58172 7.58172 4 12 4C16.4183 4 20 7.58172 20 12Z');
    fadedPath.setAttribute('fill', 'currentColor');
    const activePath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    activePath.setAttribute('d', 'M12 4C16.4183 4 20 7.58172 20 12C20 16.4183 16.4183 20 12 20C7.58172 20 4 16.4183 4 12H6C6 15.3137 8.68629 18 12 18C15.3137 18 18 15.3137 18 12C18 8.68629 15.3137 6 12 6V4Z');
    activePath.setAttribute('fill', 'currentColor');

    svg.appendChild(fadedPath);
    svg.appendChild(activePath);
    animated.appendChild(svg);
    spinner.appendChild(animated);
    slot.appendChild(spinner);
    overlay.appendChild(slot);
    return overlay;
  }

  function getSyntheticThreadButton(row) {
    if (!row) return null;
    return row.matches?.('[data-app-action-sidebar-thread-row]')
      ? row
      : row.querySelector('[data-app-action-sidebar-thread-row]')
      || row.querySelector('[role="button"].group.relative')
      || row.querySelector('[data-app-action-sidebar-thread-title]')?.closest('[role="button"]')
      || row.querySelector('[role="button"]')
      || row;
  }

  function syncThreadSpinner(row, working, nativeRow) {
    if (!row) return;
    const existing = row.querySelector('[' + THREAD_SPINNER_ATTR + ']');
    if (!working) {
      if (existing) existing.remove();
      return;
    }
    if (existing) return;

    // Let Codex keep its own indicator when the native row already exposes one.
    if (nativeRow && row.querySelector('.animate-spin')) return;

    const button = getSyntheticThreadButton(row);
    if (!button) return;
    if (window.getComputedStyle(button).position === 'static') {
      button.classList.add('relative');
    }
    button.appendChild(createThreadSpinner());
  }

  function syncSyntheticThreadActiveState() {
    const activeThreadId = getActiveThreadId();
    const workingThreadIds = getWorkingThreadIds();
    for (const row of getNativeThreadRows()) {
      const threadId = normalizeThreadId(getThreadIdForRow(row));
      syncThreadSpinner(row, Boolean(threadId && workingThreadIds.has(threadId)), true);
    }

    for (const row of Array.from(document.querySelectorAll('[' + SYNTHETIC_ROW_ATTR + '="threads"]'))) {
      const threadId = normalizeThreadId(row.getAttribute('data-codex-plus-thread-id'));
      const active = Boolean(threadId && activeThreadId && threadId === activeThreadId);
      const working = Boolean(threadId && workingThreadIds.has(threadId));
      row.setAttribute('data-app-action-sidebar-thread-active', active ? 'true' : 'false');
      row.setAttribute('data-codex-plus-thread-working', working ? 'true' : 'false');
      if (active) {
        row.setAttribute('aria-current', 'page');
      } else {
        row.removeAttribute('aria-current');
      }

      const button = getSyntheticThreadButton(row);
      button.classList.toggle('bg-token-list-hover-background', active);
      syncThreadSpinner(row, working, false);
    }
  }

  function findAssetName(mainSource, assetPrefix) {
    const marker = assetPrefix + '-';
    const markerIndex = mainSource.indexOf(marker);
    if (markerIndex < 0) return '';

    const extensionIndex = mainSource.indexOf('.js', markerIndex);
    return extensionIndex < 0 ? '' : mainSource.slice(markerIndex, extensionIndex + 3);
  }

  function getInternalNavigationModules() {
    if (!internalNavigationModulesPromise) {
      internalNavigationModulesPromise = (async () => {
        const mainScriptUrl = Array.from(document.scripts)
          .map((script) => script.src)
          .find(Boolean);
        if (!mainScriptUrl) return null;

        const response = await fetch(mainScriptUrl);
        if (!response.ok) return null;
        const mainSource = await response.text();
        const navigationName = findAssetName(mainSource, 'sidebar-thread-navigation');
        const appServerName = findAssetName(mainSource, 'app-server-manager-signals');
        if (!navigationName || !appServerName) return null;

        const [navigation, appServer] = await Promise.all([
          import(new URL(navigationName, mainScriptUrl).href),
          import(new URL(appServerName, mainScriptUrl).href)
        ]);
        return { navigation, appServer };
      })().catch(() => null);
    }
    return internalNavigationModulesPromise;
  }

  function getThreadNavigationLocation(sourceListLabel) {
    const projectLabel = getProjectLabelFromSourceList(sourceListLabel);
    if (projectLabel) {
      const projectRow = findProjectRowByLabel(projectLabel);
      const projectId = getProjectIdForRow(projectRow);
      if (projectId) return 'project:' + projectId;
    }
    return 'flat-chats';
  }

  async function navigateThreadThroughCodex(threadRow) {
    const threadId = normalizeThreadId(threadRow?.getAttribute('data-codex-plus-thread-id'));
    if (!threadId) return false;

    const scope = getAppScopeFromSidebar();
    if (!scope) return false;

    const modules = await getInternalNavigationModules();
    if (!modules || typeof modules.navigation?.t !== 'function') return false;

    const routerNavigator = getReactRouterNavigatorFromSidebar();
    if (!routerNavigator || typeof routerNavigator.push !== 'function') return false;

    const hostId = 'local';
    const manager = typeof modules.appServer?.c === 'object'
      ? scope.get(modules.appServer.c, hostId)
      : null;
    if (!manager || typeof manager.activateThreadSummary !== 'function') return false;

    try {
      modules.appServer.Et?.(scope, threadId, hostId);
      manager.activateThreadSummary(threadId);
      if (typeof manager.getConversation === 'function' && !manager.getConversation(threadId)) {
        return false;
      }
      routerNavigator.push('/local/' + threadId);
      modules.navigation.t(
        scope,
        hostId + ':' + threadId,
        getThreadNavigationLocation(threadRow.getAttribute(SOURCE_LIST_ATTR))
      );
      return true;
    } catch {
      return false;
    }
  }

  function getProjectGroupFromRow(row) {
    let fiber = getReactFiberForElement(row);
    let depth = 0;
    while (fiber && depth < 8) {
      const props = fiber.memoizedProps;
      if (props?.group && typeof props.group === 'object') {
        return props.group;
      }
      fiber = fiber.return;
      depth += 1;
    }
    return null;
  }

  function toTimestampMs(value) {
    const timestamp = Number(value || 0);
    if (!Number.isFinite(timestamp) || timestamp <= 0) return 0;
    return timestamp < 1e12 ? Math.round(timestamp * 1000) : Math.round(timestamp);
  }

  function getRemoteProjectTimestampMsForRow(row) {
    const group = getProjectGroupFromRow(row);
    return toTimestampMs(group?.cloudEnvironment?.created_at);
  }

  function getLiveThreadTimestampMs(record, catalog) {
    if (!record) return 0;

    const threadKey = normalizeLiveThreadKey(record.key);
    const recency = catalog?.state?.threadRecencyAtByKey;
    const recencyValue = recency && typeof recency.get === 'function'
      ? (recency.get(threadKey) || recency.get(record.key))
      : 0;

    return Math.max(
      toTimestampMs(record.updatedAt),
      toTimestampMs(recencyValue),
      parseThreadTimestampMs(record.id)
    );
  }

  function getThreadTitleElement(row) {
    if (!row) return null;
    return row.querySelector('[data-thread-title="true"], [data-app-action-sidebar-thread-title], .text-fade-truncate') || null;
  }

  function stripThreadTimestampSuffix(label) {
    return normalizeText(label).replace(/\s+\[[^\]]+\]$/, '').trim();
  }

  function formatThreadModifiedTime(updatedMs) {
    const timestampMs = Number(updatedMs || 0);
    if (timestampMs <= 0) return '';

    try {
      return new Intl.DateTimeFormat(undefined, {
        dateStyle: 'short',
        timeStyle: 'short'
      }).format(new Date(timestampMs));
    } catch {
      return '';
    }
  }

  function getThreadBaseLabel(row) {
    if (!row) return '';

    const explicit = normalizeText(row.getAttribute(THREAD_BASE_LABEL_ATTR));
    if (explicit) return explicit;

    const current = normalizeText(textOf(getThreadTitleElement(row)) || textOf(row));
    const baseLabel = stripThreadTimestampSuffix(current);
    if (baseLabel) {
      row.setAttribute(THREAD_BASE_LABEL_ATTR, baseLabel);
    }
    return baseLabel;
  }

  function appendThreadTimestampToLabel(label, updatedMs) {
    const baseLabel = stripThreadTimestampSuffix(label);
    const timestampLabel = formatThreadModifiedTime(updatedMs);
    return timestampLabel ? (baseLabel + ' [' + timestampLabel + ']') : baseLabel;
  }

  function styleThreadTitleElement(element) {
    if (!element) return;
    element.classList.remove('text-token-description-foreground');
    element.classList.add('text-token-foreground');
  }

  function syncThreadToggleButton(button, collapsed) {
    if (!button) return;
    const nextLabel = collapsed ? 'Show Threads list' : 'Hide Threads list';
    const nextExpanded = collapsed ? 'false' : 'true';
    if (button.getAttribute(ACTION_ATTR) !== 'collapse-list') {
      button.setAttribute(ACTION_ATTR, 'collapse-list');
    }
    if (button.getAttribute('aria-label') !== nextLabel) {
      button.setAttribute('aria-label', nextLabel);
    }
    if (button.getAttribute('aria-expanded') !== nextExpanded) {
      button.setAttribute('aria-expanded', nextExpanded);
    }
    if (button.hasAttribute('data-app-action-sidebar-section-toggle')) {
      button.removeAttribute('data-app-action-sidebar-section-toggle');
    }
    if (button.hasAttribute('aria-describedby')) {
      button.removeAttribute('aria-describedby');
    }
    if (button.hasAttribute('aria-disabled')) {
      button.removeAttribute('aria-disabled');
    }
    if (button.hasAttribute('aria-roledescription')) {
      button.removeAttribute('aria-roledescription');
    }
    if (button.hasAttribute('data-state')) {
      button.removeAttribute('data-state');
    }
    const labelSpan = button.querySelector('span');
    if (labelSpan && normalizeText(labelSpan.textContent) !== 'Threads') {
      labelSpan.textContent = 'Threads';
    }
    const icon = button.querySelector('svg');
    if (icon) {
      if (icon.classList.contains('-rotate-90') !== collapsed) {
        icon.classList.toggle('-rotate-90', collapsed);
      }
      if (!icon.classList.contains('opacity-100')) {
        icon.classList.add('opacity-100');
      }
    }
  }

  function getRowTextSignature(row) {
    return stripThreadTimestampSuffix(normalizeText(row?.innerText || ''));
  }

  function getClickableElement(row) {
    if (!row) return null;
    const candidates = Array.from(row.querySelectorAll('button, a, [role="button"]'));
    const preferred = candidates.find((candidate) => {
      const role = normalizeText(candidate.getAttribute('role'));
      const ariaLabel = normalizeText(candidate.getAttribute('aria-label'));
      const className = String(candidate.className || '');
      if (ariaLabel) return false;
      if (className.includes('cursor-grab')) return false;
      return role === 'button' || candidate.tagName === 'BUTTON' || candidate.tagName === 'A';
    });
    return preferred || candidates.find((candidate) => !String(candidate.className || '').includes('cursor-grab')) || row;
  }

  function dispatchRowClick(row) {
    const target = getClickableElement(row);
    if (!target) return false;
    if (typeof target.focus === 'function') {
      try { target.focus(); } catch {}
    }
    if (typeof target.click === 'function') {
      target.click();
      return true;
    }
    for (const eventName of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
      target.dispatchEvent(new MouseEvent(eventName, {
        bubbles: true,
        cancelable: true,
        view: window
      }));
    }
    return true;
  }

  function findRowByTextSignature(list, normalizedRowText) {
    return getSidebarRows(list).find((row) => getRowTextSignature(row) === normalizedRowText) || null;
  }

  function findSourceRowInList(list, normalizedRowText) {
    if (!list || !normalizedRowText) return null;

    let row = findRowByTextSignature(list, normalizedRowText);
    let attempts = 0;
    while (!row && attempts < 8) {
      const showMoreButton = Array.from(list.querySelectorAll('button')).find((button) => {
        return normalizeText(button.textContent) === 'Show more' && !button.hidden;
      });
      if (!showMoreButton) break;

      showMoreButton.click();
      attempts += 1;
      row = findRowByTextSignature(list, normalizedRowText);
    }

    return row;
  }

  function findSourceRow(listLabel, rowText) {
    const normalizedListLabel = normalizeText(listLabel);
    const normalizedRowText = normalizeText(rowText);
    if (!normalizedListLabel || !normalizedRowText) return null;

    const candidateLabels = normalizedListLabel === 'Tasks'
      ? ['Tasks', 'Threads', 'Chats']
      : [normalizedListLabel];

    const list = candidateLabels
      .map((label) => getNonSyntheticSidebarSectionListByLabel(document, label))
      .find(Boolean);
    if (!list) return null;

    return findSourceRowInList(list, normalizedRowText);
  }

  function getProjectLabelFromSourceList(listLabel) {
    const normalizedListLabel = normalizeText(listLabel);
    const prefix = 'Scheduled tasks in ';
    return normalizedListLabel.startsWith(prefix)
      ? normalizedListLabel.slice(prefix.length).trim()
      : '';
  }

  function findProjectRowByLabel(projectLabel) {
    const normalizedProjectLabel = normalizeText(projectLabel);
    if (!normalizedProjectLabel) return null;

    return Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
      .find((row) => normalizeText(row.getAttribute('data-app-action-sidebar-project-label')) === normalizedProjectLabel)
      || null;
  }

  function expandSourceProject(sourceListLabel) {
    const projectLabel = getProjectLabelFromSourceList(sourceListLabel);
    const projectRow = findProjectRowByLabel(projectLabel);
    if (!projectRow) return false;

    const expanded = projectRow.getAttribute('aria-expanded') === 'true'
      || projectRow.getAttribute('data-app-action-sidebar-project-collapsed') === 'false';
    if (!expanded) {
      if (typeof projectRow.click === 'function') {
        projectRow.click();
      } else {
        dispatchRowClick(projectRow);
      }
    }
    return true;
  }

  function waitForSourceRow(listLabel, rowText, threadId) {
    return new Promise((resolve) => {
      let attempts = 0;
      const poll = () => {
        const sourceRow = findSourceRow(listLabel, rowText) || findRowByThreadId(threadId);
        if (sourceRow || attempts >= 20) {
          resolve(sourceRow || null);
          return;
        }
        attempts += 1;
        window.setTimeout(poll, 50);
      };
      poll();
    });
  }

  function findRowByThreadId(threadId) {
    const normalizedThreadId = normalizeThreadId(threadId);
    if (!normalizedThreadId) return null;

    return getSidebarSectionLists(document, (label, list) => !list.hasAttribute(SYNTHETIC_LIST_ATTR))
      .flatMap((list) => getSidebarRows(list))
      .find((row) => normalizeThreadId(getThreadIdForRow(row)) === normalizedThreadId) || null;
  }

  function wireSyntheticThreadRow(row, sourceListLabel, sourceRowText) {
    if (!row) return;
    if (row.getAttribute('data-codex-plus-thread-wired') === 'true') {
      return;
    }
    row.setAttribute(SOURCE_LIST_ATTR, sourceListLabel);
    row.setAttribute(SOURCE_TEXT_ATTR, sourceRowText);

    const invokeSourceRow = (event) => {
      if (row.getAttribute(NAVIGATION_PENDING_ATTR) === 'true') {
        return;
      }

      const stopSyntheticEvent = () => {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      };
      stopSyntheticEvent();
      row.setAttribute(NAVIGATION_PENDING_ATTR, 'true');
      navigateThreadThroughCodex(row)
        .then((handled) => {
          if (handled) return;

          const sourceRow = findSourceRow(row.getAttribute(SOURCE_LIST_ATTR), row.getAttribute(SOURCE_TEXT_ATTR))
            || findRowByThreadId(row.getAttribute('data-codex-plus-thread-id'));
          if (sourceRow) {
            dispatchRowClick(sourceRow);
            return;
          }

          if (!expandSourceProject(row.getAttribute(SOURCE_LIST_ATTR))) return;
          return waitForSourceRow(
            row.getAttribute(SOURCE_LIST_ATTR),
            row.getAttribute(SOURCE_TEXT_ATTR),
            row.getAttribute('data-codex-plus-thread-id')
          ).then((resolvedSourceRow) => {
            if (resolvedSourceRow) dispatchRowClick(resolvedSourceRow);
          });
        })
        .finally(() => row.removeAttribute(NAVIGATION_PENDING_ATTR));
    };

    row.addEventListener('click', invokeSourceRow, true);
    row.addEventListener('pointerup', invokeSourceRow, true);
    row.setAttribute('data-codex-plus-thread-wired', 'true');
  }

  function getThreadTitleForRow(row) {
    return textOf(getThreadTitleElement(row)) || textOf(row);
  }

  function getNativeThreadTitleMap() {
    for (const row of getNativeThreadRows()) {
      const threadId = normalizeThreadId(getThreadIdForRow(row));
      const title = getThreadBaseLabel(row) || stripThreadTimestampSuffix(getThreadTitleForRow(row));
      if (threadId && title) {
        nativeThreadTitleCache.set(threadId, title);
      }
    }
    return nativeThreadTitleCache;
  }

  function getProjectLabelForRow(row) {
    const directLabel = normalizeText(row?.getAttribute('data-app-action-sidebar-project-label'));
    if (directLabel) return stripThreadTimestampSuffix(directLabel);

    const explicitLabel = row?.querySelector('[data-app-action-sidebar-project-label]');
    const explicitText = stripThreadTimestampSuffix(normalizeText(textOf(explicitLabel)));
    if (explicitText) return explicitText;

    const projectId = getProjectIdForRow(row);
    if (!projectId) return '';
    const normalized = String(projectId).replace(/\\+/g, '/').replace(/\/+$/g, '');
    const parts = normalized.split('/').filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : normalized;
  }

  function formatThreadLabel(row, kind, projectTitle, updatedMs) {
    const title = getThreadBaseLabel(row);
    return title || '';
  }

  function formatThreadLabelFromCatalog(entry) {
    const title = normalizeText(entry?.displayTitle || entry?.title);
    if (!title) return '';
    return title;
  }

  function setThreadLabel(row, label, baseLabel, updatedMs) {
    if (!row || !label) return;
    const titleElement = getThreadTitleElement(row);
    const nextBaseLabel = normalizeText(baseLabel || stripThreadTimestampSuffix(label || getThreadBaseLabel(row)));
    const timestampMs = Number((updatedMs ?? getThreadTimestampMsForRow(row)) || 0);
    const nextTimestampLabel = formatThreadModifiedTime(timestampMs);
    const nextLabel = appendThreadTimestampToLabel(nextBaseLabel, timestampMs);
    const currentLabel = normalizeText(textOf(titleElement) || textOf(row));
    const legacyTimestampSpan = row.querySelector(LEGACY_TIMESTAMP_SUFFIX_SELECTOR);

    if (nextBaseLabel && row.getAttribute(THREAD_BASE_LABEL_ATTR) !== nextBaseLabel) {
      row.setAttribute(THREAD_BASE_LABEL_ATTR, nextBaseLabel);
    }
    if (row.getAttribute(THREAD_TIMESTAMP_ATTR) !== nextTimestampLabel) {
      row.setAttribute(THREAD_TIMESTAMP_ATTR, nextTimestampLabel);
    }
    if (row.getAttribute(THREAD_UPDATED_ATTR) !== String(timestampMs || 0)) {
      row.setAttribute(THREAD_UPDATED_ATTR, String(timestampMs || 0));
    }

    if (currentLabel === nextLabel && !legacyTimestampSpan) return;
    if (titleElement) {
      styleThreadTitleElement(titleElement);
      titleElement.textContent = nextLabel;
      if (legacyTimestampSpan) {
        for (const timestampSpan of Array.from(row.querySelectorAll(LEGACY_TIMESTAMP_SUFFIX_SELECTOR))) {
          timestampSpan.remove();
        }
      }
      return;
    }

    const directTextNode = Array.from(row.childNodes).find((node) => node.nodeType === Node.TEXT_NODE && normalizeText(node.nodeValue));
    if (directTextNode) {
      directTextNode.nodeValue = nextLabel;
      if (legacyTimestampSpan) {
        for (const timestampSpan of Array.from(row.querySelectorAll(LEGACY_TIMESTAMP_SUFFIX_SELECTOR))) {
          timestampSpan.remove();
        }
      }
      return;
    }

    row.textContent = nextLabel;
  }

  function parseThreadTimestampMs(threadId) {
    const value = normalizeThreadId(threadId);
    const uuidPart = value.includes(':') ? value.split(':').pop() : value;
    const hex = uuidPart.replace(/-/g, '');
    if (hex.length < 12 || !/^[0-9a-f]+$/i.test(hex)) return 0;

    try {
      return Number(BigInt('0x' + hex.slice(0, 12)));
    } catch {
      return 0;
    }
  }

  function getThreadTimestampMsForRow(row) {
    const explicit = Number(row?.getAttribute(THREAD_UPDATED_ATTR) || '0');
    if (explicit > 0) return explicit;
    return parseThreadTimestampMs(getThreadIdForRow(row));
  }

  function getProjectTimestampMap() {
    const map = new Map();
    const catalog = getLiveSidebarCatalog();
    if (!catalog) return map;

    const updateProjectTimestamp = (projectId, timestampMs) => {
      if (!projectId || timestampMs <= 0) return;
      const current = Number(map.get(projectId) || 0);
      if (timestampMs > current) map.set(projectId, timestampMs);
    };

    for (const group of catalog.projectGroups) {
      const projectId = normalizeProjectId(group?.projectId || group?.path);
      if (!projectId) continue;

      updateProjectTimestamp(projectId, toTimestampMs(group?.cloudEnvironment?.created_at));
      for (const threadKey of Array.isArray(group?.threadKeys) ? group.threadKeys : []) {
        const record = catalog.records.get(normalizeLiveThreadKey(threadKey));
        updateProjectTimestamp(projectId, getLiveThreadTimestampMs(record, catalog));
      }
    }

    for (const record of catalog.records.values()) {
      const projectId = normalizeProjectId(record?.cwd);
      updateProjectTimestamp(projectId, getLiveThreadTimestampMs(record, catalog));
    }

    return map;
  }

  function getProjectTimestampMsForRow(row) {
    const explicit = Number(row?.getAttribute(THREAD_UPDATED_ATTR) || '0');
    if (explicit > 0) return explicit;

    const projectId = normalizeProjectId(getProjectIdForRow(row));
    if (projectId) {
      const projectTimestamp = Number(getProjectTimestampMap().get(projectId) || 0);
      if (projectTimestamp > 0) return projectTimestamp;
    }

    return getRemoteProjectTimestampMsForRow(row);
  }

  function countRecentRows(rows, getTimestampMs) {
    const cutoffMs = Date.now() - RECENT_WINDOW_MS;
    let count = 0;
    for (const row of rows) {
      const timestampMs = Number(getTimestampMs(row) || 0);
      if (timestampMs < cutoffMs) {
        break;
      }
      count += 1;
    }
    return count;
  }

  function getVisibleCount(rows, spec) {
    const minimum = Math.max(0, Number(spec.minVisibleCount) || 0);
    if (!rows.length) return minimum;

    if (spec.key === 'tasks') {
      return Math.max(minimum, countRecentRows(rows, (row) => getThreadTimestampMsForRow(row)));
    }

    return minimum;
  }

  function readLoaded(list) {
    return Number(list.getAttribute(STATE_ATTR) || '0');
  }

  function writeLoaded(list, value) {
    const nextValue = String(value);
    if (list.getAttribute(STATE_ATTR) !== nextValue) {
      list.setAttribute(STATE_ATTR, nextValue);
    }
  }

  function setVisible(row, visible) {
    const nextHidden = !visible;
    const nextAriaHidden = visible ? 'false' : 'true';
    const nextDisplay = visible ? '' : 'none';
    const nextVisibility = visible ? '' : 'hidden';
    const nextPointerEvents = visible ? '' : 'none';
    if (row.hidden !== nextHidden) {
      row.hidden = nextHidden;
    }
    if (row.getAttribute('aria-hidden') !== nextAriaHidden) {
      row.setAttribute('aria-hidden', nextAriaHidden);
    }
    if (row.style.display !== nextDisplay) {
      row.style.setProperty('display', nextDisplay, 'important');
    }
    if (row.style.visibility !== nextVisibility) {
      row.style.setProperty('visibility', nextVisibility, 'important');
    }
    if (row.style.pointerEvents !== nextPointerEvents) {
      row.style.setProperty('pointer-events', nextPointerEvents, 'important');
    }
  }

  function clearPagers(root) {
    for (const pager of Array.from(root.querySelectorAll('[' + PAGER_ATTR + ']'))) {
      pager.remove();
    }
  }

  function bindSingleActivation(button, handler) {
    if (!button) return;
    button.onclick = handler;
    button.onpointerup = null;
  }

  function removeSyntheticSection(sectionKey) {
    const shell = document.querySelector('[' + SYNTHETIC_SECTION_ATTR + '="' + sectionKey + '"]');
    if (shell) shell.remove();
  }

  function getProjectTitleMap() {
    const map = new Map();
    const projectsList = resolveSidebarSectionList({ key: 'projects', title: 'Projects' });
    for (const row of getSidebarRows(projectsList)) {
      const projectId = normalizeProjectId(getProjectIdForRow(row));
      const projectTitle = getProjectLabelForRow(row) || stripThreadTimestampSuffix(textOf(row));
      if (projectId && projectTitle) {
        map.set(projectId, projectTitle);
      }
    }
    return map;
  }

  function getSyntheticThreadTemplateRow() {
    const candidateLists = [
      getNonSyntheticSidebarSectionListByLabel(document, 'Tasks'),
      getNonSyntheticSidebarSectionListByLabel(document, 'Threads'),
      getNonSyntheticSidebarSectionListByLabel(document, 'Chats'),
      ...getSidebarSectionLists(document, (label) => label.startsWith('Scheduled tasks in '))
    ].filter(Boolean);

    for (const list of candidateLists) {
      const row = getSidebarRows(list)[0];
      if (row) return row;
    }

    return null;
  }

  function sanitizeSyntheticThreadTemplate(row) {
    const nativeStateAttributes = [
      'data-app-action-sidebar-thread-id',
      'data-app-action-sidebar-thread-active',
      'data-app-action-sidebar-thread-kind',
      'data-app-action-sidebar-thread-host-id',
      'data-app-action-sidebar-thread-pinned',
      'aria-current',
      'aria-selected'
    ];

    for (const element of Array.from(row?.querySelectorAll('*') || [])) {
      for (const attribute of nativeStateAttributes) {
        element.removeAttribute(attribute);
      }
    }

    for (const animated of Array.from(row?.querySelectorAll('.animate-spin') || [])) {
      const overlay = animated.closest('[data-hover-card-open-immediately]') || animated;
      if (overlay !== row) overlay.remove();
    }
  }

  function createSyntheticThreadRow(label, updatedMs, templateRow) {
    if (templateRow) {
      const row = templateRow.cloneNode(true);
      sanitizeSyntheticThreadTemplate(row);
      row.removeAttribute('data-app-action-sidebar-thread-id');
      row.removeAttribute('data-app-action-sidebar-project-id');
      row.removeAttribute('aria-current');
      row.removeAttribute('aria-selected');
      row.setAttribute(SYNTHETIC_ROW_ATTR, 'threads');
      row.setAttribute(THREAD_UPDATED_ATTR, String(updatedMs || 0));
      for (const selected of Array.from(row.querySelectorAll('[aria-current], [aria-selected]'))) {
        selected.removeAttribute('aria-current');
        selected.removeAttribute('aria-selected');
      }
      setThreadLabel(row, label, stripThreadTimestampSuffix(label), updatedMs);
      return row;
    }

    const row = document.createElement('div');
    row.setAttribute('role', 'listitem');
    row.setAttribute(SYNTHETIC_ROW_ATTR, 'threads');
    row.setAttribute(THREAD_UPDATED_ATTR, String(updatedMs || 0));
    row.className = 'after:block after:h-px after:content-[\'\'] last:after:hidden';

    const button = document.createElement('div');
    button.setAttribute('role', 'button');
    button.setAttribute('tabindex', '0');
    button.setAttribute('aria-roledescription', 'sortable');
    button.className = 'group relative h-[var(--height-token-row)] cursor-interaction rounded-[var(--radius-token-row)] py-row-y text-sm hover:bg-token-list-hover-background focus-visible:outline focus-visible:outline-offset-[-2px] pr-1 pl-[var(--padding-row-cell-x,var(--padding-row-x))]';

    const outer = document.createElement('div');
    outer.className = 'flex h-full w-full items-center text-sm leading-4';

    const inner = document.createElement('div');
    inner.className = 'flex min-w-0 flex-1 self-stretch items-center gap-2 text-base leading-5 text-token-foreground';

    const title = document.createElement('span');
    title.setAttribute('data-thread-title', 'true');
    title.className = 'min-w-0 select-none text-fade-truncate flex-1 text-token-foreground';
    title.textContent = label;

    inner.appendChild(title);
    outer.appendChild(inner);
    button.appendChild(outer);
    row.appendChild(button);
    row.setAttribute(THREAD_BASE_LABEL_ATTR, stripThreadTimestampSuffix(label));
    row.setAttribute(THREAD_TIMESTAMP_ATTR, formatThreadModifiedTime(updatedMs) || '');
    return row;
  }

  function syncSyntheticThreadRows(listElement, threadRows) {
    if (!listElement) return;

    const existingRows = new Map();
    for (const row of getSidebarRows(listElement)) {
      const threadId = normalizeThreadId(getThreadIdForRow(row) || row.getAttribute('data-codex-plus-thread-id'));
      if (threadId) {
        existingRows.set(threadId, row);
      }
    }

    const orderedRows = [];
    for (const entry of threadRows) {
      const threadId = normalizeThreadId(entry.row.getAttribute('data-codex-plus-thread-id'));
      let row = threadId ? existingRows.get(threadId) : null;
      if (!row) {
        row = entry.row;
      } else {
        const nextLabel = entry.label || getThreadTitleForRow(entry.row);
        setThreadLabel(row, nextLabel, stripThreadTimestampSuffix(nextLabel), entry.timestampMs);
        row.setAttribute(THREAD_UPDATED_ATTR, String(entry.timestampMs || 0));
        row.setAttribute(SYNTHETIC_ROW_ATTR, 'threads');
      }
      if (threadId) {
        row.setAttribute('data-app-action-sidebar-thread-id', threadId);
      }
      wireSyntheticThreadRow(row, entry.row.getAttribute(SOURCE_LIST_ATTR) || 'Tasks', entry.row.getAttribute(SOURCE_TEXT_ATTR) || getThreadTitleForRow(entry.row));
      orderedRows.push(row);
      if (threadId) {
        existingRows.delete(threadId);
      }
    }

    for (const row of existingRows.values()) {
      row.remove();
    }

    const currentRows = getSidebarRows(listElement);
    orderedRows.sort((left, right) => {
      return Number(right.getAttribute(THREAD_UPDATED_ATTR) || 0) - Number(left.getAttribute(THREAD_UPDATED_ATTR) || 0);
    });
    const sameOrder = currentRows.length === orderedRows.length && currentRows.every((row, index) => row === orderedRows[index]);
    if (!sameOrder) {
      listElement.replaceChildren(...orderedRows);
    }
  }

  function getRecentThreadEntries() {
    const catalog = getLiveSidebarCatalog();
    if (!catalog) return [];

    const projectTitleMap = getProjectTitleMap();
    const nativeThreadTitleMap = getNativeThreadTitleMap();
    const seen = new Set();
    const entries = [];

    for (const threadKey of catalog.threadKeys) {
      const record = catalog.records.get(threadKey);
      if (!record) continue;

      const cwd = normalizeProjectId(record.cwd);
      const projectTitle = projectTitleMap.get(cwd) || '';
      const kind = projectTitle ? 'project' : 'task';
      const id = normalizeThreadId(record.id);
      const title = nativeThreadTitleMap.get(id) || normalizeText(record.title);
      const lastModifiedMs = getLiveThreadTimestampMs(record, catalog);
      if (!id || !title || !cwd || lastModifiedMs <= 0) continue;

      const signature = [id, cwd, title, kind].join('|').toLowerCase();
      if (seen.has(signature)) continue;
      seen.add(signature);

      entries.push({
        id,
        title,
        displayTitle: title,
        cwd,
        projectTitle,
        kind,
        lastModifiedMs,
        sourceListLabel: kind === 'project' ? ('Scheduled tasks in ' + projectTitle) : 'Tasks',
        sourceRowText: title
      });
    }

    return entries
      .sort((left, right) => right.lastModifiedMs - left.lastModifiedMs)
      .slice(0, RECENT_THREAD_LIMIT);
  }

  function ensureSyntheticThreadsSection() {
    const projectsHeading = getSidebarSectionTitle(document, 'Projects');
    const projectsShell = getSectionShellFromTitle(projectsHeading);

    if (!projectsShell || !projectsHeading) {
      removeSyntheticSection('threads');
      return null;
    }

    const recentThreadEntries = getRecentThreadEntries();
    if (recentThreadEntries.length === 0) {
      removeSyntheticSection('threads');
      return null;
    }

    const templateRow = getSyntheticThreadTemplateRow();
    const seen = new Set();
    const threadRows = [];
    for (const entry of recentThreadEntries) {
      const signature = [entry.id || '', entry.cwd || '', entry.title, entry.kind].join('|').toLowerCase();
      if (seen.has(signature)) continue;
      seen.add(signature);
      const label = formatThreadLabelFromCatalog(entry);
      const clone = createSyntheticThreadRow(label, entry.lastModifiedMs, templateRow);
      clone.setAttribute('data-codex-plus-thread-id', entry.id);
      clone.setAttribute(SYNTHETIC_ROW_ATTR, 'threads');
      clone.setAttribute(THREAD_UPDATED_ATTR, String(entry.lastModifiedMs));
      setThreadLabel(clone, label, stripThreadTimestampSuffix(label), entry.lastModifiedMs);
      wireSyntheticThreadRow(clone, entry.sourceListLabel || 'Tasks', entry.displayTitle || entry.title);
      threadRows.push({
        row: clone,
        timestampMs: entry.lastModifiedMs,
        label
      });
    }

    threadRows.sort((left, right) => right.timestampMs - left.timestampMs);

    let shell = document.querySelector('[' + SYNTHETIC_SECTION_ATTR + '="threads"]');
    if (!shell) {
      shell = document.createElement('div');
      shell.setAttribute(SYNTHETIC_SECTION_ATTR, 'threads');
    }

    let header = shell.querySelector('[' + THREADS_HEADER_ATTR + ']');
    let sectionContainer = shell.querySelector('[' + THREADS_CONTAINER_ATTR + ']');
    let listElement = shell.querySelector('[' + SYNTHETIC_LIST_ATTR + ']');

    if (!header || !sectionContainer || !listElement) {
      shell.innerHTML = '';

      header = projectsHeading.cloneNode(true);
      header.setAttribute(THREADS_HEADER_ATTR, 'threads');
      const headerButton = header.querySelector('button[data-app-action-sidebar-section-toggle]') || header.querySelector('button');
      if (headerButton) {
        // Keep the project-style section toggle signature (`group/section-toggle`) in the payload.
        syncThreadToggleButton(headerButton, false);
      }
      while (header.children.length > 1) {
        header.lastElementChild.remove();
      }
      if (headerButton) {
        syncThreadToggleButton(headerButton, false);
      }

      shell.appendChild(header);

      sectionContainer = document.createElement('div');
      sectionContainer.setAttribute(THREADS_CONTAINER_ATTR, 'threads');
      const scroller = document.createElement('div');
      listElement = document.createElement('div');
      listElement.setAttribute('role', 'list');
      listElement.setAttribute('aria-label', 'Threads');
      listElement.setAttribute(SYNTHETIC_LIST_ATTR, 'threads');
      scroller.appendChild(listElement);
      sectionContainer.appendChild(scroller);
      shell.appendChild(sectionContainer);
    }

    sectionContainer.hidden = shell.getAttribute(COLLAPSED_ATTR) === 'true';

    writeLoaded(listElement, Math.max(0, readLoaded(listElement)));
    syncSyntheticThreadRows(listElement, threadRows);

    const collapseButton = shell.querySelector('[' + ACTION_ATTR + '="collapse-list"]');
    if (collapseButton && sectionContainer) {
      const collapsed = sectionContainer.hidden || shell.getAttribute(COLLAPSED_ATTR) === 'true';
      syncThreadToggleButton(collapseButton, collapsed);
      bindSingleActivation(collapseButton, (event) => {
        const nextCollapsed = !sectionContainer.hidden;
        sectionContainer.hidden = nextCollapsed;
        shell.setAttribute(COLLAPSED_ATTR, nextCollapsed ? 'true' : 'false');
        syncThreadToggleButton(collapseButton, nextCollapsed);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      });
    }

    if (shell.parentElement !== projectsShell.parentElement || shell.nextSibling !== projectsShell) {
      projectsShell.parentElement.insertBefore(shell, projectsShell);
    }

    return listElement;
  }

  function renderSidebarSection(sectionList, visibleCount, sectionKey) {
    if (!sectionList) return;

    const rows = getSidebarRows(sectionList);
    if (rows.length === 0) return;

    if (sectionKey === 'projects') {
      rows.sort((left, right) => {
        const rightTimestamp = Number(getProjectTimestampMsForRow(right) || 0);
        const leftTimestamp = Number(getProjectTimestampMsForRow(left) || 0);
        if (rightTimestamp !== leftTimestamp) {
          return rightTimestamp - leftTimestamp;
        }

        const leftLabel = normalizeText(getThreadBaseLabel(left) || textOf(left));
        const rightLabel = normalizeText(getThreadBaseLabel(right) || textOf(right));
        return leftLabel.localeCompare(rightLabel);
      });
    }

    for (const row of rows) {
      const timestampMs = sectionKey === 'projects' ? getProjectTimestampMsForRow(row) : getThreadTimestampMsForRow(row);
      const nextLabel = formatThreadLabel(row, sectionKey, null, timestampMs);
      const baseLabel = nextLabel;
      setThreadLabel(row, nextLabel, baseLabel, timestampMs);
    }

    const visibleRows = rows.slice(0, visibleCount);
    const hiddenRows = rows.slice(visibleCount);
    const loaded = Math.max(0, Math.min(readLoaded(sectionList), hiddenRows.length));

    for (const row of visibleRows) {
      setVisible(row, true);
    }
    for (let index = 0; index < hiddenRows.length; index++) {
      setVisible(hiddenRows[index], index < loaded);
    }

    let pager = sectionList.querySelector('[' + PAGER_ATTR + '="' + sectionKey + '"]');
    if (!pager && hiddenRows.length > 0) {
      pager = sectionList.ownerDocument.createElement('div');
      pager.setAttribute('role', 'listitem');
      pager.setAttribute(PAGER_ATTR, sectionKey);
      pager.className = 'flex gap-1 py-1 pl-2 pr-0 after:block after:h-px after:content-[\'\'] last:after:hidden';

      const wrapper = sectionList.ownerDocument.createElement('div');
      wrapper.className = 'flex items-center gap-2';

      const button = sectionList.ownerDocument.createElement('button');
      button.type = 'button';
      button.className = BUTTON_CLASS;
      button.setAttribute(ACTION_ATTR, 'more');
      wrapper.appendChild(button);

      const collapseButton = sectionList.ownerDocument.createElement('button');
      collapseButton.type = 'button';
      collapseButton.className = BUTTON_CLASS;
      collapseButton.setAttribute(ACTION_ATTR, 'less');
      collapseButton.textContent = 'Show less';
      wrapper.appendChild(collapseButton);

      pager.appendChild(wrapper);
    }

    if (pager) {
      const showMoreButton = pager.querySelector('[' + ACTION_ATTR + '="more"]');
      const showLessButton = pager.querySelector('[' + ACTION_ATTR + '="less"]');
      bindSingleActivation(showMoreButton, (event) => {
        const current = readLoaded(sectionList);
        const next = Math.min(hiddenRows.length, (current > 0 ? current : 0) + PAGE_SIZE);
        writeLoaded(sectionList, next);
        renderSidebarSection(sectionList, visibleCount, sectionKey);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      });

      bindSingleActivation(showLessButton, (event) => {
        writeLoaded(sectionList, 0);
        renderSidebarSection(sectionList, visibleCount, sectionKey);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      });

      const hasAny = loaded > 0;
      const hasMore = loaded < hiddenRows.length;
      if (showMoreButton.textContent !== 'Show more') {
        showMoreButton.textContent = 'Show more';
      }
      if (showMoreButton.hidden !== !hasMore) {
        showMoreButton.hidden = !hasMore;
      }
      if (showLessButton.hidden !== !hasAny) {
        showLessButton.hidden = !hasAny;
      }
      const nextPagerHidden = !hasMore && !hasAny;
      if (pager.hidden !== nextPagerHidden) {
        pager.hidden = nextPagerHidden;
      }
      const nextPagerDisplay = nextPagerHidden ? 'none' : 'flex';
      if (pager.style.display !== nextPagerDisplay) {
        pager.style.setProperty('display', nextPagerDisplay, 'important');
      }

      const beforeNode = sectionKey === 'projects' ? null : (hiddenRows[loaded] || null);
      if (pager.parentElement !== sectionList || pager.nextSibling !== beforeNode) {
        sectionList.insertBefore(pager, beforeNode);
      }
    } else {
      writeLoaded(sectionList, 0);
      const existing = sectionList.querySelector('[' + PAGER_ATTR + '="' + sectionKey + '"]');
      if (existing) existing.remove();
    }
  }

  function apply() {
    for (const spec of SECTION_SPECS) {
      const list = spec.synthetic ? ensureSyntheticThreadsSection() : resolveSidebarSectionList(spec);
      if (!list) continue;

      const rows = getSidebarRows(list);
      const visibleCount = Math.min(rows.length, getVisibleCount(rows, spec));
      writeLoaded(list, Math.max(0, Math.min(readLoaded(list), Math.max(0, rows.length - visibleCount))));
      renderSidebarSection(list, visibleCount, spec.key);
    }
    syncSyntheticThreadActiveState();
  }

  let pending = false;
  let applying = false;
  let observing = false;
  const observe = () => {
    if (observing || !document.documentElement) return;
    observer.observe(document.documentElement, {
      attributes: true,
      childList: true,
      subtree: true
    });
    observing = true;
  };
  const disconnect = () => {
    if (!observing) return;
    observer.disconnect();
    observing = false;
  };
  const schedule = () => {
    if (pending || applying) return;
    pending = true;
    window.setTimeout(() => {
      pending = false;
      applying = true;
      try {
        apply();
      } finally {
        applying = false;
      }
    }, 50);
  };

  const observer = new MutationObserver(schedule);
  const start = () => {
    disconnect();
    try {
      applying = true;
      apply();
    } finally {
      applying = false;
      observe();
    }
  };

  window.__CODEX_PLUS_SIDEBAR_PAGING = {
    apply,
    observer
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
'@
}
