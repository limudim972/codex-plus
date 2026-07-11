function Get-CodexSidebarPagingPayload {
    $projectOrderSnapshot = @(Get-CodexProjectOrderSnapshot)
    $projectOrderJson = @($projectOrderSnapshot | Select-Object -ExpandProperty cwd) | ConvertTo-Json -Compress
    @'
(function () {
  const SECTION_SELECTOR = '[class*="group/nav-section-title"]';
  const PAGE_SIZE = 5;
  const PAGER_ATTR = 'data-codex-plus-sidebar-pager';
  const ACTION_ATTR = 'data-codex-plus-sidebar-action';
  const STATE_ATTR = 'data-codex-plus-sidebar-loaded';
  const ORDER_ATTR = 'data-codex-plus-project-order';
  const BUTTON_CLASS = 'border-token-border no-drag cursor-interaction flex items-center gap-1 border whitespace-nowrap select-none focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 rounded-full text-token-muted-foreground enabled:hover:bg-transparent data-[state=open]:bg-transparent hover:text-token-foreground border-transparent px-2 py-0.5 text-sm leading-[18px] text-token-description-foreground hover:text-token-foreground -ml-[9px]';
  const PROJECT_ORDER = __CODEX_PLUS_PROJECT_ORDER__;

  const SECTION_SPECS = [
    { key: 'projects', title: 'Projects', visibleCount: 3 },
    { key: 'tasks', labels: ['Tasks', 'Chats'], visibleCount: 2 }
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

    const orderMap = new Map(PROJECT_ORDER.map((id, index) => [normalizeProjectId(id), index]));
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
      button.setAttribute(ACTION_ATTR, 'toggle');
      wrapper.appendChild(button);

      pager.appendChild(wrapper);
    }

    if (pager) {
      const toggleButton = pager.querySelector('[' + ACTION_ATTR + '="toggle"]');
      toggleButton.onclick = (event) => {
        const current = readLoaded(sectionList);
        const next = current > 0 ? 0 : Math.min(hiddenRows.length, PAGE_SIZE);
        writeLoaded(sectionList, next);
        renderSidebarSection(sectionList, visibleCount, sectionKey);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      };
      toggleButton.onpointerup = toggleButton.onclick;

      const hasAny = loaded > 0;
      const hasMore = loaded < hiddenRows.length;
      toggleButton.textContent = hasAny ? 'Show less' : 'Show more';
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
      const list = resolveSidebarSectionList(spec);
      if (!list) continue;

      clearPagers(list);
      sortProjectRows(list, spec.key);
      writeLoaded(list, Math.max(0, Math.min(readLoaded(list), Math.max(0, getSidebarRows(list).length - spec.visibleCount))));
      renderSidebarSection(list, spec.visibleCount, spec.key);
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
'@.Replace('__CODEX_PLUS_PROJECT_ORDER__', $projectOrderJson)
}
