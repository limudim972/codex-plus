function Get-CodexNewWindowButtonPayload {
    @'
(function () {
  const HEADER_SELECTOR = '.app-header-tint';
  const MENU_GROUP_SELECTOR = '[role="menubar"][aria-label="Application menu"]';
  const BUTTON_ATTR = 'data-codex-plus-shared-window-button';
  const DASHBOARD_BUTTON_ATTR = 'data-codex-plus-usage-dashboard-button';
  const DASHBOARD_URL = 'http://127.0.0.1:3000/';
  const PROJECT_BUTTON_ATTR = 'data-codex-plus-project-window-button';
  const PENDING_PROJECT_WINDOWS_KEY = 'codexPlusPendingProjectWindows';

  // A previous payload can leave the global flag set after its DOM nodes are
  // removed by a native React rerender. Reconcile from the actual DOM instead
  // of permanently disabling installation based on that stale flag.
  function hasInstalledButtons() {
    return Boolean(
      document.querySelector('[' + BUTTON_ATTR + ']')
      && document.querySelector('[' + PROJECT_BUTTON_ATTR + ']')
    );
  }

  if (window.__CODEX_PLUS_NEW_WINDOW_BUTTON && hasInstalledButtons()) return;

  function getMenuGroup() {
    return document.querySelector(HEADER_SELECTOR + ' ' + MENU_GROUP_SELECTOR)
      || document.querySelector(MENU_GROUP_SELECTOR)
      || document.querySelector('button[aria-label="Help"]')?.parentElement
      || null;
  }

  function projectContextFromRow(row) {
    if (!row) return null;
    const id = row.getAttribute('data-app-action-sidebar-project-id')
      || row.querySelector('[data-app-action-sidebar-project-id]')?.getAttribute('data-app-action-sidebar-project-id');
    const name = row.getAttribute('data-app-action-sidebar-project-label')
      || row.querySelector('[data-app-action-sidebar-project-label]')?.textContent
      || row.textContent;
    return id && name ? { id: String(id).trim(), name: String(name).replace(/\s+/g, ' ').trim() } : null;
  }

  function currentProjectContext() {
    if (window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.id && window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.name) {
      return window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT;
    }
    const active = document.querySelector('[data-app-action-sidebar-thread-active="true"]');
    const projectRow = active?.closest('[data-app-action-sidebar-project-row]')
      || Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]')).find((row) => row.querySelector('[data-app-action-sidebar-thread-active="true"]'));
    const rowContext = projectContextFromRow(projectRow);
    if (rowContext) return rowContext;

    const activeProjectId = active?.getAttribute('data-app-action-sidebar-thread-project-id')
      || active?.querySelector('[data-app-action-sidebar-thread-project-id]')?.getAttribute('data-app-action-sidebar-thread-project-id');
    const sourceList = active?.getAttribute('data-codex-plus-source-list-label') || '';
    const sourcePrefix = 'Scheduled tasks in ';
    const sourceProjectName = sourceList.startsWith(sourcePrefix)
      ? sourceList.slice(sourcePrefix.length).trim()
      : '';
    if (activeProjectId && sourceProjectName) {
      return { id: String(activeProjectId).trim(), name: sourceProjectName };
    }

    if (sourceProjectName) {
      const sourceProjectRow = Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
        .find((row) => projectContextFromRow(row)?.name === sourceProjectName);
      return projectContextFromRow(sourceProjectRow);
    }

    return null;
  }

  function getProjectStartupPath(context) {
    // Codex validates this native route and silently rejects custom query
    // parameters or the bare home route. Use a real local thread route to
    // satisfy the native window validator; the project metadata still travels
    // through the shared queue.
    const activeThread = document.querySelector('[data-app-action-sidebar-thread-active="true"]')
      || document.querySelector('[data-app-action-sidebar-thread-id]');
    const projectThread = Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-id]'))
      .find((thread) => {
        const projectName = thread.getAttribute('data-codex-plus-thread-project-title');
        return context?.name && projectName === context.name;
      });
    const threadId = projectThread?.getAttribute('data-app-action-sidebar-thread-id')
      || activeThread?.getAttribute('data-app-action-sidebar-thread-id');
    return threadId ? '/local/' + encodeURIComponent(threadId) : '/local/' + encodeURIComponent('00000000-0000-0000-0000-000000000000');
  }

  function launchSharedWindow(context) {
    const bridge = window.electronBridge?.sendMessageFromView;
    if (typeof bridge !== 'function') return;
    const projectName = context?.name ? String(context.name).replace(/\s+/g, ' ').trim() : '';
    window.__CODEX_PLUS_CONTEXT_BADGE?.setStatus('- Launching ' + (projectName ? projectName + ' ' : '') + 'window');
    const path = context?.id && context?.name ? getProjectStartupPath(context) : '/';
    if (context?.id && context?.name) {
      try {
        const pending = JSON.parse(localStorage.getItem(PENDING_PROJECT_WINDOWS_KEY) || '[]');
        pending.push({
          codexPlusProjectId: context.id,
          codexPlusProjectName: context.name,
          startupPath: path,
          createdAt: Date.now()
        });
        localStorage.setItem(PENDING_PROJECT_WINDOWS_KEY, JSON.stringify(pending.slice(-20)));
      } catch {}
    }
    const launchRequest = Promise.resolve(window.electronBridge.sendMessageFromView({ type: 'open-in-new-window', path }));
    launchRequest.catch(() => {
      window.__CODEX_PLUS_CONTEXT_BADGE?.clearStatus();
    });
    window.setTimeout(() => window.__CODEX_PLUS_CONTEXT_BADGE?.clearStatus(), 5000);
  }

  function openUsageDashboard() {
    const link = document.createElement('a');
    link.href = DASHBOARD_URL;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.textContent = 'Usage Dashboard';
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    window.setTimeout(() => link.remove(), 1000);
  }

  function installProjectButtons() {
    for (const row of document.querySelectorAll('[data-app-action-sidebar-project-row]')) {
      if (row.querySelector('[' + PROJECT_BUTTON_ATTR + ']')) continue;
      const context = projectContextFromRow(row);
      if (!context) continue;
      const button = document.createElement('button');
      button.type = 'button';
      button.setAttribute(PROJECT_BUTTON_ATTR, 'true');
      button.setAttribute('aria-label', 'New window');
      button.title = 'Open project in a new window';
      button.className = 'no-drag rounded-md border border-transparent px-2 py-1 text-token-text-tertiary hover:bg-token-foreground/5 hover:text-token-description-foreground';
      button.textContent = '> New window';
      button.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        launchSharedWindow(projectContextFromRow(row));
      });
      (row.querySelector('[data-app-action-sidebar-project-label]')?.parentElement || row).appendChild(button);
    }
  }

  function install() {
    installProjectButtons();
    if (!window.__CODEX_PLUS_PROJECT_WINDOW_CLICK_GUARD) {
      document.addEventListener('click', (event) => {
        const target = event.target instanceof Element
          ? event.target.closest('[' + PROJECT_BUTTON_ATTR + ']')
          : null;
        if (!target) return;
        const row = target.closest('[data-app-action-sidebar-project-row]');
        const context = projectContextFromRow(row);
        if (!context) return;
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
        launchSharedWindow(context);
      }, true);
      window.__CODEX_PLUS_PROJECT_WINDOW_CLICK_GUARD = true;
    }
    const menuGroup = getMenuGroup();
    if (menuGroup) {
      if (!menuGroup.querySelector('[' + BUTTON_ATTR + ']')) {
        const nativeButton = menuGroup.querySelector('button');
        const button = document.createElement('button');
        button.type = 'button';
        button.setAttribute(BUTTON_ATTR, 'true');
        button.setAttribute('aria-label', 'New window');
        button.title = 'Open a new Codex window in this Plus session';
        button.className = nativeButton?.className || 'no-drag rounded-md border border-transparent px-2.5 py-1 text-base font-normal leading-none outline-none transition-colors text-token-text-tertiary hover:bg-token-foreground/5 hover:text-token-description-foreground focus-visible:bg-token-foreground/5 focus-visible:text-token-description-foreground';
        button.innerHTML = '<span aria-hidden="true" style="font-size:16px;line-height:1">></span><span>New window</span>';
        button.addEventListener('click', () => {
          if (button.disabled) return;
          button.disabled = true;
          try { launchSharedWindow(currentProjectContext()); }
          finally { window.setTimeout(() => { button.disabled = false; }, 800); }
        });
        menuGroup.appendChild(button);
      }

      if (!menuGroup.querySelector('[' + DASHBOARD_BUTTON_ATTR + ']')) {
        const nativeButton = menuGroup.querySelector('button');
        const dashboardButton = document.createElement('button');
        dashboardButton.type = 'button';
        dashboardButton.setAttribute(DASHBOARD_BUTTON_ATTR, 'true');
        dashboardButton.setAttribute('aria-label', 'Usage Dashboard');
        dashboardButton.title = 'Open the Codex usage dashboard';
        dashboardButton.className = nativeButton?.className || 'no-drag rounded-md border border-transparent px-2.5 py-1 text-base font-normal leading-none outline-none transition-colors text-token-text-tertiary hover:bg-token-foreground/5 hover:text-token-description-foreground focus-visible:bg-token-foreground/5 focus-visible:text-token-description-foreground';
        dashboardButton.textContent = 'Usage Dashboard';
        dashboardButton.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          openUsageDashboard();
        });
        menuGroup.appendChild(dashboardButton);
      }
    }
  }

  let installPending = false;
  const INSTALL_SURFACE_SELECTOR = [
    HEADER_SELECTOR,
    MENU_GROUP_SELECTOR,
    '[data-app-action-sidebar-project-row]'
  ].join(',');

  function mutationTouchesInstallSurface(record) {
    const target = record.target instanceof Element
      ? record.target
      : record.target?.parentElement;
    if (target?.matches(INSTALL_SURFACE_SELECTOR) || target?.closest(INSTALL_SURFACE_SELECTOR)) return true;
    return [...Array.from(record.addedNodes || []), ...Array.from(record.removedNodes || [])].some((node) => {
      return node instanceof Element && (
        node.matches(INSTALL_SURFACE_SELECTOR) || Boolean(node.querySelector(INSTALL_SURFACE_SELECTOR))
      );
    });
  }

  function scheduleInstall(records) {
    if (records && !records.some(mutationTouchesInstallSurface)) return;
    if (installPending) return;
    installPending = true;
    window.setTimeout(() => {
      installPending = false;
      install();
    }, 80);
  }

  install();
  window.__CODEX_PLUS_NEW_WINDOW_BUTTON = true;
  new MutationObserver(scheduleInstall).observe(document.documentElement, { childList: true, subtree: true });
  window.setInterval(scheduleInstall, 5000);
})();
'@
}
