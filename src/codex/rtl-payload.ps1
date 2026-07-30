function Get-CodexRtlPayload {
    @'
(function () {
  if (window.__CODEX_RTL_FIX_CODEX && window.__CODEX_RTL_FIX_CODEX.observer) {
    return;
  }

  const CONVERSATION_SELECTOR = '[data-thread-find-target="conversation"]';
  const USER_BUBBLE_SELECTOR = '[data-user-message-bubble="true"]';
  const TITLE_SELECTOR = [
    '[data-thread-title="true"]',
    'span[data-thread-title="true"]',
    'div[data-app-action-sidebar-project-row]',
    '[data-app-action-sidebar-project-label]',
    '[data-testid="app-shell-header-context-menu-surface"] .min-w-0.truncate[data-state]'
  ].join(',');
  const COMPOSER_SELECTOR = '[contenteditable], [contenteditable="true"], [contenteditable=true], div.ProseMirror, textarea';
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

  const LEFT_EDGE_SIDEBAR_GUARD_KEY = '__CODEX_PLUS_LEFT_EDGE_SIDEBAR_GUARD';
  const LEFT_EDGE_SIDEBAR_GUARD_WIDTH = 40;

  function installLeftEdgeSidebarGuard() {
    if (window[LEFT_EDGE_SIDEBAR_GUARD_KEY]) return;
    const blockEdgeActivation = (event) => {
      if (event.isTrusted && event.clientX <= LEFT_EDGE_SIDEBAR_GUARD_WIDTH
          && !document.querySelector('[data-app-shell-sidebar-trigger][aria-label="Hide sidebar"]')) {
        event.stopImmediatePropagation();
      }
    };
    for (const eventName of ['pointerenter', 'mouseenter', 'pointerover', 'mouseover', 'pointermove', 'mousemove']) {
      window.addEventListener(eventName, blockEdgeActivation, true);
    }
    window[LEFT_EDGE_SIDEBAR_GUARD_KEY] = true;
  }

  const INLINE_STYLE_ID = 'data-codex-rtl-fix-style';
  const RTL_SHARED = window.__CODEX_RTL_SHARED_HELPERS;
  const RTL_RE = RTL_SHARED.RTL_RE;
  const LTR_RE = RTL_SHARED.LTR_RE;
  const STRONG_RE = RTL_SHARED.STRONG_RE;
  const normalizeText = RTL_SHARED.normalizeText;
  function stripDiagnosticPrefix(text) {
    return RTL_SHARED.stripDiagnosticPrefix(text);
  }
  function getMeaningfulText(input) {
    return RTL_SHARED.getMeaningfulText(input, INLINE_TECHNICAL_SELECTOR);
  }
  function classifyDirection(input) {
    return RTL_SHARED.classifyDirection(input, INLINE_TECHNICAL_SELECTOR);
  }

  function shouldSkipElement(element) {
    return Boolean(element.closest(SKIP_SELECTOR));
  }

  function cleanupOwnedDirection(element) {
    if (!element || !element.hasAttribute('data-codex-rtl-fix')) return;
    element.removeAttribute('data-codex-rtl-fix');
    element.removeAttribute('dir');
    element.style.textAlign = '';
    element.style.unicodeBidi = '';
  }

  function setOwnedDirection(element, direction, marker, unicodeBidi, forceLtr) {
    const shouldApply = direction === 'rtl' || (direction === 'ltr' && forceLtr);
    if (!shouldApply) {
      cleanupOwnedDirection(element);
      return;
    }

    if (element.getAttribute('dir') !== direction) {
      element.setAttribute('dir', direction);
    }
    if (element.getAttribute('data-codex-rtl-fix') !== marker) {
      element.setAttribute('data-codex-rtl-fix', marker);
    }
    if (element.style.textAlign !== 'start') {
      element.style.textAlign = 'start';
    }
    if (element.style.unicodeBidi !== unicodeBidi) {
      element.style.unicodeBidi = unicodeBidi;
    }
  }

  function ensureInlineIslandsStyle() {
    if (document.head && document.head.querySelector('style[' + INLINE_STYLE_ID + ']')) return;
    if (!document.head) return;

    const style = document.createElement('style');
    style.setAttribute(INLINE_STYLE_ID, 'true');
    style.textContent = [
      '[data-thread-find-target="conversation"] code,',
      '[data-thread-find-target="conversation"] kbd,',
      '[data-thread-find-target="conversation"] samp,',
      '[data-user-message-bubble="true"] code,',
      '[data-user-message-bubble="true"] kbd,',
      '[data-user-message-bubble="true"] samp {',
      '  direction: ltr !important;',
      '  unicode-bidi: isolate !important;',
      '}',
      '[data-codex-rtl-fix="rtl"],',
      '[data-codex-rtl-fix="ltr"] {',
      '  unicode-bidi: isolate !important;',
      '}',
      'blockquote[data-codex-rtl-fix="rtl"] {',
      '  border-left: 0 !important;',
      '  border-right: 0.25rem solid currentColor !important;',
      '  border-inline-start: 0;',
      '  border-inline-end: 0.25rem solid currentColor;',
      '  padding-left: 0 !important;',
      '  padding-right: 1rem !important;',
      '  padding-inline-start: 0;',
      '  padding-inline-end: 1rem;',
      '}',
      'li[data-codex-rtl-fix="rtl"] > ' + TASK_CHECKBOX_SELECTOR + ',',
      'li[data-codex-rtl-fix="rtl"] ' + TASK_CHECKBOX_SELECTOR + ' {',
      '  direction: ltr !important;',
      '  unicode-bidi: isolate !important;',
      '}',
      '[class*="bg-token-input-validation-error-background"]:has(.text-xs.font-semibold) {',
      '  display: none !important;',
      '}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function cleanupConversationRoot(root) {
    if (root.getAttribute('dir') === 'rtl' && root.getAttribute('data-codex-rtl-fix') !== 'rtl') {
      root.removeAttribute('dir');
    }
    if (root.getAttribute('data-codex-rtl-fix') === 'rtl') {
      cleanupOwnedDirection(root);
    }
  }

  function hasNestedTextBlock(element) {
    for (const child of element.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
      if (child !== element && !shouldSkipElement(child) && child.innerText && child.innerText.trim()) {
        return true;
      }
    }
    return false;
  }

  function applyBlockDirection(element, direction, options) {
    const forceLtr = Boolean(options && options.forceLtr);

    if (direction === 'rtl') {
      setOwnedDirection(element, 'rtl', 'rtl', 'plaintext', false);
      return;
    }

    if (direction === 'ltr' && forceLtr) {
      setOwnedDirection(element, 'ltr', 'ltr', 'isolate', true);
      return;
    }

    cleanupOwnedDirection(element);
  }

  function applyDirection(element, direction) {
    applyBlockDirection(element, direction);
  }

  function processTextBlock(element) {
    if (shouldSkipElement(element)) return;
    if (element.closest(LIST_CONTAINER_SELECTOR + ',' + BLOCKQUOTE_SELECTOR + ',table')) return;
    if (hasNestedTextBlock(element)) {
      cleanupOwnedDirection(element);
      return;
    }

    applyBlockDirection(element, classifyDirection(element));
  }

  function processTitles() {
    for (const title of document.querySelectorAll(TITLE_SELECTOR)) {
      const text = getMeaningfulText(title);
      if (!text.trim()) continue;
      const direction = classifyDirection(text);
      setOwnedDirection(title, direction, direction, 'isolate', true);
    }
  }

  function processComposers() {
    for (const composer of document.querySelectorAll(COMPOSER_SELECTOR)) {
      const isDirectComposer = composer.matches('div.ProseMirror') || composer.matches('textarea') || composer.hasAttribute('contenteditable');
      if (!isDirectComposer && shouldSkipElement(composer)) continue;
      if (composer.getAttribute('dir') !== 'auto') {
        composer.setAttribute('dir', 'auto');
      }
      if (composer.getAttribute('data-codex-rtl-fix') !== 'composer') {
        composer.setAttribute('data-codex-rtl-fix', 'composer');
      }
      if (composer.style.textAlign !== 'start') {
        composer.style.textAlign = 'start';
      }
      if (composer.style.unicodeBidi !== 'plaintext') {
        composer.style.unicodeBidi = 'plaintext';
      }
    }
  }

  function getListItemOwnText(item) {
    const clone = item.cloneNode(true);
    for (const nested of clone.querySelectorAll(LIST_CONTAINER_SELECTOR)) {
      nested.remove();
    }
    return getMeaningfulText(clone);
  }

  function processInlineTechnicalIslands(root) {
    for (const technical of root.querySelectorAll(INLINE_TECHNICAL_SELECTOR)) {
      if (technical.closest('pre')) continue;
      if (technical.getAttribute('dir') !== 'ltr') {
        technical.setAttribute('dir', 'ltr');
      }
      if (technical.getAttribute('data-codex-rtl-fix') !== 'ltr') {
        technical.setAttribute('data-codex-rtl-fix', 'ltr');
      }
      if (technical.style.unicodeBidi !== 'isolate') {
        technical.style.unicodeBidi = 'isolate';
      }
    }
  }

  function processLists(root) {
    for (const list of root.querySelectorAll(LIST_CONTAINER_SELECTOR)) {
      if (shouldSkipElement(list)) continue;
      const listDirection = classifyDirection(list);
      applyBlockDirection(list, listDirection);

      for (const item of list.querySelectorAll(':scope > ' + LIST_ITEM_SELECTOR)) {
        if (shouldSkipElement(item)) continue;
        const itemDirection = classifyDirection(getListItemOwnText(item));
        const direction = itemDirection === 'neutral' ? listDirection : itemDirection;
        applyBlockDirection(item, direction, { forceLtr: listDirection === 'rtl' });
        processInlineTechnicalIslands(item);
      }
    }
  }

  function processBlockquotes(root) {
    for (const blockquote of root.querySelectorAll(BLOCKQUOTE_SELECTOR)) {
      if (shouldSkipElement(blockquote)) continue;
      applyBlockDirection(blockquote, classifyDirection(blockquote));
      processInlineTechnicalIslands(blockquote);
    }
  }

  function processUserMessageBubbles() {
    for (const bubble of document.querySelectorAll(USER_BUBBLE_SELECTOR)) {
      const bubbleDirection = classifyDirection(bubble);
      applyBlockDirection(bubble, bubbleDirection);

      processInlineTechnicalIslands(bubble);
      processLists(bubble);
      processBlockquotes(bubble);

      for (const block of bubble.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
        processTextBlock(block);
      }
    }
  }

  function processConversationRoots() {
    for (const root of document.querySelectorAll(CONVERSATION_SELECTOR)) {
      cleanupConversationRoot(root);
      processInlineTechnicalIslands(root);
      processLists(root);
      processBlockquotes(root);
      for (const block of root.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
        if (block.closest(USER_BUBBLE_SELECTOR)) continue;
        processTextBlock(block);
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

  function mutationIsInsideComposer(record) {
    const target = record.target instanceof Element
      ? record.target
      : record.target?.parentElement;
    if (!target) return false;
    return Boolean(target.closest(COMPOSER_SELECTOR));
  }

  const observer = new MutationObserver((records) => {
    if (records.length > 0 && records.every(mutationIsInsideComposer)) {
      // The composer already uses dir=auto. Do not rescan and clone the full
      // conversation for every ProseMirror keystroke.
      processComposers();
      return;
    }
    schedule();
  });
  const observe = () => {
    if (observing || !document.documentElement) return;
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['dir', 'contenteditable', 'data-thread-title'],
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
      ensureInlineIslandsStyle();
      processTitles();
      processComposers();
      processUserMessageBubbles();
      processConversationRoots();
    } finally {
      applying = false;
      if (wasObserving) observe();
    }
  };

  const start = () => {
    disconnect();
    installLeftEdgeSidebarGuard();
    apply();
    observe();
  };

  window.__CODEX_RTL_FIX_CODEX = {
    apply,
    observer,
    classifyDirection
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
'@
}

function Get-CodexPlusPayloadBundle {
    @(
        Get-CodexRtlSharedPayload
        Get-CodexNewChatButtonPayload
        Get-CodexRtlPayload
        Get-CodexRtlPayloadPlan
        Get-CodexContextBadgePayload
        Get-CodexFullAccessReminderHiderPayload
        Get-CodexSplitModelEffortSelectorPayload
        Get-CodexProjectSelectorGuardPayload
        Get-CodexSidebarPagingPayload
        Get-CodexNewWindowButtonPayload
    ) -join "`n"
}
