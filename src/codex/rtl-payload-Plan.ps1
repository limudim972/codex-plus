function Get-CodexRtlPayloadPlan {
    @'
(function () {
  const PLAN_PANEL_SELECTOR = '[role="tabpanel"][aria-label="Plan"][data-tab-id="plan"]';
  const LIST_CONTAINER_SELECTOR = 'ol, ul';
  const LIST_ITEM_SELECTOR = 'li';
  const BLOCKQUOTE_SELECTOR = 'blockquote';
  const INLINE_TECHNICAL_SELECTOR = 'code, kbd, samp';
  const TASK_CHECKBOX_SELECTOR = 'input[type="checkbox"]';
  const TEXT_BLOCK_SELECTOR = [
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'figcaption',
    '[role="article"]',
    '[data-message-author-role]',
    '[data-testid*="message"]',
    '[data-testid*="markdown"]'
  ].join(',');
  const SKIP_SELECTOR = [
    'pre',
    'code',
    'kbd',
    'samp',
    'textarea',
    'input',
    'button',
    'select',
    'option',
    'svg',
    'canvas',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    '[role="button"]',
    '[contenteditable="false"]',
    '.cm-editor',
    '.monaco-editor',
    '[data-language]',
    '[class*="code"]',
    '[class*="Code"]'
  ].join(',');
  const INLINE_STYLE_ID = 'data-codex-plus-plan-rtl-style';

  function shouldSkipElement(element) {
    return Boolean(element.closest(SKIP_SELECTOR));
  }

  function cleanupOwnedDirection(element) {
    if (!element || !element.hasAttribute('data-codex-plus-plan-rtl')) return;
    element.removeAttribute('data-codex-plus-plan-rtl');
    element.removeAttribute('dir');
    element.style.direction = '';
    element.style.textAlign = '';
    element.style.unicodeBidi = '';
  }

  function applyBlockDirection(element, direction, options) {
    const forceLtr = Boolean(options && options.forceLtr);

    if (direction === 'rtl') {
      if (element.getAttribute('dir') !== 'rtl') {
        element.setAttribute('dir', 'rtl');
      }
      if (element.getAttribute('data-codex-plus-plan-rtl') !== 'rtl') {
        element.setAttribute('data-codex-plus-plan-rtl', 'rtl');
      }
      if (element.style.direction !== 'rtl') {
        element.style.direction = 'rtl';
      }
      if (element.style.textAlign !== 'right') {
        element.style.textAlign = 'right';
      }
      if (element.style.unicodeBidi !== 'plaintext') {
        element.style.unicodeBidi = 'plaintext';
      }
      return;
    }

    if (direction === 'ltr' && forceLtr) {
      if (element.getAttribute('dir') !== 'ltr') {
        element.setAttribute('dir', 'ltr');
      }
      if (element.getAttribute('data-codex-plus-plan-rtl') !== 'ltr') {
        element.setAttribute('data-codex-plus-plan-rtl', 'ltr');
      }
      if (element.style.direction !== 'ltr') {
        element.style.direction = 'ltr';
      }
      if (element.style.textAlign !== 'left') {
        element.style.textAlign = 'left';
      }
      if (element.style.unicodeBidi !== 'isolate') {
        element.style.unicodeBidi = 'isolate';
      }
      return;
    }

    cleanupOwnedDirection(element);
  }

  function processInlineTechnicalIslands(root) {
    for (const technical of root.querySelectorAll(INLINE_TECHNICAL_SELECTOR)) {
      if (technical.closest('pre')) continue;
      if (technical.getAttribute('dir') !== 'ltr') {
        technical.setAttribute('dir', 'ltr');
      }
      if (technical.getAttribute('data-codex-plus-plan-rtl') !== 'ltr') {
        technical.setAttribute('data-codex-plus-plan-rtl', 'ltr');
      }
      if (technical.style.unicodeBidi !== 'isolate') {
        technical.style.unicodeBidi = 'isolate';
      }
    }
  }

  function ensureInlineStyle(scopeDoc) {
    if (!scopeDoc || !scopeDoc.head) return;
    if (scopeDoc.head.querySelector('style[' + INLINE_STYLE_ID + ']')) return;

    const style = scopeDoc.createElement('style');
    style.setAttribute(INLINE_STYLE_ID, 'true');
    style.textContent = [
      '[data-codex-plus-plan-rtl="rtl"],',
      '[data-codex-plus-plan-rtl="ltr"] {',
      '  unicode-bidi: isolate !important;',
      '}',
      '[data-codex-plus-plan-rtl="rtl"] ' + INLINE_TECHNICAL_SELECTOR + ' {',
      '  direction: ltr !important;',
      '  unicode-bidi: isolate !important;',
      '}',
      'blockquote[data-codex-plus-plan-rtl="rtl"] {',
      '  border-left: 0 !important;',
      '  border-right: 0.25rem solid currentColor !important;',
      '  border-inline-start: 0;',
      '  border-inline-end: 0.25rem solid currentColor;',
      '  padding-left: 0 !important;',
      '  padding-right: 1rem !important;',
      '  padding-inline-start: 0;',
      '  padding-inline-end: 1rem;',
      '}',
      'li[data-codex-plus-plan-rtl="rtl"] > ' + TASK_CHECKBOX_SELECTOR + ',',
      'li[data-codex-plus-plan-rtl="rtl"] ' + TASK_CHECKBOX_SELECTOR + ' {',
      '  direction: ltr !important;',
      '  unicode-bidi: isolate !important;',
      '}'
    ].join('\n');
    scopeDoc.head.appendChild(style);
  }

  function processPlanPanels(scopeDoc) {
    for (const panel of scopeDoc.querySelectorAll(PLAN_PANEL_SELECTOR)) {
      if (shouldSkipElement(panel)) continue;

      if (panel.getAttribute('data-codex-plus-plan-surface') !== 'plan') {
        panel.setAttribute('data-codex-plus-plan-surface', 'plan');
      }
      if (panel.getAttribute('dir') !== 'rtl') {
        panel.setAttribute('dir', 'rtl');
      }
      if (panel.getAttribute('data-codex-plus-plan-rtl') !== 'rtl') {
        panel.setAttribute('data-codex-plus-plan-rtl', 'rtl');
      }
      if (panel.style.direction !== 'rtl') {
        panel.style.direction = 'rtl';
      }
      if (panel.style.textAlign !== 'right') {
        panel.style.textAlign = 'right';
      }
      if (panel.style.unicodeBidi !== 'plaintext') {
        panel.style.unicodeBidi = 'plaintext';
      }
      processInlineTechnicalIslands(panel);

      for (const list of panel.querySelectorAll(LIST_CONTAINER_SELECTOR)) {
        if (shouldSkipElement(list)) continue;
        applyBlockDirection(list, 'rtl');
        for (const item of list.querySelectorAll(':scope > ' + LIST_ITEM_SELECTOR)) {
          if (shouldSkipElement(item)) continue;
          applyBlockDirection(item, 'rtl');
          processInlineTechnicalIslands(item);
        }
      }

      for (const blockquote of panel.querySelectorAll(BLOCKQUOTE_SELECTOR)) {
        if (shouldSkipElement(blockquote)) continue;
        applyBlockDirection(blockquote, 'rtl');
        processInlineTechnicalIslands(blockquote);
      }

      for (const block of panel.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
        if (block.closest(SKIP_SELECTOR) || block.closest('pre')) continue;
        applyBlockDirection(block, 'rtl');
      }
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

  const observer = new MutationObserver(schedule);
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
  const apply = () => {
    const wasObserving = observing;
    if (wasObserving) disconnect();
    applying = true;
    try {
      ensureInlineStyle(document);
      processPlanPanels(document);
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

  window.__CODEX_PLUS_RTL_PLAN = {
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
