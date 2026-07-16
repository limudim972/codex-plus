function Get-CodexNewWindowButtonPayload {
    @'
(function () {
  const HEADER_SELECTOR = '.app-header-tint';
  const MENU_GROUP_SELECTOR = 'button[aria-label="Help"]';
  const BUTTON_ATTR = 'data-codex-plus-shared-window-button';

  function getMenuGroup() {
    const helpButton = document.querySelector(HEADER_SELECTOR + ' ' + MENU_GROUP_SELECTOR);
    return helpButton?.parentElement || null;
  }

  function launchSharedWindow() {
    const bridge = window.electronBridge?.sendMessageFromView;
    if (typeof bridge === 'function') {
      bridge({ type: 'open-in-new-window', path: '/' }).catch(() => {});
    }
  }

  function install() {
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
      try {
        launchSharedWindow();
      } finally {
        window.setTimeout(() => { button.disabled = false; }, 800);
      }
    });
    menuGroup.appendChild(button);
  }

  install();
  new MutationObserver(install).observe(document.documentElement, { childList: true, subtree: true });
})();
'@
}
