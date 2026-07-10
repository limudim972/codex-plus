function Get-CodexSidebarPagingPayload {
    @'
(function () {
  const SECTION_SELECTOR = '[class*="group/nav-section-title"]';
  const PAGE_SIZE = 5;
  const PAGER_ATTR = 'data-codex-plus-sidebar-pager';
  const ACTION_ATTR = 'data-codex-plus-sidebar-action';
  const STATE_ATTR = 'data-codex-plus-sidebar-loaded';
  const BUTTON_CLASS = 'border-token-border no-drag cursor-interaction flex items-center gap-1 border whitespace-nowrap select-none focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 rounded-full text-token-muted-foreground enabled:hover:bg-transparent data-[state=open]:bg-transparent hover:text-token-foreground border-transparent px-2 py-0.5 text-sm leading-[18px] text-token-description-foreground hover:text-token-foreground -ml-[9px]';

  const SECTION_SPECS = [
    { title: 'Projects', visibleCount: 3 },
    { title: 'Chats', visibleCount: 2 }
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

  function getSidebarRows(sectionList) {
    return Array.from(sectionList?.children || []).filter((row) => row.getAttribute('role') === 'listitem' && !row.hasAttribute(PAGER_ATTR));
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

  function ensureSidebarPager(sectionList, sectionKey) {
    let pagerRow = sectionList.querySelector('[' + PAGER_ATTR + '="' + sectionKey + '"]');
    if (!pagerRow) {
      pagerRow = sectionList.ownerDocument.createElement('div');
      pagerRow.setAttribute('role', 'listitem');
      pagerRow.setAttribute(PAGER_ATTR, sectionKey);
      pagerRow.className = 'flex gap-1 py-1 pl-2 pr-0 after:block after:h-px after:content-[\'\'] last:after:hidden';

      const wrapper = sectionList.ownerDocument.createElement('div');
      wrapper.className = 'flex items-center gap-2';

      const button = sectionList.ownerDocument.createElement('button');
      button.type = 'button';
      button.className = BUTTON_CLASS;
      button.setAttribute(ACTION_ATTR, 'toggle');
      wrapper.appendChild(button);
      pagerRow.appendChild(wrapper);
    }

    if (pagerRow.dataset.codexPlusSidebarBound !== 'true') {
      pagerRow.dataset.codexPlusSidebarBound = 'true';
      pagerRow.addEventListener('click', (event) => {
        const button = event.target && event.target.closest ? event.target.closest('[' + ACTION_ATTR + ']') : null;
        if (!button) return;

        const action = button.getAttribute(ACTION_ATTR);
        const list = pagerRow.parentElement;
        if (!list) return;

        const rows = getSidebarRows(list);
        const currentLoaded = readLoaded(list);
        const next = action === 'more'
          ? Math.min(rows.length - 1, currentLoaded + PAGE_SIZE || PAGE_SIZE)
          : 0;

        writeLoaded(list, next);
        renderSidebarSection(list, sectionKey);
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      });
    }

    return pagerRow;
  }

  function renderSidebarSection(sectionList, sectionKey) {
    if (!sectionList) return;

    const rows = getSidebarRows(sectionList);
    if (rows.length === 0) return;

    const visibleRows = rows.slice(0, 3);
    const hiddenRows = rows.slice(3);
    const loaded = Math.max(0, Math.min(readLoaded(sectionList), hiddenRows.length));
    const pagerRow = hiddenRows.length > 0 ? ensureSidebarPager(sectionList, sectionKey) : null;

    for (const row of visibleRows) {
      setVisible(row, true);
    }
    for (let index = 0; index < hiddenRows.length; index++) {
      setVisible(hiddenRows[index], index < loaded);
    }

    if (!pagerRow) {
      const existing = sectionList.querySelector('[' + PAGER_ATTR + '="' + sectionKey + '"]');
      if (existing) existing.remove();
      writeLoaded(sectionList, 0);
      return;
    }

    const toggleButton = pagerRow.querySelector('[' + ACTION_ATTR + '="toggle"]');
    const hasAny = loaded > 0;
    const hasMore = loaded < hiddenRows.length;
    if (toggleButton) {
      toggleButton.textContent = hasAny ? 'Show less' : 'Show more';
    }
    pagerRow.hidden = !hasMore && !hasAny;
    pagerRow.style.setProperty('display', pagerRow.hidden ? 'none' : 'flex', 'important');

    const beforeNode = hiddenRows[loaded] || null;
    if (pagerRow.parentElement !== sectionList || pagerRow.nextSibling !== beforeNode) {
      sectionList.insertBefore(pagerRow, beforeNode);
    }
  }

  function apply() {
    for (const spec of SECTION_SPECS) {
      const heading = getSidebarSectionTitle(document, spec.title);
      const list = getSidebarSectionList(heading);
      if (!list) continue;
      renderSidebarSection(list, spec.title.toLowerCase());
    }
  }

  let pending = false;
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
    apply();
    if (document.documentElement) {
      observer.observe(document.documentElement, {
        attributes: true,
        childList: true,
        subtree: true
      });
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
