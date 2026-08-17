function Get-CodexNewChatButtonPayload {
    @'
(function () {
  const BUTTON_ATTR = 'data-codex-plus-new-chat-button';
  const COMMIT_PUSH_BUTTON_ATTR = 'data-codex-plus-commit-push-button';
  const COMMIT_PUSH_LABEL = 'Commit or push';
  const NATIVE_NEW_CHAT_SELECTOR = 'button[aria-label="New chat"]';
  const COMPOSER_ACCESS_CELL_SELECTOR = 'div.col-start-1.row-start-2';
  const PROJECT_BUTTON_SELECTOR = 'button[aria-label^="Project:"], button[aria-label^="Change project:"], button[aria-label="Choose project"]';
  const PROJECT_CHOOSER_SELECTOR = 'button[aria-label="Choose project"], button[data-composer-navigation-target="workspace-project"][aria-label="Choose project"]';
  const PROJECT_OPTION_SELECTOR = '[role="option"], [role="menuitem"]';
  const COMPOSER_ROOT_SELECTOR = '[data-codex-composer-root]';
  const COMPOSER_EDITOR_SELECTOR = 'div.ProseMirror[data-codex-composer="true"], div.ProseMirror';
  const UTILITY_BAR_SCROLL_SELECTOR = '[data-composer-utility-bar-scroll-area]';
  const PERSISTENT_UTILITY_BAR_ATTR = 'data-codex-plus-persistent-composer-utility-bar';
  const CONVERSATION_ID_ATTR = 'data-above-composer-conversation-id';
  const UTILITY_BAR_STORAGE_KEY = 'codex-plus-composer-utility-bars-v3';
  const PENDING_CONTEXT_STORAGE_KEY = 'codex-plus-new-chat-pending-context-v1';
  const MAX_STORED_UTILITY_BARS = 50;
  const RESTORE_TIMEOUT_MS = 15000;
  const RESTORE_POLL_INTERVAL_MS = 120;
  let pendingUtilityBarSnapshot = '';
  let persistentSnapshotRetryPending = false;
  let persistentSnapshotSignature = '';
  let persistentSnapshotStableSince = 0;
  let selectedThreadProjectName = '';
  let selectedThreadProjectKnown = false;
  let selectedThreadIsTask = false;
  let projectSelectionInFlight = '';
  let commitPushAvailabilityObserver = null;
  let observedNativeCommitPushButton = null;

  function normalizeText(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function hasInstalledButtons() {
    return Array.from(document.querySelectorAll('[' + BUTTON_ATTR + ']'))
      .some((candidate) => !candidate.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']'));
  }

  if (window.__CODEX_PLUS_NEW_CHAT_BUTTON && hasInstalledButtons()) return;

  function isElement(node) {
    return node instanceof Element;
  }

  function isVisibleElement(element) {
    return isElement(element) && element.getClientRects().length > 0;
  }

  function findVisibleButtonByLabel(ariaLabel) {
    return Array.from(document.querySelectorAll('button[aria-label="' + ariaLabel + '"]'))
      .filter(isVisibleElement)
      .reduce((selected, candidate) => {
        if (!selected) return candidate;
        return candidate.getBoundingClientRect().top >= selected.getBoundingClientRect().top
          ? candidate
          : selected;
      }, null);
  }

  function findVisibleCommitPushButton() {
    return Array.from(document.querySelectorAll('button'))
      .filter((candidate) => !candidate.hasAttribute(COMMIT_PUSH_BUTTON_ATTR))
      .filter((candidate) => !candidate.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']'))
      .find((candidate) => isVisibleElement(candidate) && normalizeText(candidate.textContent) === COMMIT_PUSH_LABEL)
      || null;
  }

  function isCommitPushButtonAvailable(nativeButton) {
    return Boolean(
      nativeButton
      && !nativeButton.disabled
      && normalizeText(nativeButton.getAttribute('aria-disabled')) !== 'true'
    );
  }

  function updateCommitPushButtonAvailability(button, nativeButton) {
    if (!isElement(button)) return;
    const disabled = !isCommitPushButtonAvailable(nativeButton);
    if (button.disabled !== disabled) button.disabled = disabled;
    if (disabled) {
      if (button.getAttribute('aria-disabled') !== 'true') button.setAttribute('aria-disabled', 'true');
    } else if (button.hasAttribute('aria-disabled')) {
      button.removeAttribute('aria-disabled');
    }
  }

  function observeNativeCommitPushButton(nativeButton) {
    if (nativeButton === observedNativeCommitPushButton) return;
    if (commitPushAvailabilityObserver) commitPushAvailabilityObserver.disconnect();
    commitPushAvailabilityObserver = null;
    observedNativeCommitPushButton = nativeButton || null;
    if (!nativeButton) return;

    commitPushAvailabilityObserver = new MutationObserver(syncCommitPushAvailability);
    commitPushAvailabilityObserver.observe(nativeButton, {
      attributes: true,
      attributeFilter: ['disabled', 'aria-disabled', 'class']
    });
  }

  function syncCommitPushAvailability() {
    const nativeButton = findVisibleCommitPushButton();
    observeNativeCommitPushButton(nativeButton);
    document.querySelectorAll('button[' + COMMIT_PUSH_BUTTON_ATTR + ']').forEach((button) => {
      updateCommitPushButtonAvailability(button, nativeButton);
    });
  }

  function isToggleOpen(button) {
    if (!isElement(button)) return false;
    if (normalizeText(button.getAttribute('aria-pressed')) === 'true') return true;
    if (normalizeText(button.getAttribute('data-state')) === 'open') return true;
    return normalizeText(button.closest('[data-state]')?.getAttribute('data-state')) === 'open';
  }

  function findBrowserWebview() {
    return Array.from(document.querySelectorAll('webview'))
      .find((candidate) => isVisibleElement(candidate) && getComputedStyle(candidate).visibility !== 'hidden')
      || document.querySelector('webview')
      || null;
  }

  function isBrowserWebviewOpen(webview) {
    return Boolean(
      webview
      && isVisibleElement(webview)
      && getComputedStyle(webview).visibility !== 'hidden'
      && !webview.classList.contains('invisible')
    );
  }

  function readBrowserWebviewSrc(webview) {
    return normalizeText(webview?.getAttribute('src') || webview?.src);
  }

  function findBrowserUrlInput() {
    return Array.from(document.querySelectorAll('input[placeholder="Enter a URL"]'))
      .find((candidate) => isVisibleElement(candidate))
      || null;
  }

  function pressBrowserAddressEnter(input) {
    if (!isElement(input)) return false;
    input.focus();
    const keyOptions = {
      bubbles: true,
      cancelable: true,
      key: 'Enter',
      code: 'Enter',
      which: 13,
      keyCode: 13
    };
    input.dispatchEvent(new KeyboardEvent('keydown', keyOptions));
    input.dispatchEvent(new KeyboardEvent('keypress', keyOptions));
    input.dispatchEvent(new KeyboardEvent('keyup', keyOptions));
    return true;
  }

  function findBrowserTabButton() {
    return Array.from(document.querySelectorAll('button'))
      .find((button) => {
        if (!isVisibleElement(button)) return false;
        const text = normalizeText(button.textContent);
        return /^Browser(?:\s|$)/.test(text) && !/^Browser options$/i.test(text);
      })
      || null;
  }

  function readBrowserUrl() {
    const browserUrlInput = findBrowserUrlInput();
    if (browserUrlInput) {
      return normalizeText(browserUrlInput.value || browserUrlInput.getAttribute('value'));
    }

    return readBrowserWebviewSrc(findBrowserWebview());
  }

  function hasClasses(element, classNames) {
    return isElement(element) && classNames.every((className) => element.classList.contains(className));
  }

  function isComposerAccessCell(element) {
    return hasClasses(element, ['min-w-0', 'col-start-1', 'row-start-2']);
  }

  function isComposerAccessRow(element) {
    return hasClasses(element, ['flex', 'min-w-0', 'items-center', 'gap-[5px]']);
  }

  function findComposerAccessCell() {
    return Array.from(document.querySelectorAll(COMPOSER_ACCESS_CELL_SELECTOR))
      .find(isComposerAccessCell)
      || null;
  }

  function findComposerAccessRow() {
    const accessCell = findComposerAccessCell();
    if (!accessCell) return null;
    return Array.from(accessCell.children).find(isComposerAccessRow) || null;
  }

  function getComposerAccessHost(row) {
    return Array.from(row.children)
      .find((candidate) => (candidate.textContent || '').trim() === 'Full access')
      || null;
  }

  function isInsideComposerAccessSurface(candidate) {
    return Boolean(candidate.closest(COMPOSER_ACCESS_CELL_SELECTOR));
  }

  function getNativeSidebarNewChatButton() {
    return Array.from(document.querySelectorAll(NATIVE_NEW_CHAT_SELECTOR))
      .find((candidate) => isVisibleElement(candidate) && !candidate.hasAttribute(BUTTON_ATTR) && !isInsideComposerAccessSurface(candidate))
      || null;
  }

  function findComposerRoot() {
    return Array.from(document.querySelectorAll(COMPOSER_ROOT_SELECTOR))
      .find((root) => isVisibleElement(root) && root.querySelector(COMPOSER_EDITOR_SELECTOR))
      || null;
  }

  function findComposerContentHost(root) {
    if (!isElement(root)) return null;
    return Array.from(root.children)
      .find((candidate) => candidate.querySelector(COMPOSER_EDITOR_SELECTOR))
      || null;
  }

  function findComposerUtilityBarRow(root) {
    if (!isElement(root)) return null;
    const scrollArea = Array.from(root.querySelectorAll(UTILITY_BAR_SCROLL_SELECTOR))
      .find((candidate) => !candidate.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']'));
    if (!scrollArea) return null;
    return isElement(scrollArea.firstElementChild) ? scrollArea.firstElementChild : null;
  }

  function findComposerUtilityBarAnchor(row) {
    if (!isElement(row)) return null;
    return Array.from(row.children)
      .find((candidate) => normalizeText(candidate.textContent) === 'main')
      || row.lastElementChild
      || null;
  }

  function getComposerUtilityBarSignature(wrapper) {
    if (!isElement(wrapper)) return '';
    const scrollArea = Array.from(wrapper.querySelectorAll(UTILITY_BAR_SCROLL_SELECTOR))
      .find((candidate) => !candidate.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']'));
    const row = scrollArea?.firstElementChild;
    if (!isElement(row)) return '';

    // The native row is assembled in stages. Do not cache the early state,
    // otherwise the persistent copy can permanently miss Local and branch.
    const projectButton = row.querySelector('button[data-composer-navigation-target="workspace-project"]');
    const locationButton = row.querySelector('[data-composer-navigation-target="run-location"]');
    const nativeNewChatButton = row.querySelector('button[aria-label="New chat"]:not([' + BUTTON_ATTR + '])');
    if (!projectButton || !locationButton || !nativeNewChatButton) return '';

    return Array.from(row.children)
      .map((child) => [
        child.getAttribute('data-composer-navigation-target') || '',
        child.getAttribute('aria-label') || '',
        normalizeText(child.textContent)
      ].join(':'))
      .join('|');
  }

  function isComposerUtilityBarReady(wrapper) {
    return Boolean(getComposerUtilityBarSignature(wrapper));
  }

  function retryPersistentUtilityBarSnapshot() {
    if (persistentSnapshotRetryPending) return;
    persistentSnapshotRetryPending = true;
    window.setTimeout(() => {
      persistentSnapshotRetryPending = false;
      installPersistentComposerUtilityBar();
    }, 160);
  }

  function currentComposerConversationId(root) {
    return normalizeText(root?.querySelector('[' + CONVERSATION_ID_ATTR + ']')?.getAttribute(CONVERSATION_ID_ATTR));
  }

  function readUtilityBarSnapshots() {
    try {
      const stored = JSON.parse(window.sessionStorage.getItem(UTILITY_BAR_STORAGE_KEY) || '{}');
      return stored && typeof stored === 'object' && !Array.isArray(stored) ? stored : {};
    } catch {
      return {};
    }
  }

  function writeUtilityBarSnapshots(snapshots) {
    try {
      const entries = Object.entries(snapshots)
        .sort((left, right) => Number(right[1]?.capturedAt || 0) - Number(left[1]?.capturedAt || 0))
        .slice(0, MAX_STORED_UTILITY_BARS);
      window.sessionStorage.setItem(UTILITY_BAR_STORAGE_KEY, JSON.stringify(Object.fromEntries(entries)));
    } catch {
    }
  }

  function createPersistentUtilityBarSnapshot(wrapper) {
    if (!isElement(wrapper)) return '';
    const snapshot = wrapper.cloneNode(true);
    snapshot.setAttribute(PERSISTENT_UTILITY_BAR_ATTR, 'true');
    snapshot.setAttribute('aria-label', 'Composer context');
    snapshot.style.userSelect = 'none';
    // This is a non-interactive copy of the native composer row. Remove the
    // native hover affordances from the copied project control only; the live
    // composer row below remains untouched and keeps its normal hover state.
    snapshot.querySelectorAll('[class]').forEach((element) => {
      Array.from(element.classList)
        .filter((className) => className.startsWith('hover:'))
        .forEach((className) => element.classList.remove(className));
    });
    snapshot.querySelectorAll('[data-tooltip-trigger], [data-tooltip-visibility-target], [title]')
      .forEach((element) => {
        element.removeAttribute('data-tooltip-trigger');
        element.removeAttribute('data-tooltip-visibility-target');
        element.removeAttribute('title');
      });
    snapshot.querySelectorAll('[id], [aria-controls], [aria-expanded], [data-state]')
      .forEach((element) => {
        element.removeAttribute('id');
        element.removeAttribute('aria-controls');
        element.removeAttribute('aria-expanded');
        element.removeAttribute('data-state');
      });
    snapshot.querySelectorAll('button, a, input, select, textarea, [tabindex]')
      .forEach((element) => element.setAttribute('tabindex', '-1'));
    snapshot.querySelectorAll('button, a, input, select, textarea')
      .forEach((element) => {
        if (element.hasAttribute(BUTTON_ATTR) || element.hasAttribute(COMMIT_PUSH_BUTTON_ATTR)) {
          element.style.pointerEvents = 'auto';
          element.removeAttribute('tabindex');
          return;
        }
        element.style.pointerEvents = 'none';
      });
    return snapshot.outerHTML;
  }

  function utilityBarFromSnapshot(snapshotHtml) {
    if (!normalizeText(snapshotHtml)) return null;
    const template = document.createElement('template');
    template.innerHTML = snapshotHtml;
    const utilityBar = template.content.firstElementChild;
    if (!isElement(utilityBar) || !utilityBar.hasAttribute(PERSISTENT_UTILITY_BAR_ATTR)) return null;
    return utilityBar;
  }

  function createFallbackUtilityBar() {
    const bar = document.createElement('div');
    bar.setAttribute(PERSISTENT_UTILITY_BAR_ATTR, 'true');
    bar.setAttribute('aria-label', 'Composer context');
    bar.className = 'z-0 relative -mb-2 flex min-w-0 items-center gap-1 rounded-t-3xl border border-b-0 border-token-border bg-token-main-surface-secondary px-4 py-2 text-base text-token-text-tertiary';
    const project = document.createElement('button');
    project.type = 'button';
    project.textContent = currentProjectName() || 'Choose project';
    project.setAttribute('aria-label', 'Change project: ' + project.textContent);
    project.setAttribute('data-composer-navigation-target', 'workspace-project');
    project.className = 'no-drag flex items-center gap-2 rounded-md border border-transparent px-1.5 py-1 text-base text-token-text-primary';
    project.style.pointerEvents = 'none';
    project.insertBefore(createProjectFolderIcon(), project.firstChild);
    const location = document.createElement('span');
    location.className = 'flex items-center gap-2 px-1.5 py-1 text-base text-token-text-primary';
    location.innerHTML = '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2.5" y="4.5" width="15" height="10.5" rx="1.5" stroke="currentColor" stroke-width="1.4"/><path d="M6 17h8" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg><span>Local</span>';
    const newChat = document.createElement('button');
    newChat.type = 'button';
    newChat.textContent = 'New chat';
    newChat.setAttribute(BUTTON_ATTR, 'true');
    newChat.setAttribute('aria-label', 'New chat');
    newChat.className = 'no-drag flex items-center gap-2 rounded-md border border-transparent px-2.5 py-1 text-base text-token-text-primary';
    newChat.appendChild(createNewChatIcon());
    const commit = document.createElement('button');
    commit.type = 'button';
    commit.textContent = 'Commit or push';
    commit.setAttribute(COMMIT_PUSH_BUTTON_ATTR, 'true');
    commit.setAttribute('aria-label', 'Commit or push');
    commit.className = 'no-drag ms-auto rounded-md border border-transparent px-2.5 py-1 text-sm text-token-text-primary';
    bar.append(project, location, newChat, commit);
    return bar;
  }

  function createProjectFolderIcon() {
    const template = document.createElement('span');
    template.innerHTML = '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" class="icon-sm shrink-0" aria-hidden="true"><path d="M2.5 5.83333C2.5 4.91286 3.24619 4.16667 4.16667 4.16667H8.33333L10 5.83333H15.8333C16.7538 5.83333 17.5 6.57953 17.5 7.5V14.1667C17.5 15.0871 16.7538 15.8333 15.8333 15.8333H4.16667C3.24619 15.8333 2.5 15.0871 2.5 14.1667V5.83333Z" stroke="currentColor" stroke-width="1.4"/></svg>';
    return template.firstElementChild;
  }

  function ensureProjectFolderIcon(bar) {
    const project = bar?.querySelector('button[aria-label^="Project:"], button[aria-label^="Change project:"]') || bar?.querySelector('button');
    if (project && !project.querySelector('svg')) project.insertBefore(createProjectFolderIcon(), project.firstChild);
  }

  function wirePersistentNewChatButton(bar) {
    if (!isElement(bar)) return;
    const button = bar.querySelector('button[' + BUTTON_ATTR + ']') || bar.querySelector('button[aria-label="New chat"]');
    if (!button) return;
    button.style.pointerEvents = 'auto';
    button.removeAttribute('tabindex');
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      triggerNewChat();
    });
  }

  function wirePersistentCommitPushButton(bar) {
    if (!isElement(bar)) return;
    const button = bar.querySelector('button[' + COMMIT_PUSH_BUTTON_ATTR + ']');
    if (!button) return;
    button.style.pointerEvents = 'auto';
    button.removeAttribute('tabindex');
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      triggerCommitOrPush();
    });
  }

  function installPersistentComposerUtilityBar() {
    const root = findComposerRoot();
    const host = findComposerContentHost(root);
    if (!root || !host) return;

    const nativeScrollArea = Array.from(root.querySelectorAll(UTILITY_BAR_SCROLL_SELECTOR))
      .find((candidate) => !candidate.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']'));
    const existingPersistentBars = Array.from(host.querySelectorAll(':scope > [' + PERSISTENT_UTILITY_BAR_ATTR + ']'));

    if (nativeScrollArea) {
      existingPersistentBars.forEach((bar) => bar.remove());
      const nativeWrapper = Array.from(host.children).find((candidate) => candidate.contains(nativeScrollArea));
      if (!isComposerUtilityBarReady(nativeWrapper)) {
        pendingUtilityBarSnapshot = '';
        persistentSnapshotSignature = '';
        persistentSnapshotStableSince = 0;
        retryPersistentUtilityBarSnapshot();
        return;
      }
      const snapshotSignature = getComposerUtilityBarSignature(nativeWrapper);
      if (snapshotSignature !== persistentSnapshotSignature) {
        persistentSnapshotSignature = snapshotSignature;
        persistentSnapshotStableSince = Date.now();
        retryPersistentUtilityBarSnapshot();
        return;
      }
      if (Date.now() - persistentSnapshotStableSince < 320) {
        retryPersistentUtilityBarSnapshot();
        return;
      }
      const snapshotHtml = createPersistentUtilityBarSnapshot(nativeWrapper);
      if (!snapshotHtml) return;

      pendingUtilityBarSnapshot = snapshotHtml;
      const conversationId = currentComposerConversationId(root);
      if (conversationId) {
        const snapshots = readUtilityBarSnapshots();
        snapshots[conversationId] = { html: snapshotHtml, capturedAt: Date.now() };
        writeUtilityBarSnapshots(snapshots);
      }
      return;
    }

    if (existingPersistentBars.length) return;

    const conversationId = currentComposerConversationId(root);
    const snapshots = readUtilityBarSnapshots();
    let snapshotHtml = normalizeText(snapshots[conversationId]?.html);
    if (!snapshotHtml && pendingUtilityBarSnapshot) {
      snapshotHtml = pendingUtilityBarSnapshot;
      if (conversationId) {
        snapshots[conversationId] = { html: snapshotHtml, capturedAt: Date.now() };
        writeUtilityBarSnapshots(snapshots);
      }
    }
    if (!snapshotHtml) {
      const fallbackBar = createFallbackUtilityBar();
      ensureProjectFolderIcon(fallbackBar);
      wirePersistentNewChatButton(fallbackBar);
      wirePersistentCommitPushButton(fallbackBar);
      host.insertBefore(fallbackBar, host.firstElementChild);
      return;
    }

    const persistentBar = utilityBarFromSnapshot(snapshotHtml);
    if (!persistentBar) return;
    ensureProjectFolderIcon(persistentBar);
    wirePersistentNewChatButton(persistentBar);
    wirePersistentCommitPushButton(persistentBar);
    host.insertBefore(persistentBar, host.firstElementChild);
  }

  function createNewChatIcon() {
    const nativeIcon = getNativeSidebarNewChatButton()?.querySelector('svg');
    if (nativeIcon) {
      const icon = nativeIcon.cloneNode(true);
      if (icon?.classList) {
        icon.classList.add('shrink-0');
      }
      return icon;
    }

    const template = document.createElement('span');
    template.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" class="icon-xs shrink-0"><path d="M6.33325 1.88379C6.58178 1.88379 6.78345 2.08546 6.78345 2.33398C6.78328 2.58237 6.58168 2.78418 6.33325 2.78418H4.66626C3.62638 2.78435 2.78362 3.62711 2.78345 4.66699V11.334C2.78361 12.3739 3.62637 13.2176 4.66626 13.2178H11.3333C12.3733 13.2178 13.2169 12.374 13.217 11.334V9.66699C13.2172 9.41872 13.418 9.21795 13.6663 9.21777C13.9147 9.21777 14.1163 9.41861 14.1165 9.66699V11.334C14.1163 12.871 12.8703 14.1172 11.3333 14.1172H4.66626C3.12932 14.117 1.88322 12.8709 1.88306 11.334V4.66699C1.88323 3.13006 3.12933 1.88396 4.66626 1.88379H6.33325Z" fill="currentColor"></path><path fill-rule="evenodd" clip-rule="evenodd" d="M10.8948 2.375C11.6494 1.63227 12.8628 1.63698 13.6116 2.38574C14.362 3.13643 14.3637 4.35266 13.6165 5.10644L9.36353 9.39355C9.01402 9.74579 8.56977 9.98985 8.08521 10.0967L6.17603 10.5166C5.74813 10.6107 5.36686 10.2296 5.46118 9.80176L5.88208 7.89746C5.98978 7.4105 6.23578 6.96428 6.59106 6.61426L10.8948 2.375ZM12.9749 3.02148C12.5756 2.62258 11.9289 2.62086 11.5266 3.0166L7.2229 7.25586C6.99148 7.4839 6.83116 7.77457 6.76099 8.0918L6.44165 9.53711L7.89185 9.21777C8.20744 9.14811 8.49721 8.98919 8.72485 8.75976L12.9778 4.47266C13.3759 4.07066 13.375 3.42164 12.9749 3.02148Z" fill="currentColor"></path></svg>';
    return template.firstElementChild;
  }

  function createCommitPushIcon() {
    const nativeIcon = findVisibleCommitPushButton()?.querySelector('svg');
    if (nativeIcon) {
      const icon = nativeIcon.cloneNode(true);
      icon.classList.add('shrink-0');
      return icon;
    }

    const template = document.createElement('span');
    template.innerHTML = '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" class="icon-sm shrink-0" aria-hidden="true"><path d="M13.5013 10.0003C13.5013 8.06653 11.9341 6.49856 10.0003 6.49838C8.06641 6.49838 6.49837 8.06642 6.49837 10.0003C6.49855 11.9341 8.06652 13.5013 10.0003 13.5013C11.934 13.5011 13.5011 11.934 13.5013 10.0003ZM14.8314 10.0003C14.8312 12.6685 12.6685 14.8312 10.0003 14.8314C7.33198 14.8314 5.16847 12.6686 5.16829 10.0003C5.16829 7.33188 7.33187 5.1683 10.0003 5.1683C12.6686 5.16848 14.8314 7.33199 14.8314 10.0003Z" fill="currentColor"></path><path d="M5 9.33497C5.36727 9.33497 5.66504 9.63274 5.66504 10C5.66504 10.3673 5.36727 10.665 5 10.665H1.25C0.882731 10.665 0.584961 10.3673 0.584961 10C0.584961 9.63274 0.882731 9.33497 1.25 9.33497H5Z" fill="currentColor"></path><path d="M18.75 9.33497C19.1173 9.33497 19.415 9.63274 19.415 10C19.415 10.3673 19.117 10.665 18.75 10.665H15C14.6327 10.665 14.335 10.3673 14.335 10C14.335 9.63274 14.6327 9.33497 15 9.33497H18.75Z" fill="currentColor"></path></svg>';
    return template.firstElementChild;
  }

  function readProjectButtonName(button) {
    const ariaLabel = normalizeText(button?.getAttribute('aria-label'));
    const ariaMatch = ariaLabel.match(/^(?:Project|Change project):\s*(.+)$/);
    if (ariaMatch) return normalizeText(ariaMatch[1]);
    if (ariaLabel === 'Choose project') return '';
    const text = normalizeText(button?.textContent);
    if (text === 'Choose project') return '';
    const textMatch = text.match(/^(?:Project|Change project):\s*(.+)$/);
    if (textMatch) return normalizeText(textMatch[1]);
    return text;
  }

  function findCurrentProjectButton() {
    return Array.from(document.querySelectorAll(PROJECT_BUTTON_SELECTOR))
      .find((button) => isVisibleElement(button)
        && !button.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']')
        && getComputedStyle(button).pointerEvents !== 'none'
        && readProjectButtonName(button))
      || null;
  }

  function currentSidebarProjectName() {
    const activeThread = document.querySelector('[data-app-action-sidebar-thread-active]:not([data-app-action-sidebar-thread-active="false"])');
    const projectRow = activeThread?.closest('[data-app-action-sidebar-project-row]')
      || Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]')).find((row) => row.querySelector('[data-app-action-sidebar-thread-active]:not([data-app-action-sidebar-thread-active="false"])'));
    if (!projectRow) return '';

    const label = projectRow.getAttribute('data-app-action-sidebar-project-label')
      || projectRow.querySelector('[data-app-action-sidebar-project-label]')?.textContent
      || projectRow.textContent;
    return normalizeText(label);
  }

  function findProjectChooserButton() {
    return Array.from(document.querySelectorAll(PROJECT_CHOOSER_SELECTOR))
      .find((button) => isVisibleElement(button)
        && !button.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']')
        && getComputedStyle(button).pointerEvents !== 'none')
      || null;
  }

  function currentProjectName() {
    const directContext = normalizeText(window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.name);
    if (directContext) return directContext;

    const activeSyntheticThread = document.querySelector('[data-codex-plus-sidebar-synthetic-row="threads"][data-app-action-sidebar-thread-active="true"]');
    if (activeSyntheticThread) {
      const activeProjectName = normalizeText(activeSyntheticThread.getAttribute('data-codex-plus-thread-project-title'));
      if (activeProjectName) return activeProjectName;
      if (normalizeText(activeSyntheticThread.getAttribute('data-codex-plus-source-list-label')) === 'Tasks') return '';
    }

    const currentButton = findCurrentProjectButton();
    const selectedName = readProjectButtonName(currentButton);
    if (selectedName) return selectedName;
    if (findProjectChooserButton()) return '';

    if (selectedThreadProjectKnown && selectedThreadIsTask) return '';
    if (selectedThreadProjectKnown) return selectedThreadProjectName;

    const sidebarProject = currentSidebarProjectName();
    if (sidebarProject) return sidebarProject;

    return '';
  }

  function syncPersistentProjectLabels() {
    const projectName = normalizeText(currentProjectName());
    const label = projectName || (selectedThreadIsTask ? 'Task' : 'Choose project');
    for (const button of document.querySelectorAll(PROJECT_BUTTON_SELECTOR)) {
      const value = button.querySelector('[data-tooltip-overflow-target]') || button.querySelector('._dropdownLabelValueContent_2l838_2');
      if (value) value.textContent = label;
      else if (button.closest('[' + PERSISTENT_UTILITY_BAR_ATTR + ']')) button.textContent = label;
      button.setAttribute('aria-label', projectName ? 'Change project: ' + projectName : (selectedThreadIsTask ? 'Task' : 'Choose project'));
    }
  }

  function rememberSyntheticThreadProject(event) {
    const row = event.target instanceof Element
      ? event.target.closest('[data-codex-plus-sidebar-synthetic-row="threads"][data-codex-plus-thread-project-title]')
      : null;
    if (!row) return;
    const projectName = normalizeText(row.getAttribute('data-codex-plus-thread-project-title'));
    selectedThreadProjectKnown = true;
    selectedThreadProjectName = projectName;
    selectedThreadIsTask = !projectName;
    if (projectName) {
      window.setTimeout(() => selectComposerProject(projectName), 120);
    } else {
      window.setTimeout(clearComposerProject, 120);
    }
    window.setTimeout(syncPersistentProjectLabels, 120);
  }

  function syncSelectedThreadFromDom() {
    const row = document.querySelector('[data-codex-plus-sidebar-synthetic-row="threads"][data-app-action-sidebar-thread-active="true"]');
    if (!row) return;
    const projectName = normalizeText(row.getAttribute('data-codex-plus-thread-project-title'));
    const isTask = !projectName && normalizeText(row.getAttribute('data-codex-plus-source-list-label')) === 'Tasks';
    const currentButton = findCurrentProjectButton();
    const currentName = readProjectButtonName(currentButton);
    const needsProjectSelection = Boolean(projectName && (!currentButton || currentName !== projectName));
    const threadStateUnchanged = selectedThreadProjectKnown
      && selectedThreadIsTask === isTask
      && selectedThreadProjectName === projectName;
    if (threadStateUnchanged && !needsProjectSelection) return;
    selectedThreadProjectKnown = true;
    selectedThreadIsTask = isTask;
    selectedThreadProjectName = projectName;
    syncPersistentProjectLabels();
    if (projectName && needsProjectSelection) {
      window.setTimeout(() => selectComposerProject(projectName), 120);
    } else if (isTask && !currentButton) {
      window.setTimeout(clearComposerProject, 120);
    }
  }

  function selectComposerProject(projectName) {
    const target = normalizeText(projectName);
    // Existing threads can render the composer in its blank/Choose project
    // state even though the active sidebar thread already has a project.
    // In that state there is no current-project button, so open the chooser
    // itself and select the matching project option.
    if (!target || projectSelectionInFlight === target) return;
    const button = findCurrentProjectButton() || findProjectChooserButton();
    if (!button || readProjectButtonName(button) === target) return;
    projectSelectionInFlight = target;
    button.click();
    const chooseProjectOption = () => {
      const option = Array.from(document.querySelectorAll(PROJECT_OPTION_SELECTOR)).find((candidate) => {
        return isVisibleElement(candidate)
          && normalizeText((candidate.textContent || '').split('\n')[0]) === target;
      });
      if (option) {
        option.click();
        projectSelectionInFlight = '';
        window.setTimeout(syncPersistentProjectLabels, 120);
        return;
      }
      if (projectSelectionInFlight !== target) return;
      if (Date.now() < chooseProjectOption.expiresAt) {
        window.setTimeout(chooseProjectOption, 100);
      } else {
        projectSelectionInFlight = '';
      }
    };
    chooseProjectOption.expiresAt = Date.now() + 2000;
    window.setTimeout(chooseProjectOption, 80);
  }

  function clearComposerProject() {
    const button = findCurrentProjectButton();
    if (!button || readProjectButtonName(button) === '') return;
    button.click();
    window.setTimeout(() => {
      const clear = document.querySelector('[data-clear-project-button], button[aria-label="Don\'t work in a project"]');
      clear?.click();
      window.setTimeout(syncPersistentProjectLabels, 120);
    }, 80);
  }

  function getSplitController() {
    return window.__CODEX_PLUS_SPLIT_MODEL_EFFORT_SELECTOR?.getController?.(document.querySelector('[data-codex-intelligence-trigger="true"]')) || null;
  }

  function getVisibleModels(controller) {
    return (controller?.models || []).filter((model) => !model.hidden);
  }

  function getEfforts(model) {
    return (model && Array.isArray(model.supportedReasoningEfforts) ? model.supportedReasoningEfforts : [])
      .map((entry) => typeof entry === 'string' ? entry : entry.reasoningEffort)
      .filter(Boolean);
  }

  function findModel(controller, modelName) {
    const target = normalizeText(modelName);
    if (!target) return null;
    return getVisibleModels(controller).find((candidate) => {
      return [
        candidate.model,
        candidate.id,
        candidate.displayName
      ].map(normalizeText).some((value) => value === target);
    }) || null;
  }

  function captureCurrentChatContext() {
    const controller = getSplitController();
    const selectedModel = controller ? findModel(controller, controller.model) : null;
    const model = normalizeText(controller?.model || selectedModel?.model || selectedModel?.id);
    const reasoningEffort = normalizeText(controller?.reasoningEffort || selectedModel?.defaultReasoningEffort || '');
    const projectName = normalizeText(window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.name || currentProjectName());
    const sidePanelOpen = isToggleOpen(findVisibleButtonByLabel('Toggle side panel'));
    const browserUrlInput = findBrowserUrlInput();
    const browserTabButton = findBrowserTabButton();
    const browserOptionsButton = findVisibleButtonByLabel('Browser options');
    const browserWebview = findBrowserWebview();
    const browserPanelOpen = Boolean(browserUrlInput || browserTabButton || browserOptionsButton || isBrowserWebviewOpen(browserWebview));
    const browserSrc = browserPanelOpen ? readBrowserUrl() : '';
    if (!projectName && !model && !reasoningEffort && !sidePanelOpen && !browserPanelOpen && !browserSrc) return null;

    const createdAt = Date.now();
    return {
      projectName,
      model,
      reasoningEffort,
      sidePanelOpen,
      browserPanelOpen,
      browserSrc,
      createdAt,
      expiresAt: createdAt + RESTORE_TIMEOUT_MS,
      projectMenuOpenedAt: 0,
      projectSelectionAttemptedAt: 0,
      sidePanelToggleAttemptedAt: 0,
      browserPanelToggleAttemptedAt: 0,
      browserSrcAttemptedAt: 0,
      modelSelectionAttemptedAt: 0,
      effortSelectionAttemptedAt: 0
    };
  }

  function setPendingContext(context) {
    window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT = context || null;
    try {
      if (context) sessionStorage.setItem(PENDING_CONTEXT_STORAGE_KEY, JSON.stringify(context));
      else sessionStorage.removeItem(PENDING_CONTEXT_STORAGE_KEY);
    } catch {
    }
  }

  function readPendingContext() {
    if (window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT) {
      return window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT;
    }
    try {
      const stored = sessionStorage.getItem(PENDING_CONTEXT_STORAGE_KEY);
      if (!stored) return null;
      const context = JSON.parse(stored);
      window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT = context;
      return context;
    } catch {
      return null;
    }
  }

  function clearPendingContext() {
    setPendingContext(null);
  }

  function getProjectOption(projectName) {
    const target = normalizeText(projectName);
    if (!target) return null;
    return Array.from(document.querySelectorAll(PROJECT_OPTION_SELECTOR))
      .find((item) => {
        if (!isVisibleElement(item)) return false;
        const firstLine = normalizeText((item.innerText || item.textContent || '').split('\n')[0]);
        return firstLine === target;
      })
      || null;
  }

  function restoreProjectSelection(pending, now) {
    const targetProjectName = normalizeText(pending?.projectName);
    if (!targetProjectName) return false;
    const currentName = normalizeText(currentProjectName());
    if (currentName === targetProjectName) return false;

    const option = getProjectOption(targetProjectName);
    if (option) {
      if (!pending.projectSelectionAttemptedAt || now - pending.projectSelectionAttemptedAt >= 1000) {
        pending.projectSelectionAttemptedAt = now;
        pending.projectMenuOpenedAt = 0;
        option.click();
      }
      return true;
    }

    if (pending.projectSelectionAttemptedAt && now - pending.projectSelectionAttemptedAt < 1000) return true;

    const chooser = findProjectChooserButton();
    if (chooser && (!pending.projectMenuOpenedAt || now - pending.projectMenuOpenedAt >= 2000)) {
      pending.projectMenuOpenedAt = now;
      chooser.click();
    }
    return true;
  }

  function restoreModelSelection(pending, now) {
    const targetModelName = normalizeText(pending?.model);
    const targetEffort = normalizeText(pending?.reasoningEffort);
    if (!targetModelName && !targetEffort) {
      return false;
    }

    const controller = getSplitController();
    if (!controller) return true;

    const currentModelName = normalizeText(controller.model);
    const currentEffort = normalizeText(controller.reasoningEffort);

    if (!targetModelName) {
      if (targetEffort && !controller.reasoningEffortDisabled && currentEffort !== targetEffort) {
        if (pending.effortSelectionAttemptedAt && now - pending.effortSelectionAttemptedAt < 1000) return true;
        pending.effortSelectionAttemptedAt = now;
        controller.onSelectReasoningEffort(targetEffort);
        return true;
      }
      return false;
    }

    const selectedModel = findModel(controller, targetModelName);
    if (!selectedModel) return true;

    const selectedModelName = normalizeText(selectedModel.model || selectedModel.id);
    const modelMatches = currentModelName === selectedModelName;
    const effortMatches = !targetEffort || currentEffort === targetEffort;
    if (modelMatches && effortMatches) {
      return false;
    }

    if (modelMatches) {
      if (targetEffort && !controller.reasoningEffortDisabled && currentEffort !== targetEffort) {
        if (pending.effortSelectionAttemptedAt && now - pending.effortSelectionAttemptedAt < 1000) return true;
        pending.effortSelectionAttemptedAt = now;
        controller.onSelectReasoningEffort(targetEffort);
      }
      return true;
    }

    if (pending.modelSelectionAttemptedAt && now - pending.modelSelectionAttemptedAt < 1000) return true;
    const efforts = getEfforts(selectedModel);
    const nextEffort = targetEffort && efforts.includes(targetEffort)
      ? targetEffort
      : (selectedModel.defaultReasoningEffort || efforts[0] || targetEffort || '');
    pending.modelSelectionAttemptedAt = now;
    controller.onSelectModel(selectedModel.model || selectedModel.id, nextEffort);
    return true;
  }

  function restoreSidePanelState(pending, now) {
    if (!pending?.sidePanelOpen) return false;
    const sidePanelButton = findVisibleButtonByLabel('Toggle side panel');
    if (!sidePanelButton) return true;
    if (isToggleOpen(sidePanelButton)) return false;
    if (pending.sidePanelToggleAttemptedAt && now - pending.sidePanelToggleAttemptedAt < 1000) return true;
    pending.sidePanelToggleAttemptedAt = now;
    sidePanelButton.click();
    return true;
  }

  function restoreBrowserPanelState(pending, now) {
    if (!pending?.browserPanelOpen) return false;

    const browserTabButton = findBrowserTabButton();
    const browserUrlInput = findBrowserUrlInput();
    const browserOptionsButton = findVisibleButtonByLabel('Browser options');
    const browserWebview = findBrowserWebview();
    const browserOpen = Boolean(browserUrlInput || browserOptionsButton || isBrowserWebviewOpen(browserWebview));

    if (!browserOpen) {
      if (!browserTabButton) return true;
      if (pending.browserPanelToggleAttemptedAt && now - pending.browserPanelToggleAttemptedAt < 1000) return true;
      pending.browserPanelToggleAttemptedAt = now;
      browserTabButton.click();
      return true;
    }

    const browserSrc = normalizeText(pending.browserSrc);
    if (!browserSrc) return false;

    if (browserUrlInput) {
      const currentValue = normalizeText(browserUrlInput.value || browserUrlInput.getAttribute('value'));
      if (currentValue !== browserSrc) {
        if (pending.browserSrcAttemptedAt && now - pending.browserSrcAttemptedAt < 1000) return true;
        pending.browserSrcAttemptedAt = now;
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
        if (setter) {
          setter.call(browserUrlInput, browserSrc);
        } else {
          browserUrlInput.value = browserSrc;
        }
        browserUrlInput.dispatchEvent(new Event('input', { bubbles: true }));
        browserUrlInput.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      }

      if (!isBrowserWebviewOpen(browserWebview)) {
        if (pending.browserPanelToggleAttemptedAt && now - pending.browserPanelToggleAttemptedAt < 1000) return true;
        pending.browserPanelToggleAttemptedAt = now;
        pressBrowserAddressEnter(browserUrlInput);
        return true;
      }
    }

    if (!browserWebview) return false;

    const currentSrc = readBrowserWebviewSrc(browserWebview);
    if (currentSrc === browserSrc) return false;
    if (pending.browserSrcAttemptedAt && now - pending.browserSrcAttemptedAt < 1000) return true;
    pending.browserSrcAttemptedAt = now;
    browserWebview.setAttribute('src', browserSrc);
    return true;
  }

  function isPendingNewChatContextSatisfied(pending) {
    const targetProjectName = normalizeText(pending?.projectName);
    if (targetProjectName && normalizeText(currentProjectName()) !== targetProjectName) return false;

    const targetModelName = normalizeText(pending?.model);
    const targetEffort = normalizeText(pending?.reasoningEffort);
    if (targetModelName || targetEffort) {
      const controller = getSplitController();
      if (!controller) return false;

      if (targetModelName) {
        const selectedModel = findModel(controller, targetModelName);
        if (!selectedModel) return false;

        const selectedModelName = normalizeText(selectedModel.model || selectedModel.id);
        if (normalizeText(controller.model) !== selectedModelName) return false;
      }

      if (targetEffort && normalizeText(controller.reasoningEffort) !== targetEffort) return false;
    }

    if (pending?.sidePanelOpen) {
      if (!isToggleOpen(findVisibleButtonByLabel('Toggle side panel'))) return false;
    }

    if (pending?.browserPanelOpen) {
      const browserUrlInput = findBrowserUrlInput();
      const browserTabButton = findBrowserTabButton();
      const browserOptionsButton = findVisibleButtonByLabel('Browser options');
      const browserWebview = findBrowserWebview();
      if (!(browserUrlInput || browserTabButton || browserOptionsButton || isBrowserWebviewOpen(browserWebview))) return false;

      const browserSrc = normalizeText(pending?.browserSrc);
      if (browserSrc) {
        const currentBrowserSrc = browserUrlInput
          ? normalizeText(browserUrlInput.value || browserUrlInput.getAttribute('value'))
          : readBrowserWebviewSrc(browserWebview);
        if (currentBrowserSrc !== browserSrc) return false;
        if (browserUrlInput && !isBrowserWebviewOpen(browserWebview)) return false;
      }
    }

    return true;
  }

  function restorePendingNewChatContext() {
    const pending = readPendingContext();
    if (!pending) return false;
    if (Date.now() > Number(pending.expiresAt || 0)) {
      clearPendingContext();
      return false;
    }

    const now = Date.now();
    const targetProjectName = normalizeText(pending.projectName);
    if (targetProjectName && normalizeText(currentProjectName()) !== targetProjectName) {
      if (restoreProjectSelection(pending, now)) return true;
    }

    if (restoreSidePanelState(pending, now)) return true;
    if (restoreBrowserPanelState(pending, now)) return true;
    if (restoreModelSelection(pending, now)) return true;

    if (isPendingNewChatContextSatisfied(pending)) {
      clearPendingContext();
      return false;
    }

    return true;
  }

  function triggerNewChat() {
    const nativeButton = getNativeSidebarNewChatButton();
    if (!nativeButton) return false;

    const context = captureCurrentChatContext();
    if (context) {
      setPendingContext(context);
    } else {
      clearPendingContext();
    }

    nativeButton.click();
    window.setTimeout(restorePendingNewChatContext, 0);
    window.setTimeout(restorePendingNewChatContext, 120);
    window.setTimeout(restorePendingNewChatContext, 400);
    return true;
  }

  function triggerCommitOrPush() {
    const nativeButton = findVisibleCommitPushButton();
    if (nativeButton) {
      if (!isCommitPushButtonAvailable(nativeButton)) return false;
      nativeButton.click();
      return true;
    }

    const panelToggle = findVisibleButtonByLabel('Toggle bottom panel');
    if (!panelToggle) return false;
    if (!isToggleOpen(panelToggle)) panelToggle.click();

    const retry = () => {
      const nextButton = findVisibleCommitPushButton();
      if (nextButton) nextButton.click();
    };
    window.setTimeout(retry, 0);
    window.setTimeout(retry, 120);
    window.setTimeout(retry, 400);
    return true;
  }

  function hideNativeComposerNewChatButton(row) {
    const nativeButton = row.querySelector('button[aria-label="New chat"]:not([' + BUTTON_ATTR + '])');
    if (!nativeButton) return;
    nativeButton.hidden = true;
    nativeButton.setAttribute('aria-hidden', 'true');
  }

  function placeNewChatButton(row, button) {
    const anchor = findComposerUtilityBarAnchor(row);
    if (!anchor) {
      row.appendChild(button);
      return;
    }

    if (anchor.nextElementSibling === button) return;
    row.insertBefore(button, anchor.nextSibling);
  }

  function placeCommitPushButton(row, button) {
    button.style.marginInlineStart = 'auto';
    const newChatButton = row.querySelector('button[' + BUTTON_ATTR + ']');
    if (newChatButton) {
      if (newChatButton.nextElementSibling !== button) {
        row.insertBefore(button, newChatButton.nextSibling);
      }
      return;
    }

    const anchor = findComposerUtilityBarAnchor(row);
    if (!anchor) {
      row.appendChild(button);
      return;
    }

    if (anchor.nextElementSibling !== button) row.insertBefore(button, anchor.nextSibling);
  }

  function installCommitPushButton(row) {
    const existingButton = row.querySelector('button[' + COMMIT_PUSH_BUTTON_ATTR + ']');
    if (!normalizeText(currentProjectName())) {
      existingButton?.remove();
      return;
    }

    if (existingButton) {
      placeCommitPushButton(row, existingButton);
      return;
    }

    const button = document.createElement('button');
    button.type = 'button';
    button.setAttribute(COMMIT_PUSH_BUTTON_ATTR, 'true');
    button.setAttribute('aria-label', COMMIT_PUSH_LABEL);
    button.title = COMMIT_PUSH_LABEL;
    button.className = 'no-drag rounded-md border border-transparent px-2.5 py-1 text-base font-normal leading-none outline-none transition-colors text-token-text-primary hover:bg-token-foreground/5 hover:text-token-foreground focus-visible:bg-token-foreground/5 focus-visible:text-token-foreground disabled:cursor-not-allowed disabled:opacity-40 disabled:text-token-text-secondary flex items-center gap-2 whitespace-nowrap';
    button.style.marginInlineStart = 'auto';

    const icon = createCommitPushIcon();
    if (icon) button.appendChild(icon);

    const label = document.createElement('span');
    label.textContent = COMMIT_PUSH_LABEL;
    button.appendChild(label);

    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      triggerCommitOrPush();
    });

    placeCommitPushButton(row, button);
  }

  function install() {
    syncSelectedThreadFromDom();
    const root = findComposerRoot();
    if (!root) return;

    const accessRow = findComposerAccessRow();
    if (accessRow) {
      hideNativeComposerNewChatButton(accessRow);
    }

    const row = findComposerUtilityBarRow(root);
    if (!row) {
      installPersistentComposerUtilityBar();
      syncCommitPushAvailability();
      return;
    }

    const existingButton = row.querySelector('[' + BUTTON_ATTR + ']');
    if (existingButton) {
      placeNewChatButton(row, existingButton);
      installCommitPushButton(row);
      syncCommitPushAvailability();
      installPersistentComposerUtilityBar();
      return;
    }

    const button = document.createElement('button');
    button.type = 'button';
    button.setAttribute(BUTTON_ATTR, 'true');
    button.setAttribute('aria-label', 'New chat');
    button.title = 'Start a new chat';
    button.className = 'no-drag rounded-md border border-transparent px-2.5 py-1 text-base font-normal leading-none outline-none transition-colors text-token-text-primary hover:bg-token-foreground/5 hover:text-token-foreground focus-visible:bg-token-foreground/5 focus-visible:text-token-foreground flex items-center gap-2 whitespace-nowrap';

    const icon = createNewChatIcon();
    if (icon) {
      icon.setAttribute('aria-hidden', 'true');
      button.appendChild(icon);
    }

    const label = document.createElement('span');
    label.textContent = 'New chat';
    button.appendChild(label);

    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      triggerNewChat();
    });

    placeNewChatButton(row, button);
    installCommitPushButton(row);
    syncCommitPushAvailability();
    installPersistentComposerUtilityBar();
  }

  let installPending = false;
  const COMPOSER_SURFACE_SELECTOR = [
    COMPOSER_ACCESS_CELL_SELECTOR,
    '[' + BUTTON_ATTR + ']',
    '[' + COMMIT_PUSH_BUTTON_ATTR + ']',
    NATIVE_NEW_CHAT_SELECTOR
  ].join(',');

  const schedule = () => {
    if (installPending) return;
    installPending = true;
    window.setTimeout(() => {
      installPending = false;
      install();
    }, 80);
  };

  install();
  window.__CODEX_PLUS_NEW_CHAT_BUTTON = true;
  document.addEventListener('click', rememberSyntheticThreadProject, true);
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  window.setInterval(install, 5000);
  window.setInterval(restorePendingNewChatContext, RESTORE_POLL_INTERVAL_MS);
})();
'@
}
