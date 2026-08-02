function Get-CodexContextBadgePayload {
    @'
(function () {
  if (window.__CODEX_PLUS_CONTEXT_BADGE && window.__CODEX_PLUS_CONTEXT_BADGE.observer) {
    return;
  }

  const BADGE_ID = 'data-codex-plus-context-badge';
  const BADGE_HOST_ID = 'data-codex-plus-context-badge-host';
  const TITLE_SELECTOR = [
    '[data-thread-title="true"]',
    'span[data-thread-title="true"]',
    'div[data-app-action-sidebar-project-row]',
    '[data-app-action-sidebar-project-label]',
    '[data-testid="app-shell-header-context-menu-surface"] .min-w-0.truncate[data-state]'
  ].join(',');
  const TOOLTIP_TRIGGER_SELECTOR = '[aria-label^="Context usage:"]';
  const CONVERSATION_SELECTOR = '[data-thread-find-target="conversation"]';
  const PLAN_PANEL_SELECTOR = '[role="tabpanel"][aria-label="Plan"][data-tab-id="plan"]';
  let statusText = '';

  function normalizeText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function stripBidiMarks(text) {
    return String(text || '').replace(/[\u0591-\u05C7\u200E\u200F\u202A-\u202E]/g, '');
  }

  function hasActiveThreadSurface(scopeDoc) {
    return Boolean(
      scopeDoc.querySelector(CONVERSATION_SELECTOR) ||
      scopeDoc.querySelector(PLAN_PANEL_SELECTOR) ||
      scopeDoc.querySelector(TOOLTIP_TRIGGER_SELECTOR) ||
      scopeDoc.body ||
      scopeDoc.documentElement
    );
  }

  function readContextPercent(scopeDoc) {
    const trigger = scopeDoc.querySelector(TOOLTIP_TRIGGER_SELECTOR);
    if (!trigger) return '';
    const ariaLabel = normalizeText(trigger.getAttribute('aria-label') || '');
    const percentMatch = ariaLabel.match(/(\d{1,3}%)/i);
    return percentMatch ? percentMatch[1] : '';
  }

  function readUsageText() {
    const usageTitle = normalizeText(window.__CODEX_PLUS_USAGE_WINDOW_TITLE);
    if (!usageTitle || usageTitle === 'Plus Codex') return '';
    const match = usageTitle.match(/^Plus Codex\s*-\s*(.+)$/i);
    return match ? '- ' + match[1] : usageTitle;
  }

  function readWindowTitle(scopeDoc) {
    const runtimeTitle = normalizeText(window.__CODEX_PLUS_NATIVE_WINDOW_TITLE);
    if (runtimeTitle) return runtimeTitle;
    const projectContext = window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT;
    if (projectContext?.name) return normalizeText(projectContext.name);
    const activeThread = scopeDoc?.querySelector('[data-codex-plus-sidebar-synthetic-row="threads"][data-app-action-sidebar-thread-active]:not([data-app-action-sidebar-thread-active="false"])');
    const activeProject = normalizeText(activeThread?.getAttribute('data-codex-plus-thread-project-title'));
    if (activeProject) return activeProject;
    const title = normalizeText(scopeDoc?.title);
    if (title.startsWith('Codex Plus Project:')) return normalizeText(title.slice('Codex Plus Project:'.length));
    return title;
  }

  function ensureBadge(scopeDoc) {
    if (!scopeDoc) return;

    let badge = scopeDoc.querySelector('[' + BADGE_ID + ']');
    if (!badge) {
      badge = scopeDoc.createElement('div');
      badge.setAttribute(BADGE_ID, 'true');
      badge.setAttribute('aria-hidden', 'true');
      badge.style.position = 'fixed';
      badge.style.insetInlineStart = '50%';
      badge.style.top = '12px';
      badge.style.transform = 'translateX(-50%)';
      badge.style.zIndex = '2147483647';
      badge.style.pointerEvents = 'none';
      badge.style.userSelect = 'none';
      badge.style.padding = '0';
      badge.style.margin = '0';
      badge.style.border = '0';
      badge.style.background = 'transparent';
      badge.style.boxShadow = 'none';
      badge.style.backdropFilter = 'none';
      badge.style.webkitBackdropFilter = 'none';
      badge.style.whiteSpace = 'nowrap';
      badge.style.display = 'inline-flex';
      badge.style.width = 'max-content';
      badge.style.maxWidth = 'calc(100vw - 240px)';
      badge.style.overflow = 'visible';
      badge.style.font = '600 13px/1.2 system-ui, sans-serif';
      badge.style.color = '#9ca3af';
    }

    const header = scopeDoc.querySelector('.app-header-tint');
    const host = header || scopeDoc.body || scopeDoc.documentElement || scopeDoc;
    if (badge.parentElement !== host) {
      if (badge.parentElement) badge.parentElement.removeChild(badge);
      if (host && host.style && getComputedStyle(host).position === 'static') {
        host.style.position = 'relative';
      }
      host.appendChild(badge);
    }

    const percent = readContextPercent(scopeDoc);
    const title = readWindowTitle(scopeDoc);
    const usage = readUsageText();
    const nextText = stripBidiMarks(['Plus', title, statusText, usage || percent].filter(Boolean).join(' '));
    if (badge.textContent !== nextText) {
      badge.textContent = nextText;
    }
  }

  let pending = false;
  let observing = false;
  let applying = false;
  const schedule = () => {
    if (pending || applying) return;
    pending = true;
    window.setTimeout(() => {
      pending = false;
      apply();
    }, 50);
  };

  const BADGE_RELEVANT_SELECTOR = [
    TOOLTIP_TRIGGER_SELECTOR,
    TITLE_SELECTOR,
    '.app-header-tint',
    'iframe'
  ].join(',');

  function mutationTouchesBadgeSource(record) {
    const target = record.target instanceof Element
      ? record.target
      : record.target?.parentElement;
    if (target?.hasAttribute(BADGE_ID) || target?.closest('[' + BADGE_ID + ']')) return false;
    if (target?.matches(BADGE_RELEVANT_SELECTOR) || target?.closest(BADGE_RELEVANT_SELECTOR)) return true;
    return Array.from(record.addedNodes || []).some((node) => {
      return node instanceof Element && (
        node.matches(BADGE_RELEVANT_SELECTOR) || Boolean(node.querySelector(BADGE_RELEVANT_SELECTOR))
      );
    });
  }

  const observer = new MutationObserver((records) => {
    if (records.some(mutationTouchesBadgeSource)) schedule();
  });
  const observe = () => {
    if (observing || !document.documentElement) return;
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['aria-label', 'data-thread-title'],
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
  const apply = () => {
    const wasObserving = observing;
    if (wasObserving) disconnect();
    applying = true;
    try {
      for (const scopeDoc of [document, ...Array.from(document.querySelectorAll('iframe')).map((frame) => {
        try { return frame.contentDocument; } catch { return null; }
      }).filter(Boolean)]) {
        ensureBadge(scopeDoc);
      }
    } finally {
      applying = false;
      if (wasObserving) observe();
    }
  };

  const start = () => {
    disconnect();
    apply();
    observe();
  };

  window.__CODEX_PLUS_CONTEXT_BADGE = {
    apply,
    observer,
    setStatus(nextStatus) {
      statusText = normalizeText(nextStatus);
      apply();
    },
    clearStatus() {
      statusText = '';
      apply();
    }
  };

  window.addEventListener('codex-plus-usage-updated', apply);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
'@
}
