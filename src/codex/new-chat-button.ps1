function Get-CodexNewChatButtonPayload {
    @'
(function () {
  const BUTTON_ATTR = 'data-codex-plus-new-chat-button';
  const NATIVE_NEW_CHAT_SELECTOR = 'button[aria-label="New chat"]';
  const COMPOSER_ACCESS_CELL_SELECTOR = 'div.col-start-1.row-start-2';
  const PROJECT_BUTTON_SELECTOR = 'button[aria-label^="Project:"], button[aria-label^="Change project:"]';
  const PROJECT_CHOOSER_SELECTOR = 'button[aria-label="Choose project"], button[data-composer-navigation-target="workspace-project"][aria-label="Choose project"]';
  const PROJECT_OPTION_SELECTOR = '[role="option"], [role="menuitem"]';
  const COMPOSER_ROOT_SELECTOR = '[data-codex-composer-root]';
  const COMPOSER_EDITOR_SELECTOR = 'div.ProseMirror[data-codex-composer="true"], div.ProseMirror';
  const UTILITY_BAR_SCROLL_SELECTOR = '[data-composer-utility-bar-scroll-area]';
  const PERSISTENT_UTILITY_BAR_ATTR = 'data-codex-plus-persistent-composer-utility-bar';
  const CONVERSATION_ID_ATTR = 'data-above-composer-conversation-id';
  const UTILITY_BAR_STORAGE_KEY = 'codex-plus-composer-utility-bars-v1';
  const MAX_STORED_UTILITY_BARS = 50;
  const RESTORE_TIMEOUT_MS = 15000;
  const RESTORE_POLL_INTERVAL_MS = 120;
  let pendingUtilityBarSnapshot = '';

  function normalizeText(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function hasInstalledButtons() {
    return Boolean(document.querySelector('[' + BUTTON_ATTR + ']'));
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
    snapshot.setAttribute('inert', '');
    snapshot.style.pointerEvents = 'none';
    snapshot.style.userSelect = 'none';
    snapshot.querySelectorAll('[id], [aria-controls], [aria-expanded], [data-state]')
      .forEach((element) => {
        element.removeAttribute('id');
        element.removeAttribute('aria-controls');
        element.removeAttribute('aria-expanded');
        element.removeAttribute('data-state');
      });
    snapshot.querySelectorAll('button, a, input, select, textarea, [tabindex]')
      .forEach((element) => element.setAttribute('tabindex', '-1'));
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
    if (!snapshotHtml) return;

    const persistentBar = utilityBarFromSnapshot(snapshotHtml);
    if (!persistentBar) return;
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
      .find((button) => isVisibleElement(button) && readProjectButtonName(button))
      || null;
  }

  function currentSidebarProjectName() {
    const activeThread = document.querySelector('[data-app-action-sidebar-thread-active="true"]');
    const projectRow = activeThread?.closest('[data-app-action-sidebar-project-row]')
      || Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]')).find((row) => row.querySelector('[data-app-action-sidebar-thread-active="true"]'));
    if (!projectRow) return '';

    const label = projectRow.getAttribute('data-app-action-sidebar-project-label')
      || projectRow.querySelector('[data-app-action-sidebar-project-label]')?.textContent
      || projectRow.textContent;
    return normalizeText(label);
  }

  function findProjectChooserButton() {
    return Array.from(document.querySelectorAll(PROJECT_CHOOSER_SELECTOR))
      .find((button) => isVisibleElement(button))
      || null;
  }

  function currentProjectName() {
    const directContext = normalizeText(window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.name);
    if (directContext) return directContext;

    const currentButton = findCurrentProjectButton();
    const selectedName = readProjectButtonName(currentButton);
    if (selectedName) return selectedName;
    if (findProjectChooserButton()) return '';
    return currentSidebarProjectName();
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

  function clearPendingContext() {
    if (window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT) {
      window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT = null;
    }
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
    const pending = window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT;
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
      window.__CODEX_PLUS_NEW_CHAT_BUTTON_PENDING_CONTEXT = context;
    }

    nativeButton.click();
    window.setTimeout(restorePendingNewChatContext, 0);
    window.setTimeout(restorePendingNewChatContext, 120);
    window.setTimeout(restorePendingNewChatContext, 400);
    return true;
  }

  function hideNativeComposerNewChatButton(row) {
    const nativeButton = row.querySelector('button[aria-label="New chat"]:not([' + BUTTON_ATTR + '])');
    if (!nativeButton) return;
    nativeButton.hidden = true;
    nativeButton.setAttribute('aria-hidden', 'true');
  }

  function placeNewChatButton(row, button) {
    const accessHost = getComposerAccessHost(row);
    if (!accessHost) {
      row.appendChild(button);
      return;
    }

    if (accessHost.nextElementSibling === button) return;
    row.insertBefore(button, accessHost.nextSibling);
  }

  function install() {
    installPersistentComposerUtilityBar();
    const row = findComposerAccessRow();
    if (!row) return;

    hideNativeComposerNewChatButton(row);
    const existingButton = row.querySelector('[' + BUTTON_ATTR + ']');
    if (existingButton) {
      placeNewChatButton(row, existingButton);
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
  }

  let installPending = false;
  const COMPOSER_SURFACE_SELECTOR = [
    COMPOSER_ACCESS_CELL_SELECTOR,
    '[' + BUTTON_ATTR + ']',
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
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  window.setInterval(install, 5000);
  window.setInterval(restorePendingNewChatContext, RESTORE_POLL_INTERVAL_MS);
})();
'@
}
