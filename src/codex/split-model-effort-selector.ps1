function Get-CodexSplitModelEffortSelectorPayload {
    @'
(function () {
  const existing = window.__CODEX_PLUS_SPLIT_MODEL_EFFORT_SELECTOR;
  if (existing && typeof existing.apply === 'function') return;

  const HOST_ATTR = 'data-codex-plus-split-model-effort-selector';
  const STYLE_ATTR = 'data-codex-plus-split-model-effort-style';
  const NATIVE_HIDDEN_ATTR = 'data-codex-plus-native-selector-hidden';
  const NATIVE_TRIGGER_SELECTOR = '[data-codex-intelligence-trigger="true"]';
  const EFFORT_LABELS = {
    low: 'Light',
    medium: 'Medium',
    high: 'High',
    xhigh: 'Extra High',
    ultra: 'Ultra'
  };
  const SELECT_CLASSES = [
    'border-token-border',
    'no-drag',
    'cursor-interaction',
    'border',
    'whitespace-nowrap',
    'select-none',
    'focus:outline-none',
    'disabled:cursor-not-allowed',
    'disabled:opacity-40',
    'rounded-full',
    'text-token-text-tertiary',
    'enabled:hover:bg-token-list-hover-background',
    'focus:bg-token-list-hover-background',
    'border-transparent',
    'h-token-button-composer',
    'text-sm',
    'leading-[18px]',
    'min-w-0'
  ].join(' ');
  const CHEVRON = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" class="cp-split-selector-chevron h-3.5 w-3.5 shrink-0 text-token-text-tertiary"><path d="M12.1338 5.94433C12.3919 5.77382 12.7434 5.80202 12.9707 6.02929C13.1979 6.25656 13.2261 6.60807 13.0556 6.8662L12.9707 6.9707L8.47067 11.4707C8.21097 11.7304 7.78896 11.7304 7.52926 11.4707L3.02926 6.9707L2.9443 6.8662C2.77379 6.60807 2.80199 6.25656 3.02926 6.02929C3.25653 5.80202 3.60804 5.77382 3.86617 5.94433L3.97067 6.02929L7.99996 10.0586L12.0293 6.02929L12.1338 5.94433Z"></path></svg>';
  const LIGHTNING_EMPTY = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M9.271 1.75 3.5 8.5h3.75l-.521 5.75L12.5 7.5H8.75l.521-5.75Z" stroke="currentColor" stroke-width="1.25" stroke-linejoin="round"></path></svg>';
  const LIGHTNING_FULL = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M9.271 1.75 3.5 8.5h3.75l-.521 5.75L12.5 7.5H8.75l.521-5.75Z" fill="currentColor" stroke="#facc15" stroke-width="1.35" stroke-linejoin="round" paint-order="stroke"></path></svg>';

  let host = null;
  let pending = false;
  let destroyed = false;
  let syncInterval = null;
  let hiddenNativeTrigger = null;
  let hiddenNativeTriggerState = null;
  let modelMenu = null;
  let effortMenu = null;

  function modelLabel(model) {
    return String(model.displayName || model.model || model.id || 'Model')
      .replace(/^GPT-/i, '')
      .replace(/-Mini$/i, ' Mini')
      .replace(/-(Sol|Terra|Luna)$/i, ' $1');
  }

  function effortLabel(effort) {
    return EFFORT_LABELS[effort] || String(effort || '').replace(/^./, (value) => value.toUpperCase());
  }

  function serviceTierLabel(option) {
    const label = option && option.label;
    return typeof label === 'string' ? label : (label && label.defaultMessage) || (option && option.value ? 'Fast' : 'Standard');
  }

  function serviceTierDescription(option) {
    const description = option && option.description;
    return typeof description === 'string'
      ? description
      : (description && description.defaultMessage) || serviceTierLabel(option);
  }

  function getServiceTiers(controller) {
    return (Array.isArray(controller.serviceTierOptions) ? controller.serviceTierOptions : [])
      .map((option) => ({
        ...option,
        nativeValue: option.value == null ? null : option.value,
        label: serviceTierLabel(option),
        description: serviceTierDescription(option),
        iconKind: option.iconKind || (option.value == null ? 'empty' : 'full')
      }));
  }

  function getController(nativeTrigger) {
    if (!nativeTrigger) return null;
    const fiberKey = Object.keys(nativeTrigger).find((key) => key.startsWith('__reactFiber$'));
    let fiber = fiberKey ? nativeTrigger[fiberKey] : null;
    for (let depth = 0; fiber && depth < 60; depth += 1, fiber = fiber.return) {
      const props = fiber.memoizedProps || {};
      if (
        Array.isArray(props.models) &&
        typeof props.onSelectModel === 'function' &&
        typeof props.onSelectReasoningEffort === 'function'
      ) {
        return props;
      }
    }
    return null;
  }

  function getVisibleModels(controller) {
    return (controller.models || []).filter((model) => !model.hidden);
  }

  function getEfforts(model) {
    return (model && Array.isArray(model.supportedReasoningEfforts) ? model.supportedReasoningEfforts : [])
      .map((entry) => typeof entry === 'string' ? entry : entry.reasoningEffort)
      .filter(Boolean);
  }

  function syncButtonWidth(button, label) {
    if (!button) return;

    const styles = getComputedStyle(button);
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    if (!context) return;

    context.font = [styles.fontStyle, styles.fontWeight, styles.fontSize, styles.fontFamily].join(' ');
    const letterSpacing = parseFloat(styles.letterSpacing) || 0;
    const textWidth = context.measureText(label).width + letterSpacing * Math.max(0, label.length - 1);
    const horizontalPadding = parseFloat(styles.paddingInlineStart) + parseFloat(styles.paddingInlineEnd);
    const horizontalBorder = parseFloat(styles.borderInlineStartWidth) + parseFloat(styles.borderInlineEndWidth);
    button.style.width = Math.ceil(textWidth + horizontalPadding + horizontalBorder) + 'px';
  }

  function findToolbar(nativeTrigger) {
    let node = nativeTrigger.parentElement;
    while (node && node !== document.body) {
      const style = getComputedStyle(node);
      if ((style.display === 'flex' || style.display === 'inline-flex') && parseFloat(style.columnGap || style.gap || '0') > 0) return node;
      node = node.parentElement;
    }
    return nativeTrigger.parentElement;
  }

  function directChildContaining(parent, descendant) {
    let child = descendant;
    while (child && child.parentElement !== parent) child = child.parentElement;
    return child;
  }

  function restoreNativeTrigger() {
    if (!hiddenNativeTrigger) return;

    hiddenNativeTrigger.hidden = Boolean(hiddenNativeTriggerState?.hidden);
    if (hiddenNativeTriggerState?.ariaHidden == null) {
      hiddenNativeTrigger.removeAttribute('aria-hidden');
    } else {
      hiddenNativeTrigger.setAttribute('aria-hidden', hiddenNativeTriggerState.ariaHidden);
    }
    hiddenNativeTrigger.removeAttribute(NATIVE_HIDDEN_ATTR);
    if (hiddenNativeTriggerState?.display) {
      hiddenNativeTrigger.style.setProperty('display', hiddenNativeTriggerState.display);
    } else {
      hiddenNativeTrigger.style.removeProperty('display');
    }
    hiddenNativeTrigger = null;
    hiddenNativeTriggerState = null;
  }

  function hideNativeTrigger(nativeTrigger) {
    if (!nativeTrigger) return;
    if (hiddenNativeTrigger !== nativeTrigger) {
      restoreNativeTrigger();
      hiddenNativeTrigger = nativeTrigger;
      hiddenNativeTriggerState = {
        hidden: nativeTrigger.hidden,
        ariaHidden: nativeTrigger.getAttribute('aria-hidden'),
        display: nativeTrigger.style.display
      };
    }

    nativeTrigger.hidden = true;
    nativeTrigger.setAttribute('aria-hidden', 'true');
    nativeTrigger.setAttribute(NATIVE_HIDDEN_ATTR, 'true');
    nativeTrigger.style.setProperty('display', 'none', 'important');
  }

  function ensureStyle() {
    if (!document.head || document.head.querySelector('style[' + STYLE_ATTR + ']')) return;
    const style = document.createElement('style');
    style.setAttribute(STYLE_ATTR, 'true');
    style.textContent = `
      [${HOST_ATTR}] { align-items: center; display: inline-flex; gap: 0; min-width: 0; }
      [${HOST_ATTR}] .cp-split-selector-wrap { display: inline-flex; min-width: 0; position: relative; }
      [${HOST_ATTR}] .cp-split-selector {
        align-items: center; appearance: none; background-color: transparent; display: inline-flex;
        font-size: 13px; font-weight: 445; height: 28px; justify-content: space-between;
        line-height: 18px; max-width: 118px; padding-block: 0; padding-inline-end: 14px; padding-inline-start: 8px;
      }
      [${HOST_ATTR}] .cp-split-selector-effort { max-width: 112px; }
      .cp-split-selector-menu {
        background: var(--token-main-surface); border: 1px solid var(--token-border);
        border-radius: 8px; box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18); display: none;
        isolation: isolate; max-height: 320px; min-width: 132px; overflow: auto; padding: 4px;
        pointer-events: auto; position: fixed; z-index: 2147483647;
      }
      .cp-split-selector-menu[hidden] { display: none !important; }
      .cp-split-selector-menu[data-open="true"] { display: block !important; }
      .cp-split-selector-option {
        background: transparent; border: 0; border-radius: 6px; color: #000;
        cursor: pointer; display: block; font: inherit; min-height: 28px; padding: 5px 8px;
        text-align: start; width: 100%;
      }
      .cp-split-selector-option:hover {
        background-color: rgba(0, 0, 0, 0.08); color: inherit;
      }
      [${HOST_ATTR}] .cp-split-selector:not(:disabled):hover { background-color: rgba(0, 0, 0, 0.08); color: inherit; }
      .cp-split-selector-option:focus-visible { outline: 2px solid var(--token-focus-border); outline-offset: -2px; }
      [${HOST_ATTR}] .cp-split-selector-speed-button {
        align-items: center; appearance: none; background-color: transparent; display: inline-flex; height: 28px;
        justify-content: center; padding: 0; width: 28px;
      }
      [${HOST_ATTR}] .cp-split-selector-speed-button:not(:disabled):hover { background-color: var(--token-list-hover-background); }
      [${HOST_ATTR}] .cp-split-selector-speed-icon {
        align-items: center; display: inline-flex; justify-content: center; pointer-events: none;
      }
      [${HOST_ATTR}] .cp-split-selector-speed-icon svg { height: 16px; width: 16px; }
      [${HOST_ATTR}] .cp-split-selector-chevron {
        inset-inline-end: 0; margin: 0; pointer-events: none; position: absolute; top: 50%; transform: translateY(-50%);
      }
    `;
    document.head.appendChild(style);
  }

  function replaceMenuOptions(menu, signature, options, selectedValue, onSelect) {
    if (!menu) return;
    if (menu.dataset.signature === signature) {
      for (const option of menu.querySelectorAll('[data-codex-plus-selector-option]')) {
        option.toggleAttribute('data-selected', option.dataset.value === selectedValue);
        option.setAttribute('aria-selected', option.dataset.value === selectedValue ? 'true' : 'false');
      }
      return;
    }
    menu.replaceChildren();
    for (const optionData of options) {
      const option = document.createElement('button');
      option.type = 'button';
      option.className = 'cp-split-selector-option';
      option.setAttribute('role', 'option');
      option.setAttribute('data-codex-plus-selector-option', 'true');
      option.dataset.value = optionData.value;
      option.textContent = optionData.label;
      option.setAttribute('aria-selected', optionData.value === selectedValue ? 'true' : 'false');
      option.toggleAttribute('data-selected', optionData.value === selectedValue);
      option.addEventListener('click', () => onSelect(optionData.value));
      menu.appendChild(option);
    }
    menu.dataset.signature = signature;
  }

  function closeMenus() {
    for (const menu of [modelMenu, effortMenu]) {
      if (!menu) continue;
      menu.dataset.open = 'false';
      menu.hidden = true;
    }
    if (host) {
      for (const button of host.querySelectorAll('[data-codex-plus-selector-button]')) {
        button.setAttribute('aria-expanded', 'false');
      }
    }
  }

  function removeMenus() {
    closeMenus();
    modelMenu?.remove();
    effortMenu?.remove();
    modelMenu = null;
    effortMenu = null;
  }

  function positionMenu(button, menu) {
    if (!button || !menu) return;
    const rect = button.getBoundingClientRect();
    const surface = document.querySelector('[class*="bg-token-side-bar-background"], [class*="bg-token-main-surface"]');
    const surfaceColor = surface ? getComputedStyle(surface).backgroundColor : '';
    if (surfaceColor && surfaceColor !== 'rgba(0, 0, 0, 0)') menu.style.backgroundColor = surfaceColor;
    menu.style.color = getComputedStyle(button).color;
    const width = Math.max(rect.width, 132);
    const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8));
    const estimatedHeight = Math.min(320, Math.max(36, menu.scrollHeight || 36));
    const top = rect.bottom + estimatedHeight + 8 <= window.innerHeight
      ? rect.bottom + 4
      : Math.max(8, rect.top - estimatedHeight - 4);
    menu.style.left = left + 'px';
    menu.style.top = top + 'px';
    menu.style.minWidth = width + 'px';
  }

  function toggleMenu(button, menu) {
    const isOpen = menu?.dataset.open === 'true';
    closeMenus();
    if (isOpen || !menu || button.disabled) return;
    menu.hidden = false;
    menu.dataset.open = 'true';
    button.setAttribute('aria-expanded', 'true');
    positionMenu(button, menu);
  }

  function render(controller) {
    if (!host) return;
    const models = getVisibleModels(controller);
    const selectedModel = models.find((model) => model.model === controller.model || model.id === controller.model) || models[0];
    if (!selectedModel) return;
    const efforts = getEfforts(selectedModel);
    const serviceTiers = getServiceTiers(controller);
    const modelButton = host.querySelector('[data-codex-plus-model-button]');
    const effortButton = host.querySelector('[data-codex-plus-effort-button]');
    const speedButton = host.querySelector('[data-codex-plus-speed-button]');
    const speedIcon = host.querySelector('[data-codex-plus-speed-icon]');

    const selectedModelValue = selectedModel.model || selectedModel.id;
    const selectedEffort = efforts.includes(controller.reasoningEffort) ? controller.reasoningEffort : (selectedModel.defaultReasoningEffort || efforts[0]);
    replaceMenuOptions(
      modelMenu,
      models.map((model) => model.model || model.id).join('|'),
      models.map((model) => ({ value: model.model || model.id, label: modelLabel(model) })),
      selectedModelValue,
      (value) => {
        const latest = getController(document.querySelector(NATIVE_TRIGGER_SELECTOR));
        if (!latest || latest.modelOptionsDisabled) return;
        const model = getVisibleModels(latest).find((candidate) => candidate.model === value || candidate.id === value);
        if (!model) return;
        const modelEfforts = getEfforts(model);
        const nextEffort = modelEfforts.includes(latest.reasoningEffort)
          ? latest.reasoningEffort
          : (model.defaultReasoningEffort || modelEfforts[0]);
        closeMenus();
        latest.onSelectModel(model.model || model.id, nextEffort);
        window.setTimeout(schedule, 0);
        window.setTimeout(schedule, 120);
      }
    );
    replaceMenuOptions(
      effortMenu,
      (selectedModel.model || selectedModel.id) + ':' + efforts.join('|'),
      efforts.map((effort) => ({ value: effort, label: effortLabel(effort) })),
      selectedEffort,
      (value) => {
        const latest = getController(document.querySelector(NATIVE_TRIGGER_SELECTOR));
        if (!latest || latest.reasoningEffortDisabled) return;
        closeMenus();
        latest.onSelectReasoningEffort(value);
        window.setTimeout(schedule, 0);
        window.setTimeout(schedule, 120);
      }
    );
    modelButton.querySelector('[data-codex-plus-selector-label]').textContent = modelLabel(selectedModel);
    effortButton.querySelector('[data-codex-plus-selector-label]').textContent = effortLabel(selectedEffort);
    const selectedServiceTier = serviceTiers.find((option) => option.nativeValue === (controller.selectedServiceTier == null ? null : controller.selectedServiceTier)) || serviceTiers[0];
    if (selectedServiceTier) {
      speedIcon.innerHTML = selectedServiceTier.iconKind === 'fast' ? LIGHTNING_FULL : LIGHTNING_EMPTY;
      speedIcon.setAttribute('aria-label', selectedServiceTier.label);
      speedButton.title = selectedServiceTier.description;
      speedButton.setAttribute('aria-label', 'Speed: ' + selectedServiceTier.label + '. ' + selectedServiceTier.description);
      speedButton.toggleAttribute('data-codex-plus-speed-active', selectedServiceTier.iconKind === 'fast');
    }
    syncButtonWidth(modelButton, modelLabel(selectedModel));
    syncButtonWidth(effortButton, effortLabel(selectedEffort));
    modelButton.disabled = Boolean(controller.modelOptionsDisabled);
    effortButton.disabled = Boolean(controller.reasoningEffortDisabled || efforts.length === 0);
    if (modelMenu?.dataset.open === 'true') positionMenu(modelButton, modelMenu);
    if (effortMenu?.dataset.open === 'true') positionMenu(effortButton, effortMenu);
    speedButton.disabled = Boolean(controller.serviceTierOptionsLoading || serviceTiers.length <= 1 || typeof controller.onSelectServiceTier !== 'function');
  }

  function buildUi(nativeTrigger, controller) {
    const toolbar = findToolbar(nativeTrigger);
    if (!toolbar) return;
    const anchor = directChildContaining(toolbar, nativeTrigger) || nativeTrigger;
    host = document.createElement('span');
    host.setAttribute(HOST_ATTR, 'true');
    host.innerHTML = `<span class="cp-split-selector-wrap"><button type="button" class="cp-split-selector cp-split-selector-model ${SELECT_CLASSES}" data-codex-plus-model-button data-codex-plus-selector-button aria-haspopup="listbox" aria-expanded="false" aria-label="Model"><span data-codex-plus-selector-label></span>${CHEVRON}</button><div class="cp-split-selector-menu" data-codex-plus-model-menu role="listbox" hidden></div></span><span class="cp-split-selector-wrap"><button type="button" class="cp-split-selector cp-split-selector-effort ${SELECT_CLASSES}" data-codex-plus-effort-button data-codex-plus-selector-button aria-haspopup="listbox" aria-expanded="false" aria-label="Effort"><span data-codex-plus-selector-label></span>${CHEVRON}</button><div class="cp-split-selector-menu" data-codex-plus-effort-menu role="listbox" hidden></div></span><span class="cp-split-selector-wrap cp-split-selector-speed-wrap"><button type="button" class="cp-split-selector-speed-button ${SELECT_CLASSES}" data-codex-plus-speed-button aria-label="Speed"><span class="cp-split-selector-speed-icon" data-codex-plus-speed-icon aria-hidden="true"></span></button></span>`;
    modelMenu = host.querySelector('[data-codex-plus-model-menu]');
    effortMenu = host.querySelector('[data-codex-plus-effort-menu]');
    document.body.append(modelMenu, effortMenu);
    toolbar.insertBefore(host, anchor);

    host.querySelector('[data-codex-plus-model-button]').addEventListener('click', (event) => {
      event.stopPropagation();
      toggleMenu(event.currentTarget, document.querySelector('[data-codex-plus-model-menu]'));
    });
    host.querySelector('[data-codex-plus-effort-button]').addEventListener('click', (event) => {
      event.stopPropagation();
      toggleMenu(event.currentTarget, document.querySelector('[data-codex-plus-effort-menu]'));
    });

    host.querySelector('[data-codex-plus-speed-button]').addEventListener('click', () => {
      const latest = getController(document.querySelector(NATIVE_TRIGGER_SELECTOR));
      if (!latest || latest.serviceTierOptionsLoading || typeof latest.onSelectServiceTier !== 'function') return;
      const serviceTiers = getServiceTiers(latest);
      if (serviceTiers.length <= 1) return;
      const currentIndex = serviceTiers.findIndex((option) => option.nativeValue === (latest.selectedServiceTier == null ? null : latest.selectedServiceTier));
      const nextTier = serviceTiers[(currentIndex + 1 + serviceTiers.length) % serviceTiers.length] || serviceTiers[0];
      latest.onSelectServiceTier(nextTier.nativeValue);
      window.setTimeout(schedule, 0);
      window.setTimeout(schedule, 120);
    });
    document.addEventListener('pointerdown', (event) => {
      if (
        host && !host.contains(event.target) &&
        !modelMenu?.contains(event.target) && !effortMenu?.contains(event.target)
      ) closeMenus();
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') closeMenus();
    });
    render(controller);
  }

  function apply() {
    if (destroyed) return;
    ensureStyle();
    const nativeTrigger = document.querySelector(NATIVE_TRIGGER_SELECTOR);
    const controller = getController(nativeTrigger);
    if (!nativeTrigger || !controller) {
      if (host) host.hidden = true;
      removeMenus();
      restoreNativeTrigger();
      return;
    }

    hideNativeTrigger(nativeTrigger);
    const toolbar = findToolbar(nativeTrigger);
    const anchor = directChildContaining(toolbar, nativeTrigger) || nativeTrigger;
    if (!host || !host.isConnected) {
      removeMenus();
      buildUi(nativeTrigger, controller);
    } else {
      host.hidden = false;
      if (host.parentElement !== toolbar || host.nextElementSibling !== anchor) toolbar.insertBefore(host, anchor);
      render(controller);
    }
  }

  function schedule() {
    if (pending || destroyed) return;
    pending = true;
    window.setTimeout(() => {
      pending = false;
      apply();
    }, 40);
  }

  function destroy() {
    destroyed = true;
    observer.disconnect();
    if (syncInterval) window.clearInterval(syncInterval);
    if (host) host.remove();
    removeMenus();
    restoreNativeTrigger();
  }

  const SELECTOR_SURFACE = NATIVE_TRIGGER_SELECTOR + ',[' + HOST_ATTR + ']';
  function mutationTouchesSelector(record) {
    const target = record.target instanceof Element
      ? record.target
      : record.target?.parentElement;
    if (target?.matches(SELECTOR_SURFACE) || target?.closest(SELECTOR_SURFACE)) return true;
    return [...Array.from(record.addedNodes || []), ...Array.from(record.removedNodes || [])].some((node) => {
      return node instanceof Element && (
        node.matches(SELECTOR_SURFACE) || Boolean(node.querySelector(SELECTOR_SURFACE))
      );
    });
  }

  const observer = new MutationObserver((records) => {
    if (records.some(mutationTouchesSelector)) schedule();
  });
  const start = () => {
    apply();
    if (document.documentElement) {
      observer.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ['data-selected-reasoning-effort'],
        childList: true,
        characterData: true,
        subtree: true
      });
    }
    syncInterval = window.setInterval(schedule, 2000);
  };

  window.__CODEX_PLUS_SPLIT_MODEL_EFFORT_SELECTOR = { apply, destroy, getController };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
'@
}
