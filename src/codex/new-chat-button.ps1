function Get-CodexNewChatButtonPayload {
    @'
(function () {
  const BUTTON_ATTR = 'data-codex-plus-new-chat-button';
  const NATIVE_NEW_CHAT_SELECTOR = 'button[aria-label="New chat"]';
  const COMPOSER_ACCESS_CELL_SELECTOR = 'div.col-start-1.row-start-2';
  const PROJECT_BUTTON_SELECTOR = 'button[aria-label^="Project:"], button[aria-label^="Change project:"]';
  const PROJECT_CHOOSER_SELECTOR = 'button[aria-label="Choose project"], button[data-composer-navigation-target="workspace-project"][aria-label="Choose project"]';
  const PROJECT_OPTION_SELECTOR = '[role="option"], [role="menuitem"]';
  const RESTORE_TIMEOUT_MS = 15000;
  const RESTORE_POLL_INTERVAL_MS = 120;

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
    const currentButton = findCurrentProjectButton();
    const selectedName = readProjectButtonName(currentButton);
    if (selectedName) return selectedName;
    if (findProjectChooserButton()) return '';

    const directContext = normalizeText(window.__CODEX_PLUS_PROJECT_WINDOW_CONTEXT?.name);
    if (directContext) return directContext;
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
    const projectName = normalizeText(currentProjectName());
    if (!projectName && !model && !reasoningEffort) return null;

    const createdAt = Date.now();
    return {
      projectName,
      model,
      reasoningEffort,
      createdAt,
      expiresAt: createdAt + RESTORE_TIMEOUT_MS,
      projectMenuOpenedAt: 0,
      projectSelectionAttemptedAt: 0,
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
    const controller = getSplitController();
    if (!controller) return true;

    const targetModelName = normalizeText(pending?.model);
    const targetEffort = normalizeText(pending?.reasoningEffort);
    const currentModelName = normalizeText(controller.model);
    const currentEffort = normalizeText(controller.reasoningEffort);

    if (!targetModelName && !targetEffort) {
      clearPendingContext();
      return false;
    }

    if (!targetModelName) {
      if (targetEffort && !controller.reasoningEffortDisabled && currentEffort !== targetEffort) {
        if (pending.effortSelectionAttemptedAt && now - pending.effortSelectionAttemptedAt < 1000) return true;
        pending.effortSelectionAttemptedAt = now;
        controller.onSelectReasoningEffort(targetEffort);
        return true;
      }
      clearPendingContext();
      return false;
    }

    const selectedModel = findModel(controller, targetModelName);
    if (!selectedModel) return true;

    const selectedModelName = normalizeText(selectedModel.model || selectedModel.id);
    const modelMatches = currentModelName === selectedModelName;
    const effortMatches = !targetEffort || currentEffort === targetEffort;
    if (modelMatches && effortMatches) {
      clearPendingContext();
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

    return restoreModelSelection(pending, now);
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
