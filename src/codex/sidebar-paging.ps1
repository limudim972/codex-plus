function Get-CodexSidebarPagingPayload {
    $projectOrderSnapshot = @(Get-CodexProjectOrderSnapshot)
    $projectOrderJson = @($projectOrderSnapshot) | ConvertTo-Json -Compress
    $recentThreadSnapshot = @(Get-CodexRecentThreadSnapshot)
    $recentThreadJson = @($recentThreadSnapshot) | ConvertTo-Json -Compress
    @'
(function () {
  const SECTION_SELECTOR = '[class*="group/nav-section-title"]';
  const PAGE_SIZE = 3;
  const RECENT_WINDOW_MS = 24 * 60 * 60 * 1000;
  const SYNTHETIC_SECTION_ATTR = 'data-codex-plus-sidebar-synthetic-section';
  const SYNTHETIC_LIST_ATTR = 'data-codex-plus-sidebar-synthetic-list';
  const SYNTHETIC_ROW_ATTR = 'data-codex-plus-sidebar-synthetic-row';
  const SOURCE_LIST_ATTR = 'data-codex-plus-source-list-label';
  const SOURCE_TEXT_ATTR = 'data-codex-plus-source-row-text';
  const PAGER_ATTR = 'data-codex-plus-sidebar-pager';
  const ACTION_ATTR = 'data-codex-plus-sidebar-action';
  const STATE_ATTR = 'data-codex-plus-sidebar-loaded';
  const ORDER_ATTR = 'data-codex-plus-project-order';
  const THREAD_UPDATED_ATTR = 'data-codex-plus-thread-updated-ms';
  const BUTTON_CLASS = 'border-token-border no-drag cursor-interaction flex items-center gap-1 border whitespace-nowrap select-none focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 rounded-full text-token-muted-foreground enabled:hover:bg-transparent data-[state=open]:bg-transparent hover:text-token-foreground border-transparent px-2 py-0.5 text-sm leading-[18px] text-token-description-foreground hover:text-token-foreground -ml-[9px]';
  const PROJECT_ORDER = __CODEX_PLUS_PROJECT_ORDER__;
  const RECENT_THREADS = __CODEX_PLUS_RECENT_THREADS__;

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
    return String(value || '').trim().toLowerCase();
  }

  function getProjectIdForRow(row) {
    if (!row) return '';
    const direct = row.getAttribute('data-app-action-sidebar-project-id');
    if (direct) return direct;
    const nested = row.querySelector('[data-app-action-sidebar-project-id]');
    return nested ? nested.getAttribute('data-app-action-sidebar-project-id') : '';
  }

  function sortProjectRows(sectionList, sectionKey) {
    if (sectionKey !== 'projects' || !Array.isArray(PROJECT_ORDER) || PROJECT_ORDER.length === 0) {
      return;
    }

    const orderMap = new Map(PROJECT_ORDER.map((entry, index) => [normalizeProjectId(entry?.cwd), index]));
    const rows = getSidebarRows(sectionList).map((row, index) => ({
      row,
      index,
      rank: orderMap.has(normalizeProjectId(getProjectIdForRow(row)))
        ? orderMap.get(normalizeProjectId(getProjectIdForRow(row)))
        : Number.MAX_SAFE_INTEGER
    }));

    rows.sort((left, right) => {
      if (left.rank !== right.rank) return left.rank - right.rank;
      return left.index - right.index;
    });

    const signature = rows.map((entry) => normalizeProjectId(getProjectIdForRow(entry.row)) || ('index:' + entry.index)).join('|');
    if (sectionList.getAttribute(ORDER_ATTR) === signature) {
      return;
    }

    for (const entry of rows) {
      sectionList.appendChild(entry.row);
    }

    sectionList.setAttribute(ORDER_ATTR, signature);
  }

  function getThreadIdForRow(row) {
    if (!row) return '';
    const direct = row.getAttribute('data-app-action-sidebar-thread-id');
    if (direct) return direct;
    const nested = row.querySelector('[data-app-action-sidebar-thread-id]');
    return nested ? nested.getAttribute('data-app-action-sidebar-thread-id') : '';
  }

  function getThreadTitleElement(row) {
    return row?.querySelector('[data-thread-title="true"], [data-app-action-sidebar-thread-title], [data-app-action-sidebar-project-label]') || null;
  }

  function getRowTextSignature(row) {
    return normalizeText(row?.innerText || '');
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

    return getSidebarRows(list).find((row) => getRowTextSignature(row) === normalizedRowText) || null;
  }

  function findRowByThreadId(threadId) {
    const normalizedThreadId = normalizeThreadId(threadId);
    if (!normalizedThreadId) return null;

    return getSidebarSectionLists(document, () => true)
      .flatMap((list) => getSidebarRows(list))
      .find((row) => normalizeThreadId(getThreadIdForRow(row)) === normalizedThreadId) || null;
  }

  function wireSyntheticThreadRow(row, sourceListLabel, sourceRowText) {
    if (!row) return;
    row.setAttribute(SOURCE_LIST_ATTR, sourceListLabel);
    row.setAttribute(SOURCE_TEXT_ATTR, sourceRowText);

    const invokeSourceRow = (event) => {
      const sourceRow = findRowByThreadId(row.getAttribute('data-codex-plus-thread-id'));
      if (!sourceRow) return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      dispatchRowClick(sourceRow);
    };

    row.addEventListener('click', invokeSourceRow, true);
    row.addEventListener('pointerup', invokeSourceRow, true);
  }

  function getThreadTitleForRow(row) {
    return textOf(getThreadTitleElement(row)) || textOf(row);
  }

  function getProjectLabelForRow(row) {
    const explicitLabel = row?.querySelector('[data-app-action-sidebar-project-label]');
    const explicitText = textOf(explicitLabel);
    if (explicitText) return explicitText;

    const projectId = getProjectIdForRow(row);
    if (!projectId) return '';
    const normalized = String(projectId).replace(/\\+/g, '/').replace(/\/+$/g, '');
    const parts = normalized.split('/').filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : normalized;
  }

  function formatThreadLabel(row, kind, projectTitle) {
    const title = getThreadTitleForRow(row);
    if (!title) return '';
    if (kind === 'project') {
      const projectLabel = projectTitle || getProjectLabelForRow(row);
      return projectLabel ? (title + ' (' + projectLabel + ')') : title;
    }
    return /\s+\([^)]+\)$/.test(title) ? title : (title + ' (task)');
  }

  function formatThreadLabelFromSnapshot(entry) {
    const title = normalizeText(entry?.display_title || entry?.title);
    if (!title) return '';
    return title;
  }

  function setThreadLabel(row, label) {
    if (!row || !label) return;
    const titleElement = getThreadTitleElement(row);
    if (titleElement) {
      titleElement.textContent = label;
      return;
    }
    const fallbackLabel = row.querySelector('[aria-label]') || row.firstElementChild || row;
    fallbackLabel.textContent = label;
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

    if (spec.key === 'projects') {
      const projectTimes = new Map((Array.isArray(PROJECT_ORDER) ? PROJECT_ORDER : []).map((entry) => [
        normalizeProjectId(entry?.cwd),
        Number(entry?.last_modified_ms || 0)
      ]));
      return Math.max(minimum, countRecentRows(rows, (row) => projectTimes.get(normalizeProjectId(getProjectIdForRow(row)))));
    }

    if (spec.key === 'tasks') {
      return Math.max(minimum, countRecentRows(rows, (row) => getThreadTimestampMsForRow(row)));
    }

    return minimum;
  }

  function readLoaded(list) {
    return Number(list.getAttribute(STATE_ATTR) || '0');
  }

  function writeLoaded(list, value) {
    list.setAttribute(STATE_ATTR, String(value));
  }

  function setVisible(row, visible) {
    row.hidden = !visible;
    row.setAttribute('aria-hidden', visible ? 'false' : 'true');
    row.style.setProperty('display', visible ? '' : 'none', 'important');
    row.style.setProperty('visibility', visible ? '' : 'hidden', 'important');
    row.style.setProperty('pointer-events', visible ? '' : 'none', 'important');
  }

  function clearPagers(root) {
    for (const pager of Array.from(root.querySelectorAll('[' + PAGER_ATTR + ']'))) {
      pager.remove();
    }
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
      const projectTitle = getProjectLabelForRow(row) || textOf(row);
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

  function createSyntheticThreadRow(label, updatedMs, templateRow) {
    if (templateRow) {
      const row = templateRow.cloneNode(true);
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
      setThreadLabel(row, label);
      return row;
    }

    const row = document.createElement('div');
    row.setAttribute('role', 'listitem');
    row.setAttribute(SYNTHETIC_ROW_ATTR, 'threads');
    row.setAttribute(THREAD_UPDATED_ATTR, String(updatedMs || 0));
    row.className = 'after:block after:h-px after:content-[\'\'] last:after:hidden';

    const button = document.createElement('div');
    button.setAttribute('role', 'button');
    button.className = 'group relative h-[var(--height-token-row)] rounded-[var(--radius-token-row)] py-row-y text-sm pr-1 pl-[var(--padding-row-cell-x,var(--padding-row-x))]';

    const outer = document.createElement('div');
    outer.className = 'flex h-full w-full items-center text-sm leading-4';

    const inner = document.createElement('div');
    inner.className = 'flex min-w-0 flex-1 self-stretch items-center gap-2 text-base leading-5 text-token-foreground';

    const title = document.createElement('span');
    title.setAttribute('data-thread-title', 'true');
    title.className = 'min-w-0 select-none text-fade-truncate flex-1';
    title.textContent = label;

    inner.appendChild(title);
    outer.appendChild(inner);
    button.appendChild(outer);
    row.appendChild(button);
    return row;
  }

  function getRecentThreadEntries() {
    const projectTitleMap = getProjectTitleMap();
    const seen = new Set();

    return (Array.isArray(RECENT_THREADS) ? RECENT_THREADS : []).map((entry) => {
      const cwd = normalizeProjectId(entry?.cwd);
      const projectTitle = projectTitleMap.get(cwd) || '';
      const kind = projectTitle ? 'project' : 'task';
      const title = normalizeText(entry?.display_title || entry?.title);
      const lastModifiedMs = Number(entry?.last_modified_ms || 0);
      const id = normalizeThreadId(entry?.id);
      return {
        id,
        title,
        displayTitle: title,
        cwd,
        projectTitle,
        kind,
        lastModifiedMs,
        sourceListLabel: kind === 'project' ? ('Scheduled tasks in ' + projectTitle) : 'Tasks',
        sourceRowText: title
      };
    }).filter((entry) => {
      if (!entry.title || entry.lastModifiedMs <= 0) return false;
      const signature = [entry.id || '', entry.cwd || '', entry.title, entry.kind].join('|').toLowerCase();
      if (seen.has(signature)) return false;
      seen.add(signature);
      return true;
    }).sort((left, right) => right.lastModifiedMs - left.lastModifiedMs);
  }

  function ensureSyntheticThreadsSection() {
    const projectsHeading = getSidebarSectionTitle(document, 'Projects');
    const projectsShell = getSectionShellFromTitle(projectsHeading);

    if (!projectsShell) {
      removeSyntheticSection('threads');
      return null;
    }

    const recentThreadEntries = getRecentThreadEntries();
    const templateRow = getSyntheticThreadTemplateRow();
    const seen = new Set();
    const threadRows = [];
    for (const entry of recentThreadEntries) {
      const signature = [entry.id || '', entry.cwd || '', entry.title, entry.kind].join('|').toLowerCase();
      if (seen.has(signature)) continue;
      seen.add(signature);
      const clone = createSyntheticThreadRow(formatThreadLabelFromSnapshot(entry), entry.lastModifiedMs, templateRow);
      clone.setAttribute('data-codex-plus-thread-id', entry.id);
      clone.setAttribute(SYNTHETIC_ROW_ATTR, 'threads');
      clone.setAttribute(THREAD_UPDATED_ATTR, String(entry.lastModifiedMs));
      setThreadLabel(clone, formatThreadLabelFromSnapshot(entry));
      wireSyntheticThreadRow(clone, entry.sourceListLabel || 'Tasks', entry.displayTitle || entry.title);
      threadRows.push({
        row: clone,
        timestampMs: entry.lastModifiedMs
      });
    }

    threadRows.sort((left, right) => right.timestampMs - left.timestampMs);

    let shell = document.querySelector('[' + SYNTHETIC_SECTION_ATTR + '="threads"]');
    if (!shell) {
      shell = document.createElement('div');
      shell.setAttribute(SYNTHETIC_SECTION_ATTR, 'threads');

      const title = document.createElement('div');
      title.className = projectsHeading.className;
      title.textContent = 'Threads';
      shell.appendChild(title);

      const sectionContainer = document.createElement('div');
      const scroller = document.createElement('div');
      const list = document.createElement('div');
      list.setAttribute('role', 'list');
      list.setAttribute('aria-label', 'Threads');
      list.setAttribute(SYNTHETIC_LIST_ATTR, 'threads');
      scroller.appendChild(list);
      sectionContainer.appendChild(scroller);
      shell.appendChild(sectionContainer);
    }

    const list = shell.querySelector('[role="list"]');
    clearPagers(list);
    writeLoaded(list, Math.max(0, readLoaded(list)));
    list.innerHTML = '';
    for (const entry of threadRows) {
      list.appendChild(entry.row);
    }

    if (shell.parentElement !== projectsShell.parentElement || shell.nextSibling !== projectsShell) {
      projectsShell.parentElement.insertBefore(shell, projectsShell);
    }

    return list;
  }

  function renderSidebarSection(sectionList, visibleCount, sectionKey) {
    if (!sectionList) return;

    const rows = getSidebarRows(sectionList);
    if (rows.length === 0) return;

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
      showMoreButton.onclick = (event) => {
        const current = readLoaded(sectionList);
        const next = Math.min(hiddenRows.length, (current > 0 ? current : 0) + PAGE_SIZE);
        writeLoaded(sectionList, next);
        renderSidebarSection(sectionList, visibleCount, sectionKey);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      };
      showMoreButton.onpointerup = showMoreButton.onclick;

      showLessButton.onclick = (event) => {
        writeLoaded(sectionList, 0);
        renderSidebarSection(sectionList, visibleCount, sectionKey);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      };
      showLessButton.onpointerup = showLessButton.onclick;

      const hasAny = loaded > 0;
      const hasMore = loaded < hiddenRows.length;
      showMoreButton.textContent = 'Show more';
      showMoreButton.hidden = !hasMore;
      showLessButton.hidden = !hasAny;
      pager.hidden = !hasMore && !hasAny;
      pager.style.setProperty('display', pager.hidden ? 'none' : 'flex', 'important');

      const beforeNode = hiddenRows[loaded] || null;
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

      clearPagers(list);
      sortProjectRows(list, spec.key);
      const rows = getSidebarRows(list);
      const visibleCount = Math.min(rows.length, getVisibleCount(rows, spec));
      writeLoaded(list, Math.max(0, Math.min(readLoaded(list), Math.max(0, rows.length - visibleCount))));
      renderSidebarSection(list, visibleCount, spec.key);
    }
  }

  let pending = false;
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
    if (pending) return;
    pending = true;
    window.setTimeout(() => {
      pending = false;
      apply();
    }, 50);
  };

  const observer = new MutationObserver(schedule);
  const start = () => {
    disconnect();
    try {
      apply();
    } finally {
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
'@.Replace('__CODEX_PLUS_PROJECT_ORDER__', $projectOrderJson).Replace('__CODEX_PLUS_RECENT_THREADS__', $recentThreadJson)
}
