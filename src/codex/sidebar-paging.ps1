function Get-CodexSidebarPagingPayload {
    @'
(function () {
  if (window.__CODEX_PLUS_SIDEBAR_PAGING && window.__CODEX_PLUS_SIDEBAR_PAGING.observer) {
    return;
  }

  const SECTION_SELECTOR = '[class*="group/nav-section-title"]';
  const SIDEBAR_ROOT_SELECTOR = '[data-app-action-sidebar-scroll]';
  const PAGE_SIZE = 3;
  const RECENT_WINDOW_MS = 24 * 60 * 60 * 1000;
  const SYNTHETIC_SECTION_ATTR = 'data-codex-plus-sidebar-synthetic-section';
  const SYNTHETIC_LIST_ATTR = 'data-codex-plus-sidebar-synthetic-list';
  const SYNTHETIC_ROW_ATTR = 'data-codex-plus-sidebar-synthetic-row';
  const SOURCE_LIST_ATTR = 'data-codex-plus-source-list-label';
  const SOURCE_TEXT_ATTR = 'data-codex-plus-source-row-text';
  const SOURCE_PROJECT_ID_ATTR = 'data-codex-plus-source-project-id';
  const NAVIGATION_PENDING_ATTR = 'data-codex-plus-thread-navigation-pending';
  const THREAD_SPINNER_ATTR = 'data-codex-plus-thread-spinner';
  const THREAD_NAVIGATION_OVERLAY_ATTR = 'data-codex-plus-thread-navigation-overlay';
  const THREAD_NAVIGATION_MIN_DISPLAY_MS = 100;
  const THREAD_NAVIGATION_TIMEOUT_MS = 20000;
  const SIDEBAR_REFRESH_DEBOUNCE_MS = 250;
  const SIDEBAR_NAVIGATION_REFRESH_RETRY_MS = 100;
  const SIDEBAR_POLL_INTERVAL_MS = 5000;
  const PAGER_ATTR = 'data-codex-plus-sidebar-pager';
  const ACTION_ATTR = 'data-codex-plus-sidebar-action';
  const STATE_ATTR = 'data-codex-plus-sidebar-loaded';
  const COLLAPSED_ATTR = 'data-codex-plus-sidebar-collapsed';
  const THREAD_BASE_LABEL_ATTR = 'data-codex-plus-thread-base-label';
  const THREAD_TIMESTAMP_ATTR = 'data-codex-plus-thread-timestamp-label';
  const NATIVE_TIMESTAMP_ELEMENT_ATTR = 'data-codex-plus-native-timestamp';
  const PROJECT_WINDOW_MARKER = 'data-codex-plus-project-window';
  const THREAD_UNREAD_INDICATOR_ATTR = 'data-codex-plus-thread-unread-indicator';
  const THREAD_UPDATED_ATTR = 'data-codex-plus-thread-updated-ms';
  const THREADS_HEADER_ATTR = 'data-codex-plus-sidebar-threads-header';
  const THREADS_CONTAINER_ATTR = 'data-codex-plus-sidebar-threads-container';
  const BUTTON_CLASS = 'border-token-border no-drag cursor-interaction flex items-center gap-1 border whitespace-nowrap select-none focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 rounded-full text-token-muted-foreground enabled:hover:bg-transparent data-[state=open]:bg-transparent hover:text-token-foreground border-transparent px-2 py-0.5 text-sm leading-[18px] text-token-description-foreground hover:text-token-foreground -ml-[9px]';
  const LEGACY_TIMESTAMP_SUFFIX_SELECTOR = 'span[aria-hidden="true"].pointer-events-none.select-none.whitespace-nowrap.text-token-description-foreground';
  let internalNavigationModulesPromise = null;
  let startupThreadNavigationWarmupStarted = false;
  const nativeThreadTitleCache = new Map();
  let liveCatalogScope = null;
  let liveCatalogStateBinding = null;
  let liveCatalogCache = null;
  let liveCatalogThreadSignature = '';
  let liveCatalogLastRefreshMs = 0;
  let lastLiveSidebarCatalog = null;
  let lastLiveSidebarCatalogAt = 0;
  const LIVE_CATALOG_GAP_GRACE_MS = 2000;
  let liveCatalogSubscriptionScope = null;
  let liveCatalogSubscriptions = [];
  let requestSidebarRefresh = () => {};
  const PAGE_START_TIME = Number(window.performance?.timeOrigin || Date.now());
  const nativeThreadUnreadIndicatorCache = new Map();
  const nativeThreadUnreadStateCache = new Set();
  const nativeThreadWorkingCache = new Set();

  const SECTION_SPECS = [
    { key: 'threads', title: 'Recents', minVisibleCount: 3, synthetic: true },
    { key: 'projects', title: 'Projects', minVisibleCount: 2 },
    { key: 'tasks', labels: ['Tasks', 'Chats'], minVisibleCount: 3 }
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

  function getSidebarObserverRoot() {
    return document.querySelector(SIDEBAR_ROOT_SELECTOR);
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
      // Project thread buttons can be nested inside one project-level
      // listitem. Prefer the actual thread row so every nested thread keeps
      // its own id, title, and unread state.
      const row = candidate.closest('[data-app-action-sidebar-thread-row]') || candidate;
      if (getThreadIdForRow(row)) {
        rows.add(row);
      }
    }
    return Array.from(rows);
  }

  function getWorkingThreadIds() {
    const workingThreadIds = new Set();
    const liveStatusKnownThreadIds = new Set();
    const catalog = getLiveSidebarCatalog(true);
    for (const record of catalog?.records?.values?.() || []) {
      const threadId = normalizeThreadId(record?.id || record?.key);
      const liveStatus = getLiveThreadStatus(record);
      const statusType = liveStatus?.type;
      if (threadId && statusType) {
        liveStatusKnownThreadIds.add(threadId);
      }
      if (threadId && isWorkingThreadStatus(liveStatus)) {
        workingThreadIds.add(threadId);
      } else if (threadId && statusType && statusType !== 'notLoaded') {
        nativeThreadWorkingCache.delete(threadId);
      }
    }

    for (const threadId of nativeThreadWorkingCache) {
      if (!liveStatusKnownThreadIds.has(threadId)) {
        workingThreadIds.add(threadId);
      }
    }

    for (const row of getNativeThreadRows()) {
      const threadId = normalizeThreadId(getThreadIdForRow(row));
      const statusState = getReactThreadStatusState(row);
      if (!threadId || !statusState?.type) continue;

      const hasUnread = Boolean(
        statusState.unread || Number(statusState.unreadCount || 0) > 0
      );
      if (hasUnread) {
        nativeThreadUnreadStateCache.add(threadId);
      } else if (statusState.unread === false || statusState.unreadCount !== undefined) {
        nativeThreadUnreadStateCache.delete(threadId);
      }

      if (statusState?.type === 'loading' && !liveStatusKnownThreadIds.has(threadId)) {
        nativeThreadWorkingCache.add(threadId);
        workingThreadIds.add(threadId);
      } else {
        nativeThreadWorkingCache.delete(threadId);
      }
    }
    return workingThreadIds;
  }

  function getProjectWindowContext() {
    try {
      const parseParams = (params) => {
        const id = normalizeText(params.get('codexPlusProjectId'));
        const name = normalizeText(params.get('codexPlusProjectName'));
        return id && name ? { id, name } : null;
      };
      const direct = parseParams(new URLSearchParams(window.location.search));
      if (direct) {
        try {
          const pending = JSON.parse(localStorage.getItem('codexPlusPendingProjectWindows') || '[]');
          const matchIndex = pending.findIndex((entry) => (
            normalizeText(entry?.codexPlusProjectId) === direct.id
            && normalizeText(entry?.codexPlusProjectName) === direct.name
          ));
          if (matchIndex >= 0) {
            pending.splice(matchIndex, 1);
            localStorage.setItem('codexPlusPendingProjectWindows', JSON.stringify(pending));
          }
        } catch {}
        window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT = direct;
        return direct;
      }

      const startupRoute = new URLSearchParams(window.location.search).get('initialRoute') || '';
      let decodedRoute = startupRoute;
      try { decodedRoute = decodeURIComponent(startupRoute); } catch {}

      try {
        const pending = JSON.parse(localStorage.getItem('codexPlusPendingProjectWindows') || '[]');
        const matchIndex = pending.findIndex((entry) => {
          const route = normalizeText(entry?.startupPath);
          const createdAt = Number(entry?.createdAt || 0);
          const isNewWindowRequest = createdAt > 0
            && PAGE_START_TIME >= createdAt - 1000
            && PAGE_START_TIME - createdAt <= 60000;
          return route && (
            route === startupRoute
            || route === decodedRoute
            || (!startupRoute && route === '/')
          ) && isNewWindowRequest;
        });
        if (matchIndex >= 0) {
          const match = pending[matchIndex];
          pending.splice(matchIndex, 1);
          localStorage.setItem('codexPlusPendingProjectWindows', JSON.stringify(pending));
          const pendingContext = parseParams(new URLSearchParams(
            'codexPlusProjectId=' + encodeURIComponent(match.codexPlusProjectId || '')
              + '&codexPlusProjectName=' + encodeURIComponent(match.codexPlusProjectName || '')
          ));
          if (pendingContext) {
            window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT = pendingContext;
            const homeUrl = new URL(window.location.href);
            homeUrl.searchParams.set('initialRoute', '/');
            window.history.replaceState(window.history.state, '', homeUrl.toString());
            return pendingContext;
          }
        }
      } catch {}

      if (!startupRoute) return null;

      const context = parseParams(new URLSearchParams(new URL(decodedRoute, window.location.origin).search));
      if (!context) return null;

      window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT = context;
      if (context && decodedRoute.startsWith('/')) {
        const homeUrl = new URL(window.location.href);
        homeUrl.searchParams.set('initialRoute', '/');
        window.history.replaceState(window.history.state, '', homeUrl.toString());
      }
      return context;
    } catch {
      return null;
    }
  }

  let projectWindowContext = null;
  let projectWindowMetadataInterval = null;
  function adoptProjectWindowContext(context) {
    if (!context?.id || !context?.name || projectWindowContext) return false;
    projectWindowContext = context;
    window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT = context;
    const reinforceProjectWindowMetadata = () => {
      const projectRow = findProjectRowById(projectWindowContext.id);
      const liveName = projectRow ? getProjectLabelForRow(projectRow) : '';
      if (liveName && liveName !== projectWindowContext.name) {
        projectWindowContext = { ...projectWindowContext, name: liveName };
        window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT = projectWindowContext;
        requestSidebarRefresh();
      }
      document.documentElement?.setAttribute(PROJECT_WINDOW_MARKER, projectWindowContext.id);
      const projectWindowTitle = 'Codex Plus Project: ' + projectWindowContext.name;
      if (document.title !== projectWindowTitle) document.title = projectWindowTitle;
    };
    reinforceProjectWindowMetadata();
    if (projectWindowMetadataInterval) window.clearInterval(projectWindowMetadataInterval);
    projectWindowMetadataInterval = window.setInterval(reinforceProjectWindowMetadata, 250);
    return true;
  }

  adoptProjectWindowContext(getProjectWindowContext());

  function tryClaimPendingProjectWindowContext() {
    if (projectWindowContext) return;
    if (adoptProjectWindowContext(getProjectWindowContext())) {
      requestSidebarRefresh();
    }
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

    const threadId = normalizeLiveThreadKey(conversation?.id || conversation?.conversationId);
    if (!threadId) return '';
    const hostId = normalizeLiveThreadKey(task?.kind || task?.hostId || conversation?.hostId || 'local') || 'local';
    return hostId + ':' + threadId;
  }

  function addLiveThreadRecord(records, bindings, value, binding, unreadPriority) {
    const task = value?.task || value;
    const conversation = task?.conversation || (
      task?.id || task?.conversationId
        ? task
        : null
    );
    const conversationId = conversation?.id || conversation?.conversationId;
    if (!conversation || !conversationId) return;

    const key = getLiveThreadRecordKey(task, conversation);
    if (!key) return;

    const previous = records.get(key) || {};
    const nextStatus = conversation.threadRuntimeStatus || conversation.statusState || null;
    const previousStatus = previous.threadRuntimeStatus || null;
    const mergedStatus = isWorkingThreadStatus(nextStatus) || isWorkingThreadStatus(previousStatus)
      ? (isWorkingThreadStatus(nextStatus) ? nextStatus : previousStatus)
      : (nextStatus || previousStatus);
    const nextUpdatedAt = Math.max(
      Number(previous.updatedAt || 0),
      Number(conversation.updatedAt || 0)
    ) || conversation.updatedAt || previous.updatedAt || 0;
    const nextCreatedAt = Math.min(
      Number(previous.createdAt || 0) || Number.MAX_SAFE_INTEGER,
      Number(conversation.createdAt || 0) || Number.MAX_SAFE_INTEGER
    );
    const currentUnread = conversation.hasUnreadTurn !== undefined
      ? Boolean(conversation.hasUnreadTurn)
      : conversation.unread !== undefined
        ? Boolean(conversation.unread)
        : null;
    const currentUnreadCount = conversation.unreadCount !== undefined
      ? Number(conversation.unreadCount)
      : null;
    const currentUnreadStateKnown = currentUnread !== null || Number.isFinite(currentUnreadCount);
    const currentUnreadPriority = currentUnreadStateKnown ? Number(unreadPriority || 0) : -1;
    const previousUnreadPriority = Number(previous.unreadStatePriority ?? -1);
    const shouldApplyUnreadState = currentUnreadStateKnown
      && (!previous.unreadStateKnown || currentUnreadPriority >= previousUnreadPriority);
    const unreadStateKnown = currentUnreadStateKnown || Boolean(previous.unreadStateKnown);
    const hasUnreadTurn = shouldApplyUnreadState
      ? currentUnread !== null
        ? currentUnread
        : currentUnreadCount > 0
      : Boolean(previous.hasUnreadTurn);
    const unreadCount = shouldApplyUnreadState
      ? Number.isFinite(currentUnreadCount)
        ? Math.max(0, currentUnreadCount)
        : currentUnread === false
          ? 0
          : Number(previous.unreadCount || 0)
      : Number(previous.unreadCount || 0);

    records.set(key, {
      ...previous,
      key,
      id: String(conversationId),
      title: normalizeText(conversation.title) || previous.title || '',
      cwd: normalizeText(conversation.cwd) || previous.cwd || '',
      updatedAt: nextUpdatedAt,
      createdAt: nextCreatedAt === Number.MAX_SAFE_INTEGER ? (conversation.createdAt || previous.createdAt || 0) : nextCreatedAt,
      source: normalizeText(conversation.source || task?.source) || previous.source || '',
      kind: normalizeText(task?.kind || task?.hostId || conversation.hostId) || previous.kind || '',
      unreadStateKnown,
      hasUnreadTurn,
      unreadCount,
      unreadStatePriority: shouldApplyUnreadState
        ? currentUnreadPriority
        : previousUnreadPriority,
      threadRuntimeStatus: mergedStatus
    });
    bindings.set(key, binding);
  }

  function collectLiveThreadValue(records, bindings, value, binding) {
    if (Array.isArray(value)) {
      for (const item of value) {
        addLiveThreadRecord(records, bindings, item, binding, 2);
      }
      return;
    }

    for (const collection of [
      value?.recentConversations,
      value?.threadSummaries,
      value?.conversations instanceof Map ? Array.from(value.conversations.values()) : null
    ]) {
      if (!Array.isArray(collection)) continue;
      for (const item of collection) {
        addLiveThreadRecord(records, bindings, item, binding, 2);
      }
    }

    // The top-level manager record can lag behind the summaries after a thread
    // is opened. Keep it useful for runtime status, but let collection-backed
    // unread state win over a stale hasUnreadTurn=true value.
    addLiveThreadRecord(records, bindings, value, binding, 1);
  }

  function clearLiveCatalogSubscriptions() {
    for (const unsubscribe of liveCatalogSubscriptions) {
      try { unsubscribe(); } catch {}
    }
    liveCatalogSubscriptions = [];
    liveCatalogSubscriptionScope = null;
  }

  function subscribeToLiveThreadBindings(scope, cachedBindings) {
    if (!scope?.node?.store || typeof scope.node.store.sub !== 'function') return;
    if (
      liveCatalogSubscriptionScope === scope
      && liveCatalogSubscriptions.length === cachedBindings.size
    ) {
      return;
    }

    clearLiveCatalogSubscriptions();
    liveCatalogSubscriptionScope = scope;
    for (const [binding] of cachedBindings.entries()) {
      try {
        const unsubscribe = scope.node.store.sub(binding, () => requestSidebarRefresh());
        if (typeof unsubscribe === 'function') {
          liveCatalogSubscriptions.push(unsubscribe);
        }
      } catch {
      }
    }
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

  function getLiveSidebarCatalog(forceScan) {
    const scope = getAppScopeFromSidebar();
    const fallback = () => {
      return lastLiveSidebarCatalog && Date.now() - lastLiveSidebarCatalogAt < LIVE_CATALOG_GAP_GRACE_MS
        ? lastLiveSidebarCatalog
        : null;
    };
    if (!scope) return fallback();

    if (liveCatalogScope !== scope) {
      liveCatalogScope = scope;
      liveCatalogStateBinding = null;
      liveCatalogCache = null;
      liveCatalogThreadSignature = '';
      liveCatalogLastRefreshMs = 0;
    }

    const stateResult = getLiveThreadCatalogState(scope);
    if (!stateResult) return fallback();

    subscribeToLiveThreadBindings(scope, stateResult.cachedBindings);

    const catalog = {
      scope,
      state: stateResult.state,
      cachedBindings: stateResult.cachedBindings
    };
    refreshLiveThreadBindings(catalog, Boolean(forceScan));
    const threadKeys = Array.from(new Set([
      ...(Array.isArray(stateResult.state.threadKeys)
        ? stateResult.state.threadKeys.map(normalizeLiveThreadKey).filter(Boolean)
        : []),
      ...Array.from(liveCatalogCache?.records?.keys?.() || [])
        .map(normalizeLiveThreadKey)
        .filter(Boolean)
    ]));
    const result = {
      scope,
      state: stateResult.state,
      // The state key list can lag behind binding-backed conversation records
      // while a thread changes read/status state. Keep both sources so a real
      // unread thread is still eligible for the synthetic Recents list.
      threadKeys,
      records: liveCatalogCache?.records || new Map(),
      projectGroups: Array.isArray(stateResult.state.projectGroups) ? stateResult.state.projectGroups : [],
      cachedBindings: stateResult.cachedBindings
    };
    if (result.threadKeys.length > 0 && result.records.size > 0) {
      lastLiveSidebarCatalog = result;
      lastLiveSidebarCatalogAt = Date.now();
    }
    return result;
  }

  function getLiveThreadRecordById(catalog, threadId) {
    const normalizedThreadId = normalizeThreadId(threadId);
    if (!normalizedThreadId) return null;

    const matches = Array.from(catalog?.records?.entries?.() || [])
      .filter(([key, record]) => normalizeThreadId(record?.id || key) === normalizedThreadId);
    const match = matches.find(([, record]) => {
      return Boolean(record?.hasUnreadTurn)
        || Number(record?.unreadCount || 0) > 0
        || isWorkingThreadStatus(getLiveThreadStatus(record));
    }) || matches[0] || null;
    if (!match) return null;

    const [key, record] = match;
    const attentionState = catalog?.state?.threadAttentionStateByKey?.get?.(key);
    if (attentionState === undefined) return record;
    return {
      ...record,
      unreadStateKnown: true,
      hasUnreadTurn: attentionState === 'unread',
      unreadCount: attentionState === 'unread' ? Math.max(1, Number(record?.unreadCount || 0)) : 0
    };
  }

  function getProjectGroupForThreadKey(catalog, threadKey) {
    const normalizedThreadKey = normalizeLiveThreadKey(threadKey);
    if (!normalizedThreadKey) return null;

    return (catalog?.projectGroups || []).find((group) => {
      return Array.isArray(group?.threadKeys)
        && group.threadKeys.some((candidate) => normalizeLiveThreadKey(candidate) === normalizedThreadKey);
    }) || null;
  }

  function getProjectTitleFromGroup(group) {
    return normalizeText(group?.label || group?.path || group?.projectId);
  }

  function getLiveThreadStatus(record) {
    const status = record?.threadRuntimeStatus;
    return status && typeof status.type === 'string' ? status : null;
  }

  function isWorkingThreadStatus(status) {
    return status?.type === 'loading' || status?.type === 'active';
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

  function getMainSurface() {
    return document.querySelector('main.main-surface') || document.querySelector('main');
  }

  function getThreadConversationElement() {
    return document.querySelector('[data-thread-find-target="conversation"]');
  }

  function createThreadSpinnerGraphic() {
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
    return svg;
  }

  function createThreadSpinner() {
    const overlay = document.createElement('div');
    overlay.setAttribute(THREAD_SPINNER_ATTR, 'true');
    overlay.className = 'flex shrink-0 items-center justify-end absolute right-0 top-0 z-10 flex h-full min-w-[52px] items-center justify-end gap-2 pr-1';
    positionSyntheticStatusIndicator(overlay);

    const slot = document.createElement('span');
    slot.className = 'flex h-5 min-w-5 items-center justify-center';
    const spinner = document.createElement('div');
    spinner.className = 'relative flex size-5 shrink-0 items-center justify-center text-token-foreground/70';
    const animated = document.createElement('div');
    animated.className = 'animate-spin inline-flex h-fit w-fit items-center justify-center leading-none contain-layout contain-paint contain-style';
    animated.style.animationDelay = '-540ms';
    animated.style.animationDuration = '2000ms';
    const svg = createThreadSpinnerGraphic();
    animated.appendChild(svg);
    spinner.appendChild(animated);
    slot.appendChild(spinner);
    overlay.appendChild(slot);
    return overlay;
  }

  function createThreadNavigationOverlay() {
    const overlay = document.createElement('div');
    overlay.setAttribute(THREAD_NAVIGATION_OVERLAY_ATTR, 'true');
    overlay.setAttribute('role', 'status');
    overlay.setAttribute('aria-label', 'Loading thread');
    overlay.className = 'pointer-events-none absolute inset-0 z-20 flex items-center justify-center text-token-foreground/80';

    const animated = document.createElement('div');
    animated.className = 'animate-spin inline-flex h-fit w-fit items-center justify-center leading-none contain-layout contain-paint contain-style';
    animated.style.animationDuration = '2000ms';
    const graphic = createThreadSpinnerGraphic();
    graphic.setAttribute('class', 'size-6 shrink-0');
    animated.appendChild(graphic);
    overlay.appendChild(animated);
    return overlay;
  }

  let threadNavigationState = null;
  let threadNavigationTimer = 0;
  let threadNavigationSequence = 0;

  function clearThreadNavigationLoading(sequence) {
    if (!threadNavigationState || (sequence && threadNavigationState.sequence !== sequence)) return;
    if (threadNavigationTimer) {
      window.clearTimeout(threadNavigationTimer);
      threadNavigationTimer = 0;
    }
    threadNavigationState.overlay?.remove();
    threadNavigationState = null;
    window.__CODEX_PLUS_CONTEXT_BADGE?.clearStatus();
  }

  function isThreadNavigationReady(state) {
    if (normalizeThreadId(getActiveThreadId()) !== state.targetThreadId) return false;
    if (performance.now() - state.startedAt < THREAD_NAVIGATION_MIN_DISPLAY_MS) return false;

    const conversation = getThreadConversationElement();
    const conversationText = normalizeText(conversation?.innerText || '');
    if (conversation && conversation !== state.initialConversation) {
      return conversationText.length > 0;
    }
    if (conversationText && conversationText !== state.initialConversationText) return true;

    return !conversation && performance.now() - state.startedAt >= 350;
  }

  function checkThreadNavigationLoading(sequence) {
    if (!threadNavigationState || threadNavigationState.sequence !== sequence) return;

    const elapsed = performance.now() - threadNavigationState.startedAt;
    if (isThreadNavigationReady(threadNavigationState) || elapsed >= THREAD_NAVIGATION_TIMEOUT_MS) {
      clearThreadNavigationLoading(sequence);
      return;
    }

    threadNavigationTimer = window.setTimeout(() => checkThreadNavigationLoading(sequence), 50);
  }

  function startThreadNavigationLoading(threadId) {
    const targetThreadId = normalizeThreadId(threadId);
    if (!targetThreadId || targetThreadId === normalizeThreadId(getActiveThreadId())) return;
    if (threadNavigationState?.targetThreadId === targetThreadId) return;

    const mainSurface = getMainSurface();
    if (!mainSurface) return;

    clearThreadNavigationLoading();
    const overlay = createThreadNavigationOverlay();
    mainSurface.appendChild(overlay);
    const sequence = ++threadNavigationSequence;
    threadNavigationState = {
      sequence,
      targetThreadId,
      initialConversation: getThreadConversationElement(),
      initialConversationText: normalizeText(getThreadConversationElement()?.innerText || ''),
      startedAt: performance.now(),
      overlay
    };
    window.__CODEX_PLUS_CONTEXT_BADGE?.setStatus('- Loading thread');
    checkThreadNavigationLoading(sequence);
  }

  function getThreadNavigationRowFromEvent(event) {
    const target = event?.target;
    if (!(target instanceof Element)) return null;

    const row = target.closest('[data-app-action-sidebar-thread-id]');
    if (!row) return null;
    const isSyntheticRow = Boolean(row.closest('[' + SYNTHETIC_ROW_ATTR + '="threads"]'));
    const isNativeRow = row.hasAttribute('data-app-action-sidebar-thread-row');
    if (!isSyntheticRow && !isNativeRow) return null;

    // Native rows expose pin/archive controls inside the same clickable wrapper.
    if (target.closest('button[aria-label]') && !target.closest('[data-thread-title-trigger="true"]')) return null;
    return row;
  }

  function handleThreadNavigationEvent(event) {
    const row = getThreadNavigationRowFromEvent(event);
    if (!row) return;

    const threadId = normalizeThreadId(
      row.getAttribute('data-codex-plus-thread-id') || getThreadIdForRow(row)
    );
    startThreadNavigationLoading(threadId);
  }

  function startThreadNavigationLoadingMonitor() {
    if (window.__CODEX_PLUS_THREAD_NAVIGATION_LOADING_MONITOR) return;
    window.__CODEX_PLUS_THREAD_NAVIGATION_LOADING_MONITOR = true;
    document.addEventListener('pointerup', handleThreadNavigationEvent, true);
    document.addEventListener('click', handleThreadNavigationEvent, true);
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

  function getThreadUnreadIndicator(row) {
    if (!row) return null;

    const owned = row.querySelector('[' + THREAD_UNREAD_INDICATOR_ATTR + ']');
    if (owned) return owned;

    const button = getSyntheticThreadButton(row);
    if (!button) return null;

    const indicator = Array.from(button.children).find((candidate) => {
      if (!candidate.classList.contains('shrink-0')) return false;
      return Boolean(candidate.querySelector('.icon-xs.relative.scale-50 .absolute.inset-0.rounded-full'));
    }) || null;

    const threadId = normalizeThreadId(getThreadIdForRow(row));
    if (indicator && threadId) {
      nativeThreadUnreadIndicatorCache.set(threadId, indicator.cloneNode(true));
    }
    return indicator;
  }

  function keepSyntheticUnreadIndicatorVisible(indicator) {
    if (!indicator?.classList) return indicator;
    indicator.classList.remove('group-hover:hidden');
    indicator.classList.remove('group-has-[:focus-visible]:hidden');
    return indicator;
  }

  function positionSyntheticStatusIndicator(indicator) {
    if (!indicator?.style) return indicator;

    // Native unread indicators are normally absolutely positioned at the row
    // edge. A cloned indicator can lose that layout when it is moved into a
    // synthetic row, which makes the inline timestamp shift left. Keep the
    // dot out of the title flex row so timestamps share one right edge.
    indicator.style.position = 'absolute';
    indicator.style.top = '0px';
    indicator.style.right = '0px';
    indicator.style.left = 'auto';
    indicator.style.height = '100%';
    indicator.style.minWidth = '52px';
    indicator.style.display = 'flex';
    indicator.style.alignItems = 'center';
    indicator.style.justifyContent = 'flex-end';
    indicator.style.paddingRight = '4px';
    indicator.style.zIndex = '10';
    indicator.style.pointerEvents = 'none';
    return indicator;
  }

  function positionNativeThreadStatusSlot(row) {
    if (!row) return;

    for (const nativeRow of Array.from(row.querySelectorAll('[data-app-action-sidebar-thread-row]'))) {
      const statusSlot = Array.from(nativeRow.querySelectorAll('*')).find((candidate) => {
        return candidate.classList.contains('shrink-0')
          && candidate.classList.contains('group-hover:hidden')
          && candidate.getBoundingClientRect().width > 0;
      });
      if (!statusSlot || !statusSlot.parentElement) continue;

      // Native working/unread slots can reserve 24px even when their visible
      // child is hidden. Overlay the slot so that it cannot move the timestamp.
      const contentRow = statusSlot.parentElement;
      contentRow.style.position = 'relative';
      statusSlot.style.position = 'absolute';
      statusSlot.style.top = '0px';
      statusSlot.style.right = '0px';
      statusSlot.style.height = '100%';
    }
  }

  function installNativeThreadStatusSlotStyle() {
    const styleId = 'codex-plus-thread-status-slot-style';
    if (document.getElementById(styleId)) return;

    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = '[data-app-action-sidebar-thread-row] [class~="shrink-0"][class~="group-hover:hidden"] {'
      + 'position: absolute !important; top: 0 !important; right: 0 !important; height: 100% !important;'
      + '}';
    (document.head || document.documentElement).appendChild(style);
  }

  function getNativeThreadUnreadState(row) {
    const statusState = getReactThreadStatusState(row);
    if (!statusState || typeof statusState.type !== 'string') return null;
    if (statusState.unread === undefined && statusState.unreadCount === undefined) return null;
    return Boolean(statusState.unread || Number(statusState.unreadCount || 0) > 0);
  }

  function createThreadUnreadIndicator() {
    const indicator = document.createElement('div');
    indicator.className = 'flex shrink-0 items-center justify-end absolute right-0 top-0 z-10 flex h-full min-w-[52px] items-center justify-end gap-2 pr-1 group-hover:hidden group-has-[:focus-visible]:hidden';
    indicator.setAttribute(THREAD_UNREAD_INDICATOR_ATTR, 'true');
    indicator.setAttribute('aria-hidden', 'true');

    const slot = document.createElement('span');
    slot.className = 'flex h-5 min-w-5 items-center justify-center';
    const status = document.createElement('div');
    status.className = 'relative flex size-5 shrink-0 items-center justify-center text-token-description-foreground';
    const icon = document.createElement('span');
    icon.className = 'icon-xs relative scale-50';
    const dot = document.createElement('span');
    dot.className = 'absolute inset-0 rounded-full';
    dot.style.backgroundColor = 'var(--vscode-textLink-foreground)';
    icon.appendChild(dot);
    status.appendChild(icon);
    slot.appendChild(status);
    indicator.appendChild(slot);
    return indicator;
  }

  function syncThreadUnreadIndicator(row, nativeRow, liveRecord) {
    if (!row) return;

    const existing = row.querySelector('[' + THREAD_UNREAD_INDICATOR_ATTR + ']');
    const source = getThreadUnreadIndicator(nativeRow);
    const threadId = normalizeThreadId(row.getAttribute('data-codex-plus-thread-id') || getThreadIdForRow(row));
    const nativeUnread = nativeRow ? getNativeThreadUnreadState(nativeRow) : null;
    const liveUnreadKnown = liveRecord?.unreadStateKnown === true;
    const liveUnread = liveUnreadKnown
      ? Boolean(liveRecord?.hasUnreadTurn || Number(liveRecord?.unreadCount || 0) > 0)
      : null;
    // The live conversation catalog is the current source of truth. The native
    // sidebar row can briefly retain an old unread flag while Codex reconciles
    // the opened thread, which otherwise makes the dot flicker back on.
    const authoritativeUnread = liveUnread !== null ? liveUnread : nativeUnread;
    if (threadId && nativeUnread !== null) {
      if (nativeUnread) {
        nativeThreadUnreadStateCache.add(threadId);
      } else {
        nativeThreadUnreadStateCache.delete(threadId);
      }
    }
    if (threadId && liveUnread !== null && nativeUnread === null) {
      if (liveUnread) {
        nativeThreadUnreadStateCache.add(threadId);
      } else {
        nativeThreadUnreadStateCache.delete(threadId);
      }
    }
    if (nativeRow && !source && threadId) {
      nativeThreadUnreadIndicatorCache.delete(threadId);
    }
    if (authoritativeUnread === false) {
      if (existing) existing.remove();
      if (threadId) {
        nativeThreadUnreadIndicatorCache.delete(threadId);
        nativeThreadUnreadStateCache.delete(threadId);
      }
      return;
    }
    const cached = !nativeRow && threadId ? nativeThreadUnreadIndicatorCache.get(threadId) : null;
    const cachedUnread = Boolean(threadId && nativeThreadUnreadStateCache.has(threadId));
    const hasUnread = Boolean(authoritativeUnread === true || cachedUnread);
    if (!source && !cached && !hasUnread) {
      if (existing) existing.remove();
      return;
    }

    // Refreshes are frequent while the conversation catalog and native sidebar
    // reconcile. Keep the current node when the unread state is still true;
    // replacing it on every refresh causes the dot to visibly flicker.
    if (existing && hasUnread) return;

    const button = getSyntheticThreadButton(row);
    if (!button) return;

    const next = positionSyntheticStatusIndicator(keepSyntheticUnreadIndicatorVisible(
      (source || cached || createThreadUnreadIndicator()).cloneNode(true)
    ));
    next.setAttribute(THREAD_UNREAD_INDICATOR_ATTR, 'true');
    if (existing) {
      existing.replaceWith(next);
      return;
    }

    const mainContent = Array.from(button.children).find((candidate) => {
      return candidate.querySelector?.('[data-thread-title-trigger="true"]');
    });
    if (mainContent?.parentElement === button) {
      button.insertBefore(next, mainContent);
    } else {
      button.appendChild(next);
    }
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

  function prepareThreadForActivation(modules, scope, threadId, hostId) {
    const prepareThread = modules?.appServer?.Et;
    if (typeof prepareThread !== 'function') return;
    prepareThread(scope, threadId, hostId);
  }

  function getThreadNavigationLocation(sourceListLabel, sourceProjectId) {
    const directProjectId = normalizeProjectId(sourceProjectId);
    if (directProjectId) return 'project:' + directProjectId;
    const projectLabel = getProjectLabelFromSourceList(sourceListLabel);
    if (projectLabel) {
      const projectRow = findProjectRowByLabel(projectLabel);
      const projectId = getProjectIdForRow(projectRow);
      if (projectId) return 'project:' + projectId;
    }
    return 'flat-chats';
  }

  function warmStartupThreadNavigation() {
    if (startupThreadNavigationWarmupStarted) return;
    startupThreadNavigationWarmupStarted = true;
    // Importing the private navigation modules removes first-click module
    // discovery cost. Do not activate conversations here: those operations
    // continue asynchronously and can compete with or override a real click.
    void getInternalNavigationModules();
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
      prepareThreadForActivation(modules, scope, threadId, hostId);
      manager.activateThreadSummary(threadId);
      if (typeof manager.getConversation === 'function' && !manager.getConversation(threadId)) {
        return false;
      }
      routerNavigator.push('/local/' + threadId);
      modules.navigation.t(
        scope,
        hostId + ':' + threadId,
        getThreadNavigationLocation(threadRow.getAttribute(SOURCE_LIST_ATTR), threadRow.getAttribute(SOURCE_PROJECT_ID_ATTR))
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
    const environment = group?.cloudEnvironment;
    return Math.max(
      toTimestampMs(environment?.updated_at),
      toTimestampMs(environment?.modified_at),
      toTimestampMs(environment?.created_at)
    );
  }

  function getDisplayedModifiedTimestampMs(row) {
    const label = normalizeText(textOf(getThreadTitleElement(row)) || textOf(row));
    const match = label.match(/\[(\d+)(m|h|d)\]$/i);
    if (!match) return 0;

    const amount = Number(match[1] || 0);
    const unitMs = match[2].toLowerCase() === 'm'
      ? 60000
      : (match[2].toLowerCase() === 'h' ? 3600000 : 86400000);
    return Math.max(0, Date.now() - amount * unitMs);
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
    const titleElement = row.querySelector('[data-thread-title="true"], .text-fade-truncate');
    if (titleElement) return titleElement;

    // `data-app-action-sidebar-thread-title` lives on Codex's native row wrapper,
    // not on the element that lays out the title. Selecting it appends the
    // timestamp below the row instead of beside the title.
    return Array.from(row.querySelectorAll('[data-app-action-sidebar-thread-title]'))
      .find((candidate) => !candidate.hasAttribute('data-app-action-sidebar-thread-row')) || null;
  }

  function stripThreadTimestampSuffix(label) {
    return normalizeText(label).replace(/\s+\[[^\]]+\]$/, '').trim();
  }

  function formatThreadModifiedTime(updatedMs) {
    const timestampMs = Number(updatedMs || 0);
    if (timestampMs <= 0) return '';

    const elapsedMs = Math.max(0, Date.now() - timestampMs);
    const elapsedMinutes = Math.floor(elapsedMs / 60000);
    if (elapsedMinutes < 1) return '0m';
    if (elapsedMinutes < 60) return elapsedMinutes + 'm';

    const elapsedHours = Math.floor(elapsedMinutes / 60);
    if (elapsedHours < 24) return elapsedHours + 'h';

    return Math.floor(elapsedHours / 24) + 'd';
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

  function isThreadSidebarRow(row) {
    return Boolean(
      getThreadIdForRow(row)
      || row?.getAttribute(SYNTHETIC_ROW_ATTR) === 'threads'
    );
  }

  function syncThreadToggleButton(button, collapsed, headingLabel = 'Threads') {
    if (!button) return;
    const normalizedHeadingLabel = normalizeText(headingLabel) || 'Threads';
    const nextLabel = collapsed ? 'Show ' + normalizedHeadingLabel + ' list' : 'Hide ' + normalizedHeadingLabel + ' list';
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
    if (labelSpan && normalizeText(labelSpan.textContent) !== normalizedHeadingLabel) {
      labelSpan.textContent = normalizedHeadingLabel;
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

  function findProjectRowById(projectId) {
    const normalizedProjectId = normalizeProjectId(projectId);
    if (!normalizedProjectId) return null;
    return Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
      .find((row) => normalizeProjectId(getProjectIdForRow(row)) === normalizedProjectId) || null;
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

  function wireSyntheticThreadRow(row, sourceListLabel, sourceRowText, sourceProjectId) {
    if (!row) return;
    if (row.getAttribute('data-codex-plus-thread-wired') === 'true') {
      return;
    }
    row.setAttribute(SOURCE_LIST_ATTR, sourceListLabel);
    row.setAttribute(SOURCE_TEXT_ATTR, sourceRowText);
    if (sourceProjectId) row.setAttribute(SOURCE_PROJECT_ID_ATTR, sourceProjectId);

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

  function getNativePinnedThreadIds() {
    const pinnedThreadIds = new Set();
    const rows = new Set(getNativeThreadRows());
    for (const row of Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-pinned="true"]'))) {
      if (!row.closest('[' + SYNTHETIC_ROW_ATTR + '="threads"]')) rows.add(row);
    }
    for (const row of rows) {
      const threadId = normalizeThreadId(getThreadIdForRow(row));
      if (!threadId) continue;
      const pinned = row.getAttribute('data-app-action-sidebar-thread-pinned') === 'true';
      if (pinned) pinnedThreadIds.add(threadId);
    }
    return pinnedThreadIds;
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
    if (entry?.kind === 'project') {
      if (projectWindowContext) return title;
      const projectTitle = normalizeText(entry?.projectTitle) || 'project';
      return title + ' (' + projectTitle + ')';
    }
    return title + ' (task)';
  }

  function isPlaceholderThreadTitle(title) {
    const normalized = normalizeText(title).toLowerCase();
    return normalized === 'new chat'
      || normalized === 'new task'
      || normalized === 'untitled';
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

    if (titleElement) {
      styleThreadTitleElement(titleElement);
      const titleHost = titleElement.parentElement;
      let timestampElement = row.querySelector('[' + NATIVE_TIMESTAMP_ELEMENT_ATTR + ']');
      const timestampText = nextTimestampLabel ? '[' + nextTimestampLabel + ']' : '';

      if (timestampText && titleHost) {
        // Keep thread and task timestamps inset like project rows instead of pushing them to the edge.
        titleHost.classList.toggle('pr-6', isThreadSidebarRow(row));
        positionNativeThreadStatusSlot(row);
        if (!timestampElement) {
          timestampElement = row.ownerDocument.createElement('span');
          timestampElement.setAttribute(NATIVE_TIMESTAMP_ELEMENT_ATTR, 'true');
          timestampElement.className = 'ms-1 inline-flex shrink-0 items-center whitespace-nowrap text-xs text-token-text-tertiary';
        }
        if (timestampElement.parentElement !== titleHost) {
          titleHost.appendChild(timestampElement);
        }
        if (timestampElement.textContent !== timestampText) {
          timestampElement.textContent = timestampText;
        }
      } else if (timestampElement) {
        timestampElement.remove();
      }

      if (titleElement.textContent !== nextBaseLabel) {
        titleElement.textContent = nextBaseLabel;
      }
      for (const timestampSpan of Array.from(row.querySelectorAll(LEGACY_TIMESTAMP_SUFFIX_SELECTOR))) {
        timestampSpan.remove();
      }
      return;
    }

    if (currentLabel === nextLabel && !legacyTimestampSpan) return;

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

  function getSidebarRowTimestampMs(row, sortKey) {
    if (sortKey === 'projects') {
      // The Projects list also contains the threads displayed inside each
      // expanded project. Use the project activity timestamp for project rows
      // and the thread timestamp for those nested thread rows.
      return getProjectIdForRow(row)
        ? getProjectTimestampMsForRow(row)
        : getThreadTimestampMsForRow(row);
    }
    return getThreadTimestampMsForRow(row);
  }

  function getSidebarRowSortLabel(row) {
    return normalizeText(
      getThreadBaseLabel(row)
      || getProjectLabelForRow(row)
      || textOf(row)
    );
  }

  function sortSidebarRows(sectionList, rows, sortKey) {
    rows.sort((left, right) => {
      const rightTimestamp = Number(getSidebarRowTimestampMs(right, sortKey) || 0);
      const leftTimestamp = Number(getSidebarRowTimestampMs(left, sortKey) || 0);
      if (rightTimestamp !== leftTimestamp) {
        return rightTimestamp - leftTimestamp;
      }

      const labelOrder = getSidebarRowSortLabel(left).localeCompare(getSidebarRowSortLabel(right));
      if (labelOrder !== 0) return labelOrder;

      const leftId = getProjectIdForRow(left) || getThreadIdForRow(left) || '';
      const rightId = getProjectIdForRow(right) || getThreadIdForRow(right) || '';
      return String(leftId).localeCompare(String(rightId));
    });

    const pager = Array.from(sectionList?.children || [])
      .find((child) => child.hasAttribute(PAGER_ATTR)) || null;
    const currentRows = getSidebarRows(sectionList);
    const sameOrder = currentRows.length === rows.length && currentRows.every((row, index) => row === rows[index]);
    if (!sameOrder && sectionList) {
      for (const row of rows) {
        sectionList.insertBefore(row, pager);
      }
    }

    return rows;
  }

  function sortUnmanagedSidebarLists() {
    for (const list of Array.from(document.querySelectorAll('[role="list"]'))) {
      if (list.hasAttribute(SYNTHETIC_LIST_ATTR)) continue;

      const rows = getSidebarRows(list);
      if (rows.length === 0) continue;

      const hasProjectRows = rows.some((row) => Boolean(getProjectIdForRow(row)));
      const hasThreadRows = rows.some((row) => Boolean(getThreadIdForRow(row)));
      if (!hasProjectRows && !hasThreadRows) continue;

      if (hasProjectRows) suppressProjectHoverCards(rows);

      sortSidebarRows(list, rows, hasProjectRows ? 'projects' : 'threads');
    }
  }

  function suppressProjectHoverCards(rows) {
    for (const row of rows || []) {
      if (!getProjectIdForRow(row)) continue;
      for (const hoverCard of Array.from(row.querySelectorAll('[data-hover-card-open-immediately]'))) {
        hoverCard.removeAttribute('data-hover-card-open-immediately');
      }
      // Codex can mount the card before the next refresh; hide that local
      // card visually without deleting React-owned DOM.
      for (const card of Array.from(row.querySelectorAll('[role="tooltip"], [data-radix-popper-content-wrapper]'))) {
        card.style.setProperty('display', 'none', 'important');
      }
    }
    for (const card of Array.from(document.querySelectorAll('[role="tooltip"]'))) {
      if (card.querySelector('[class*="project-hover-card-row"]')) {
        card.style.setProperty('display', 'none', 'important');
      }
    }
  }

  function installProjectHoverGuard() {
    if (window.__CODEX_PLUS_PROJECT_HOVER_GUARD) return;
    const style = document.createElement('style');
    style.id = 'codex-plus-project-hover-suppression';
    style.textContent = [
      '[role="tooltip"]:has([class*="project-hover-card-row"]),',
      '[data-radix-popper-content-wrapper]:has([class*="project-hover-card-row"]) { display: none !important; }',
      '[data-app-action-sidebar-project-row]:hover { background-color: transparent !important; }'
    ].join('\n');
    (document.head || document.documentElement).appendChild(style);
    window.__CODEX_PLUS_PROJECT_HOVER_GUARD = true;
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

    // Recents is the live, already-sorted activity feed. Prefer its newest
    // project thread because project row ids and working-directory paths are
    // not always represented consistently across local and cloud projects.
    for (const entry of getRecentThreadEntries()) {
      if (entry?.kind !== 'project' || entry.lastModifiedMs <= 0) continue;
      updateProjectTimestamp(normalizeProjectId(entry.projectId), entry.lastModifiedMs);
      updateProjectTimestamp(normalizeProjectId(entry.cwd), entry.lastModifiedMs);
    }

    for (const group of catalog.projectGroups) {
      const projectId = normalizeProjectId(group?.projectId || group?.path);
      if (!projectId) continue;

      const environment = group?.cloudEnvironment;
      updateProjectTimestamp(projectId, Math.max(
        toTimestampMs(environment?.updated_at),
        toTimestampMs(environment?.modified_at),
        toTimestampMs(environment?.created_at)
      ));
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

  function getRecentProjectTimestampByTitle() {
    const map = new Map();

    const addRelativeTimestamp = (title, amount, unit) => {
      const normalizedTitle = normalizeText(title).toLowerCase();
      if (!normalizedTitle) return;
      const unitMs = unit.toLowerCase() === 'm'
        ? 60000
        : (unit.toLowerCase() === 'h' ? 3600000 : 86400000);
      const timestampMs = Math.max(0, Date.now() - Number(amount || 0) * unitMs);
      map.set(normalizedTitle, Math.max(Number(map.get(normalizedTitle) || 0), timestampMs));
    };

    for (const list of getSidebarSectionLists(document, (label) => label === 'Recents')) {
      for (const row of getSidebarRows(list)) {
        const rowText = textOf(row);
        const projectMatch = rowText.match(/\(([^()]+)\)\s*\[(\d+)\s*(m|h|d)\]\s*$/i);
        if (projectMatch) {
          addRelativeTimestamp(projectMatch[1], projectMatch[2], projectMatch[3]);
        }
      }
    }

    for (const entry of getRecentThreadEntries()) {
      if (entry?.kind !== 'project' || entry.lastModifiedMs <= 0) continue;
      const title = normalizeText(entry.projectTitle).toLowerCase();
      if (!title) continue;
      const current = Number(map.get(title) || 0);
      if (entry.lastModifiedMs > current) map.set(title, entry.lastModifiedMs);
    }
    return map;
  }

  function getProjectTimestampMsForRow(row) {
    const explicit = Number(row?.getAttribute(THREAD_UPDATED_ATTR) || '0');
    const projectId = normalizeProjectId(getProjectIdForRow(row));
    let liveTimestamp = 0;
    if (projectId) {
      liveTimestamp = Number(getProjectTimestampMap().get(projectId) || 0);
    }
    const projectTitle = normalizeText(getProjectLabelForRow(row)).toLowerCase();
    const recentTitleTimestamp = projectTitle
      ? Number(getRecentProjectTimestampByTitle().get(projectTitle) || 0)
      : 0;

    if (recentTitleTimestamp > 0) return recentTitleTimestamp;

    return Math.max(
      explicit,
      liveTimestamp,
      getRemoteProjectTimestampMsForRow(row),
      getDisplayedModifiedTimestampMs(row)
    );
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
      return minimum;
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

  function isUnreadSyntheticThreadRow(row) {
    return Boolean(
      row?.hasAttribute(SYNTHETIC_ROW_ATTR)
      && row.querySelector('[' + THREAD_UNREAD_INDICATOR_ATTR + ']')
    );
  }

  function clearPagers(root) {
    for (const pager of Array.from(root.querySelectorAll('[' + PAGER_ATTR + ']'))) {
      pager.remove();
    }
  }

  function bindSingleActivation(button, handler) {
    if (!button) return;

    const pointerActivationKey = '__codexPlusLastPointerActivationAt';
    button.onclick = (event) => {
      const lastPointerActivationAt = Number(button[pointerActivationKey] || 0);
      button[pointerActivationKey] = 0;
      if (lastPointerActivationAt > 0 && performance.now() - lastPointerActivationAt < 500) {
        return;
      }
      handler(event);
    };
    button.onpointerup = (event) => {
      button[pointerActivationKey] = performance.now();
      handler(event);
    };
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

  function updateProjectThreadTimestamps() {
    const entries = getRecentThreadEntries();
    const byTitle = new Map(entries.map((entry) => [normalizeText(entry.title).toLowerCase(), entry]));

    const bySource = new Map();
    for (const entry of entries) {
      const sourceList = normalizeText(entry.sourceListLabel);
      const sourceText = normalizeText(entry.sourceRowText || entry.title);
      if (!sourceList || !sourceText) continue;
      bySource.set(sourceList + '\u0000' + sourceText, entry);
    }

    for (const list of getSidebarSectionLists(document, (label) => label.startsWith('Scheduled tasks in '))) {
      const sourceList = normalizeText(list.getAttribute('aria-label'));
      for (const row of getSidebarRows(list)) {
        const sourceText = normalizeText(getThreadBaseLabel(row) || textOf(row));
        const entry = bySource.get(sourceList + '\u0000' + sourceText)
          || byTitle.get(sourceText.toLowerCase());
        if (!entry) continue;
        setThreadLabel(row, sourceText, sourceText, entry.lastModifiedMs);
        positionNativeThreadStatusSlot(row);
      }
    }
  }

  function updateAllProjectTimestamps() {
    for (const row of Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))) {
      const timestampMs = getProjectTimestampMsForRow(row);
      if (timestampMs <= 0) continue;
      const baseLabel = getProjectLabelForRow(row) || getThreadBaseLabel(row);
      if (!baseLabel) continue;
      setThreadLabel(row, baseLabel, baseLabel, timestampMs);
    }
  }

  function removeSyntheticThreadActions(row) {
    if (!row) return;

    const actionContainers = new Set();
    for (const button of Array.from(row.querySelectorAll('button[aria-label]'))) {
      const label = normalizeText(button.getAttribute('aria-label')).toLowerCase();
      if (!label.includes('pin') && !label.includes('archive')) continue;

      const container = button.parentElement?.parentElement;
      if (container?.tagName === 'DIV') {
        actionContainers.add(container);
      } else {
        button.remove();
      }
    }

    for (const container of actionContainers) {
      container.remove();
    }

    const actionLayout = Array.from(row.querySelectorAll('div')).filter((element) => {
      const className = String(element.className || '');
      return className.includes('group-hover:min-w-12')
        || className.includes('group-has-[:focus-visible]:min-w-12');
    });
    for (const element of actionLayout) {
      const trailingSpacer = element.nextElementSibling;
      element.remove();
      if (trailingSpacer && String(trailingSpacer.className || '').includes('group-hover:hidden')) {
        trailingSpacer.remove();
      }
    }
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

    const unreadIndicator = getThreadUnreadIndicator(row);
    if (unreadIndicator) unreadIndicator.remove();
    removeSyntheticThreadActions(row);
  }

  function applySyntheticThreadIndent(row) {
    const button = row?.querySelector('[role="button"]');
    if (!button) return;

    // Recents is rendered outside the project tree. Keep its thread labels
    // aligned with the nested project-thread labels by adding the same 24px
    // leading inset to the interactive row.
    button.classList.add('pl-6');
  }

  function createSyntheticThreadRow(label, updatedMs, templateRow) {
    if (templateRow) {
      const row = templateRow.cloneNode(true);
      sanitizeSyntheticThreadTemplate(row);
      applySyntheticThreadIndent(row);
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
    button.classList.add('pl-6');

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

    const nativeRowsByThreadId = new Map();
    const catalog = getLiveSidebarCatalog();
    for (const nativeRow of getNativeThreadRows()) {
      const threadId = normalizeThreadId(getThreadIdForRow(nativeRow));
      if (threadId) nativeRowsByThreadId.set(threadId, nativeRow);
    }

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
      removeSyntheticThreadActions(row);
      syncThreadUnreadIndicator(
        row,
        nativeRowsByThreadId.get(threadId) || null,
        getLiveThreadRecordById(catalog, threadId)
      );
      positionNativeThreadStatusSlot(row);
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
    const nativePinnedThreadIds = getNativePinnedThreadIds();
    const projectGroupByThreadId = new Map();
    for (const group of catalog.projectGroups || []) {
      for (const threadKey of Array.isArray(group?.threadKeys) ? group.threadKeys : []) {
        const threadId = normalizeThreadId(threadKey);
        if (threadId && !projectGroupByThreadId.has(threadId)) {
          projectGroupByThreadId.set(threadId, group);
        }
      }
    }
    const entriesByThreadId = new Map();

    for (const threadKey of catalog.threadKeys) {
      const record = catalog.records.get(threadKey);
      if (!record) continue;

      const cwd = normalizeProjectId(record.cwd);
      const id = normalizeThreadId(record.id);
      const projectGroup = projectGroupByThreadId.get(id) || getProjectGroupForThreadKey(catalog, threadKey);
      const projectTitle = getProjectTitleFromGroup(projectGroup) || projectTitleMap.get(cwd) || '';
      const kind = projectGroup || projectTitle ? 'project' : 'task';
      const isPinned = nativePinnedThreadIds.has(id);
      if (isPinned) continue;
      const liveTitle = normalizeText(record.title);
      const nativeTitle = nativeThreadTitleMap.get(id) || '';
      const attentionState = catalog.state?.threadAttentionStateByKey?.get?.(threadKey);
      const isUnread = attentionState === 'unread'
        || (attentionState === undefined && Boolean(
          record.hasUnreadTurn || Number(record.unreadCount || 0) > 0
        ));
      // Codex can keep the native project/task row at its placeholder title
      // while the opened conversation is already renamed. During that brief
      // running state the live catalog is the source of truth; once the run
      // settles, keep preferring the native rendered title as it catches up.
      const resolvedTitle = liveTitle && (
        isWorkingThreadStatus(record.threadRuntimeStatus)
        || !nativeTitle
        || isPlaceholderThreadTitle(nativeTitle)
      )
        ? liveTitle
        : nativeTitle;
      // Unloaded project threads can carry authoritative unread state before
      // Codex mounts their native title. Keep them visible immediately; the
      // native title cache replaces this fallback as soon as the row mounts.
      const title = resolvedTitle || (isUnread ? 'Unread thread' : '');
      const lastModifiedMs = getLiveThreadTimestampMs(record, catalog);
      if (!id || !title || !cwd || lastModifiedMs <= 0) continue;
      if (
        projectWindowContext
        && (
          kind !== 'project'
          || normalizeProjectId(projectGroup?.projectId || cwd) !== normalizeProjectId(projectWindowContext.id)
        )
      ) continue;

      const entry = {
        id,
        title,
        displayTitle: title,
        cwd,
        projectTitle,
        projectId: normalizeText(projectGroup?.projectId),
        kind,
        lastModifiedMs,
        sourceListLabel: kind === 'project' ? ('Scheduled tasks in ' + projectTitle) : 'Tasks',
        sourceRowText: title
      };
      const existing = entriesByThreadId.get(id);
      if (
        !existing
        || (kind === 'project' && existing.kind === 'task')
        || (kind === existing.kind && lastModifiedMs > existing.lastModifiedMs)
      ) {
        entriesByThreadId.set(id, entry);
      }
    }

    return Array.from(entriesByThreadId.values())
      .sort((left, right) => right.lastModifiedMs - left.lastModifiedMs);
  }

  function ensureSyntheticThreadsSection() {
    const projectsHeading = getSidebarSectionTitle(document, 'Projects');
    const projectsShell = getSectionShellFromTitle(projectsHeading);

    if (!projectsShell || !projectsHeading) {
      removeSyntheticSection('threads');
      return null;
    }

    const recentThreadEntries = getRecentThreadEntries();
    if (recentThreadEntries.length === 0 && !projectWindowContext) {
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
      wireSyntheticThreadRow(clone, entry.sourceListLabel || 'Tasks', entry.sourceRowText || entry.title, entry.projectId);
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
    const threadsHeadingLabel = projectWindowContext
      ? projectWindowContext.name + ' threads'
      : 'Recents';

    if (!header || !sectionContainer || !listElement) {
      shell.innerHTML = '';

      header = projectsHeading.cloneNode(true);
      header.setAttribute(THREADS_HEADER_ATTR, 'threads');
      const headerButton = header.querySelector('button[data-app-action-sidebar-section-toggle]') || header.querySelector('button');
      if (headerButton) {
        // Keep the project-style section toggle signature (`group/section-toggle`) in the payload.
        syncThreadToggleButton(headerButton, false, threadsHeadingLabel);
      }
      while (header.children.length > 1) {
        header.lastElementChild.remove();
      }
      if (headerButton) {
        syncThreadToggleButton(headerButton, false, threadsHeadingLabel);
      }

      shell.appendChild(header);

      sectionContainer = document.createElement('div');
      sectionContainer.setAttribute(THREADS_CONTAINER_ATTR, 'threads');
      const scroller = document.createElement('div');
      listElement = document.createElement('div');
      listElement.setAttribute('role', 'list');
      listElement.setAttribute('aria-label', 'Recents');
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
      syncThreadToggleButton(collapseButton, collapsed, projectWindowContext ? projectWindowContext.name + ' threads' : 'Recents');
      bindSingleActivation(collapseButton, (event) => {
        const nextCollapsed = !sectionContainer.hidden;
        sectionContainer.hidden = nextCollapsed;
        shell.setAttribute(COLLAPSED_ATTR, nextCollapsed ? 'true' : 'false');
        syncThreadToggleButton(collapseButton, nextCollapsed, projectWindowContext ? projectWindowContext.name + ' threads' : 'Recents');
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      });
    }

    if (!projectWindowContext) {
      const visibleHeaderLabel = shell.querySelector('[' + THREADS_HEADER_ATTR + '] button span');
      if (visibleHeaderLabel) visibleHeaderLabel.textContent = 'Recents';
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

    sortSidebarRows(sectionList, rows, sectionKey === 'projects' ? 'projects' : 'threads');

    for (const row of rows) {
      const timestampMs = getSidebarRowTimestampMs(row, sectionKey === 'projects' ? 'projects' : 'threads');
      const nextLabel = formatThreadLabel(row, sectionKey, null, timestampMs);
      const baseLabel = nextLabel;
      setThreadLabel(row, nextLabel, baseLabel, timestampMs);
    }

    // Timestamp labels are normalized above; sort again so rows with a
    // timestamp that was only available from rendered/native markup are also
    // placed correctly in the Projects list.
    if (sectionKey === 'projects') {
      sortSidebarRows(sectionList, rows, 'projects');
    }

    let orderedRows = rows;
    let effectiveVisibleCount = visibleCount;
    if (sectionKey === 'threads' && sectionList.hasAttribute(SYNTHETIC_LIST_ATTR)) {
      const initialVisibleRows = rows.slice(0, visibleCount);
      const initiallyHiddenRows = rows.slice(visibleCount);
      const unreadRows = initiallyHiddenRows.filter(isUnreadSyntheticThreadRow);
      if (unreadRows.length > 0) {
        const remainingHiddenRows = initiallyHiddenRows.filter((row) => !isUnreadSyntheticThreadRow(row));
        orderedRows = [...initialVisibleRows, ...unreadRows, ...remainingHiddenRows];
        effectiveVisibleCount = initialVisibleRows.length + unreadRows.length;

        const existingPager = sectionList.querySelector('[' + PAGER_ATTR + '="' + sectionKey + '"]');
        for (const row of orderedRows) {
          sectionList.insertBefore(row, existingPager);
        }
      }
    }

    const visibleRows = orderedRows.slice(0, effectiveVisibleCount);
    const hiddenRows = orderedRows.slice(effectiveVisibleCount);
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
    const wasObserving = observing;
    if (wasObserving) disconnect();
    try {
      installNativeThreadStatusSlotStyle();
      if (projectWindowContext) {
        document.documentElement?.setAttribute(PROJECT_WINDOW_MARKER, projectWindowContext.id);
        document.title = 'Codex Plus Project: ' + projectWindowContext.name;
      }
      for (const spec of SECTION_SPECS) {
        if (projectWindowContext && spec.key === 'projects') {
          const projectList = resolveSidebarSectionList(spec);
          const projectHeading = getSidebarSectionTitle(document, 'Projects');
          const projectShell = projectHeading?.parentElement || projectList?.parentElement;
          if (projectShell) projectShell.hidden = true;
          continue;
        }
        const list = spec.synthetic ? ensureSyntheticThreadsSection() : resolveSidebarSectionList(spec);
        if (!list) continue;

        const rows = getSidebarRows(list);
        const visibleCount = Math.min(rows.length, getVisibleCount(rows, spec));
        writeLoaded(list, Math.max(0, Math.min(readLoaded(list), Math.max(0, rows.length - visibleCount))));
        renderSidebarSection(list, visibleCount, spec.key);
        if (spec.key === 'projects') suppressProjectHoverCards(getSidebarRows(list));
      }
      updateAllProjectTimestamps();
      updateProjectThreadTimestamps();
      sortUnmanagedSidebarLists();
      syncSyntheticThreadActiveState();
    } finally {
      if (wasObserving) observe();
    }
  }

  let pending = false;
  let applying = false;
  let scheduleTimer = 0;
  let observing = false;
  let observingRoot = null;
  const observe = () => {
    const root = getSidebarObserverRoot() || document.documentElement;
    if (!root || (observing && observingRoot === root)) return;
    if (observing) {
      observer.disconnect();
    }
    observer.observe(root, {
      childList: true,
      subtree: true
    });
    observing = true;
    observingRoot = root;
  };
  const disconnect = () => {
    if (!observing) return;
    observer.disconnect();
    observing = false;
    observingRoot = null;
  };
  const runScheduledApply = () => {
    scheduleTimer = 0;
    if (threadNavigationState) {
      scheduleTimer = window.setTimeout(runScheduledApply, SIDEBAR_NAVIGATION_REFRESH_RETRY_MS);
      return;
    }

    pending = false;
    applying = true;
    try {
      apply();
    } finally {
      applying = false;
    }
  };
  const schedule = () => {
    if (pending || applying) return;
    pending = true;
    scheduleTimer = window.setTimeout(runScheduledApply, SIDEBAR_REFRESH_DEBOUNCE_MS);
  };
  requestSidebarRefresh = schedule;

  window.setInterval(schedule, SIDEBAR_POLL_INTERVAL_MS);
  window.setInterval(tryClaimPendingProjectWindowContext, 250);

  const observer = new MutationObserver(schedule);
  const start = () => {
    disconnect();
    installProjectHoverGuard();
    try {
      applying = true;
      apply();
    } finally {
      applying = false;
      observe();
    }
    window.setTimeout(warmStartupThreadNavigation, 0);
  };

  window.__CODEX_PLUS_SIDEBAR_PAGING = {
    apply,
    observer
  };

  startThreadNavigationLoadingMonitor();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
'@
}
