function Get-CodexProjectSelectorGuardPayload {
    @'
(function () {
  const existing = window.__CODEX_PLUS_PROJECT_SELECTOR_GUARD;
  if (existing && typeof existing.apply === 'function') return;

  const PROJECT_WINDOW_MARKER = 'data-codex-plus-project-window';
  const PROJECT_SELECTOR = 'button[data-composer-navigation-target="workspace-project"], button[aria-label^="Change project:"]';
  const EMPTY_PROJECT_SELECTOR = 'button[data-composer-navigation-target="workspace-project"][aria-label="Choose project"]';
  const CLEAR_PROJECT_SELECTOR = '[data-clear-project-button], button[aria-label="Don\'t work in a project"]';
  const PROJECT_WINDOW_CLEAR_SELECTOR = '[' + PROJECT_WINDOW_MARKER + '] [data-clear-project-button], [' + PROJECT_WINDOW_MARKER + '] button[aria-label="Don\'t work in a project"]';
  const LOCKED_ATTR = 'data-codex-plus-project-selector-locked';
  const PENDING_ATTR = 'data-codex-plus-project-selector-pending';
  const STYLE_ID = 'codex-plus-project-selector-guard-style';

  let pending = false;
  let pendingButton = null;
  let lastAttemptAt = 0;
  let scheduled = false;
  const ownedState = new WeakMap();

  function normalize(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function projectWindowContext() {
    if (!document.documentElement?.hasAttribute(PROJECT_WINDOW_MARKER)) return null;
    const direct = window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT;
    if (direct?.id && direct?.name) {
      return { id: normalize(direct.id), name: normalize(direct.name) };
    }

    const titleMatch = String(document.title || '').match(/^Codex Plus Project:\s*(.+)$/);
    const id = normalize(document.documentElement.getAttribute(PROJECT_WINDOW_MARKER));
    const name = normalize(titleMatch?.[1]);
    return id && name ? { id, name } : null;
  }

  function reactProps(element) {
    if (!element) return null;
    const key = Object.keys(element).find((candidate) => candidate.startsWith('__reactProps$'));
    return key ? element[key] : null;
  }

  function syntheticPointerEvent(element) {
    return {
      button: 0,
      ctrlKey: false,
      metaKey: false,
      shiftKey: false,
      altKey: false,
      defaultPrevented: false,
      currentTarget: element,
      target: element,
      preventDefault() { this.defaultPrevented = true; }
    };
  }

  function selectedProjectName(button) {
    const ariaLabel = normalize(button?.getAttribute('aria-label'));
    const ariaMatch = ariaLabel.match(/^Change project:\s*(.+)$/);
    if (ariaMatch) return normalize(ariaMatch[1]);
    const text = normalize(button?.innerText);
    return text === 'Choose project' ? '' : text;
  }

  function projectNames(context) {
    const names = [context?.name];
    const pathParts = normalize(context?.id).replace(/\\+/g, '/').split('/').filter(Boolean);
    if (pathParts.length) names.push(pathParts[pathParts.length - 1]);
    return Array.from(new Set(names.map(normalize).filter(Boolean)));
  }

  function menuItemForContext(context) {
    const names = projectNames(context);
    return Array.from(document.querySelectorAll('[role="menuitem"]')).find((item) => {
      const firstLine = normalize((item.innerText || '').split('\n')[0]);
      return names.some((name) => firstLine === name);
    }) || null;
  }

  function setPending(button) {
    if (!button) return;
    button.setAttribute(PENDING_ATTR, 'true');
    button.setAttribute('aria-disabled', 'true');
    button.tabIndex = -1;
  }

  function rememberState(button) {
    if (ownedState.has(button)) return;
    ownedState.set(button, {
      disabled: Boolean(button.disabled),
      tabIndex: button.getAttribute('tabindex'),
      ariaDisabled: button.getAttribute('aria-disabled')
    });
  }

  function lock(button) {
    if (!button) return;
    rememberState(button);
    button.disabled = true;
    button.setAttribute('aria-disabled', 'true');
    button.setAttribute(LOCKED_ATTR, 'true');
    button.removeAttribute(PENDING_ATTR);
    button.tabIndex = -1;
  }

  function unlock(button) {
    if (!button) return;
    const state = ownedState.get(button);
    button.removeAttribute(LOCKED_ATTR);
    button.removeAttribute(PENDING_ATTR);
    if (!state) return;
    button.disabled = state.disabled;
    if (state.ariaDisabled == null) button.removeAttribute('aria-disabled');
    else button.setAttribute('aria-disabled', state.ariaDisabled);
    if (state.tabIndex == null) button.removeAttribute('tabindex');
    else button.setAttribute('tabindex', state.tabIndex);
    ownedState.delete(button);
  }

  function selectCurrentProject(button, context) {
    if (pending || !button || !button.isConnected) return;
    if (Date.now() - lastAttemptAt < 1000) return;

    const props = reactProps(button);
    if (typeof props?.onPointerDown !== 'function') return;
    lastAttemptAt = Date.now();
    pending = true;
    pendingButton = button;
    setPending(button);

    try {
      props.onPointerDown(syntheticPointerEvent(button));
    } catch {
      pending = false;
      pendingButton = null;
      unlock(button);
      return;
    }

    window.setTimeout(() => {
      const item = menuItemForContext(context);
      if (item) {
        item.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
      }
      window.setTimeout(() => {
        const currentButton = pendingButton;
        pending = false;
        pendingButton = null;
        if (!currentButton || !currentButton.isConnected) return;
        if (selectedProjectName(currentButton) === normalize(context.name)) lock(currentButton);
        else unlock(currentButton);
        schedule();
      }, 120);
    }, 80);
  }

  function installStyle() {
    if (!document.head) return;
    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      document.head.appendChild(style);
    }
    style.textContent = [
      '[' + LOCKED_ATTR + '="true"],',
      '[' + PENDING_ATTR + '="true"] {',
      '  cursor: default !important;',
      '  opacity: 0.72 !important;',
      '  pointer-events: none !important;',
      '}',
      PROJECT_WINDOW_CLEAR_SELECTOR + ' {',
      '  cursor: default !important;',
      '  pointer-events: none !important;',
      '  display: none !important;',
      '}',
      EMPTY_PROJECT_SELECTOR + ' [data-tooltip-visibility-target="true"] {',
      '  font-size: 0 !important;',
      '}',
      EMPTY_PROJECT_SELECTOR + ' [data-tooltip-visibility-target="true"]::after {',
      '  content: "Task";',
      '  color: inherit;',
      '  font-size: 14px;',
      '  line-height: 18px;',
      '}'
    ].join('\n');
  }

  function isGuardedTarget(target) {
    const element = target instanceof Element
      ? target.closest('[' + LOCKED_ATTR + '="true"],[' + PENDING_ATTR + '="true"],' + CLEAR_PROJECT_SELECTOR)
      : null;
    return Boolean(element);
  }

  function apply() {
    installStyle();
    const context = projectWindowContext();
    const buttons = Array.from(document.querySelectorAll(PROJECT_SELECTOR));
    if (!context) {
      for (const button of buttons) unlock(button);
      return;
    }

    for (const button of buttons) {
      if (selectedProjectName(button) === normalize(context.name)) lock(button);
      else if (!pending) selectCurrentProject(button, context);
    }
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    window.setTimeout(() => {
      scheduled = false;
      apply();
    }, 40);
  }

  for (const eventType of ['pointerdown', 'click', 'keydown']) {
    document.addEventListener(eventType, (event) => {
      if (!projectWindowContext() || !isGuardedTarget(event.target)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    }, true);
  }

  const GUARD_SURFACE_SELECTOR = PROJECT_SELECTOR + ',' + CLEAR_PROJECT_SELECTOR + ',[role="menuitem"]';
  function mutationTouchesGuard(record) {
    if (record.type === 'attributes' && record.attributeName === PROJECT_WINDOW_MARKER) return true;
    const target = record.target instanceof Element
      ? record.target
      : record.target?.parentElement;
    if (target?.matches(GUARD_SURFACE_SELECTOR) || target?.closest(GUARD_SURFACE_SELECTOR)) return true;
    return [...Array.from(record.addedNodes || []), ...Array.from(record.removedNodes || [])].some((node) => {
      return node instanceof Element && (
        node.matches(GUARD_SURFACE_SELECTOR) || Boolean(node.querySelector(GUARD_SURFACE_SELECTOR))
      );
    });
  }

  const observer = new MutationObserver((records) => {
    if (records.some(mutationTouchesGuard)) schedule();
  });
  const start = () => {
    apply();
    if (document.documentElement) observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: [PROJECT_WINDOW_MARKER, 'aria-label'],
      childList: true,
      subtree: true
    });
    window.setInterval(schedule, 2000);
  };

  window.__CODEX_PLUS_PROJECT_SELECTOR_GUARD = { apply, observer };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
'@
}
