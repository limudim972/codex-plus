function Get-CodexNewWindowButtonPayload {
    @'
(function () {
  if (window.__CODEX_PLUS_NEW_WINDOW_BUTTON) return;

  const HEADER_SELECTOR = '.app-header-tint';
  const MENU_GROUP_SELECTOR = 'button[aria-label="Help"]';
  const BUTTON_ATTR = 'data-codex-plus-shared-window-button';
  const PROJECT_BUTTON_ATTR = 'data-codex-plus-project-window-button';
  const PENDING_PROJECT_WINDOWS_KEY = 'codexPlusPendingProjectWindows';

  function getMenuGroup() {
    const helpButton = document.querySelector(HEADER_SELECTOR + ' ' + MENU_GROUP_SELECTOR);
    return helpButton?.parentElement || null;
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
    // The native bridge accepts the home route only. Project metadata is carried
    // through the shared Plus-session queue and claimed by the new window.
    return '/';
  }

  function launchSharedWindow(context) {
    const bridge = window.electronBridge?.sendMessageFromView;
    if (typeof bridge !== 'function') return;
    const path = context?.id && context?.name ? getProjectStartupPath(context) : '/';
    if (context?.id && context?.name) {
      try {
        const pending = JSON.parse(localStorage.getItem(PENDING_PROJECT_WINDOWS_KEY) || '[]');
        pending.push({ codexPlusProjectId: context.id, codexPlusProjectName: context.name, startupPath: path });
        localStorage.setItem(PENDING_PROJECT_WINDOWS_KEY, JSON.stringify(pending.slice(-20)));
      } catch {}
    }
    Promise.resolve(window.electronBridge.sendMessageFromView({ type: 'open-in-new-window', path })).catch(() => {});
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
    if (!menuGroup || menuGroup.querySelector('[' + BUTTON_ATTR + ']')) return;
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

  install();
  window.__CODEX_PLUS_NEW_WINDOW_BUTTON = true;
  new MutationObserver(install).observe(document.documentElement, { childList: true, subtree: true });
  window.setInterval(install, 500);
})();
'@
}
