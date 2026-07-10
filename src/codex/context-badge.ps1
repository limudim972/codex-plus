function Get-CodexContextBadgePayload {
    @'
(function () {
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
    badge.textContent = stripBidiMarks(percent ? 'Plus ' + percent : 'Plus');
  }

  function apply() {
    for (const scopeDoc of [document, ...Array.from(document.querySelectorAll('iframe')).map((frame) => {
      try { return frame.contentDocument; } catch { return null; }
    }).filter(Boolean)]) {
      ensureBadge(scopeDoc);
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

  window.__CODEX_PLUS_CONTEXT_BADGE = {
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
