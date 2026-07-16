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

  let host = null;
  let pending = false;
  let destroyed = false;
  let syncInterval = null;
  let hiddenNativeTrigger = null;
  let hiddenNativeTriggerState = null;

  function modelLabel(model) {
    return String(model.displayName || model.model || model.id || 'Model')
      .replace(/^GPT-/i, '')
      .replace(/-Mini$/i, ' Mini')
      .replace(/-(Sol|Terra|Luna)$/i, ' $1');
  }

  function effortLabel(effort) {
    return EFFORT_LABELS[effort] || String(effort || '').replace(/^./, (value) => value.toUpperCase());
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

  function syncSelectWidth(select) {
    if (!select || !select.options.length) return;
    const selectedOption = select.options[select.selectedIndex];
    if (!selectedOption) return;

    const styles = getComputedStyle(select);
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    if (!context) return;

    context.font = [styles.fontStyle, styles.fontWeight, styles.fontSize, styles.fontFamily].join(' ');
    const label = selectedOption.textContent || '';
    const letterSpacing = parseFloat(styles.letterSpacing) || 0;
    const textWidth = context.measureText(label).width + letterSpacing * Math.max(0, label.length - 1);
    const horizontalPadding = parseFloat(styles.paddingInlineStart) + parseFloat(styles.paddingInlineEnd);
    const horizontalBorder = parseFloat(styles.borderInlineStartWidth) + parseFloat(styles.borderInlineEndWidth);
    select.style.width = Math.ceil(textWidth + horizontalPadding + horizontalBorder) + 'px';
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
        appearance: none; background-color: transparent; font-size: 13px; font-weight: 445; height: 28px;
        line-height: 18px; max-width: 118px; padding-block: 0; padding-inline-end: 14px; padding-inline-start: 8px;
      }
      [${HOST_ATTR}] .cp-split-selector-effort { max-width: 112px; }
      [${HOST_ATTR}] .cp-split-selector-chevron {
        inset-inline-end: 0; margin: 0; pointer-events: none; position: absolute; top: 50%; transform: translateY(-50%);
      }
    `;
    document.head.appendChild(style);
  }

  function replaceOptions(select, signature, options) {
    if (select.dataset.signature === signature) return;
    select.replaceChildren();
    for (const optionData of options) {
      const option = document.createElement('option');
      option.value = optionData.value;
      option.textContent = optionData.label;
      select.appendChild(option);
    }
    select.dataset.signature = signature;
  }

  function render(controller) {
    if (!host) return;
    const models = getVisibleModels(controller);
    const selectedModel = models.find((model) => model.model === controller.model || model.id === controller.model) || models[0];
    if (!selectedModel) return;
    const efforts = getEfforts(selectedModel);
    const modelSelect = host.querySelector('[data-codex-plus-model-select]');
    const effortSelect = host.querySelector('[data-codex-plus-effort-select]');

    replaceOptions(
      modelSelect,
      models.map((model) => model.model || model.id).join('|'),
      models.map((model) => ({ value: model.model || model.id, label: modelLabel(model) }))
    );
    replaceOptions(
      effortSelect,
      (selectedModel.model || selectedModel.id) + ':' + efforts.join('|'),
      efforts.map((effort) => ({ value: effort, label: effortLabel(effort) }))
    );

    modelSelect.value = selectedModel.model || selectedModel.id;
    effortSelect.value = efforts.includes(controller.reasoningEffort) ? controller.reasoningEffort : (selectedModel.defaultReasoningEffort || efforts[0]);
    syncSelectWidth(modelSelect);
    syncSelectWidth(effortSelect);
    modelSelect.disabled = Boolean(controller.modelOptionsDisabled);
    effortSelect.disabled = Boolean(controller.reasoningEffortDisabled || efforts.length === 0);
  }

  function buildUi(nativeTrigger, controller) {
    const toolbar = findToolbar(nativeTrigger);
    if (!toolbar) return;
    const anchor = directChildContaining(toolbar, nativeTrigger) || nativeTrigger;
    host = document.createElement('span');
    host.setAttribute(HOST_ATTR, 'true');
    host.innerHTML = `<span class="cp-split-selector-wrap"><select class="cp-split-selector cp-split-selector-model ${SELECT_CLASSES}" data-codex-plus-model-select aria-label="Model"></select>${CHEVRON}</span><span class="cp-split-selector-wrap"><select class="cp-split-selector cp-split-selector-effort ${SELECT_CLASSES}" data-codex-plus-effort-select aria-label="Effort"></select>${CHEVRON}</span>`;
    toolbar.insertBefore(host, anchor);

    host.querySelector('[data-codex-plus-model-select]').addEventListener('change', (event) => {
      const latest = getController(document.querySelector(NATIVE_TRIGGER_SELECTOR));
      if (!latest || latest.modelOptionsDisabled) return;
      const model = getVisibleModels(latest).find((candidate) => candidate.model === event.target.value || candidate.id === event.target.value);
      if (!model) return;
      const efforts = getEfforts(model);
      const nextEffort = efforts.includes(latest.reasoningEffort)
        ? latest.reasoningEffort
        : (model.defaultReasoningEffort || efforts[0]);
      latest.onSelectModel(model.model || model.id, nextEffort);
      window.setTimeout(schedule, 0);
      window.setTimeout(schedule, 120);
    });

    host.querySelector('[data-codex-plus-effort-select]').addEventListener('change', (event) => {
      const latest = getController(document.querySelector(NATIVE_TRIGGER_SELECTOR));
      if (!latest || latest.reasoningEffortDisabled) return;
      latest.onSelectReasoningEffort(event.target.value);
      window.setTimeout(schedule, 0);
      window.setTimeout(schedule, 120);
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
      restoreNativeTrigger();
      return;
    }

    hideNativeTrigger(nativeTrigger);
    const toolbar = findToolbar(nativeTrigger);
    const anchor = directChildContaining(toolbar, nativeTrigger) || nativeTrigger;
    if (!host || !host.isConnected) {
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
    restoreNativeTrigger();
  }

  const observer = new MutationObserver(schedule);
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
    syncInterval = window.setInterval(schedule, 500);
  };

  window.__CODEX_PLUS_SPLIT_MODEL_EFFORT_SELECTOR = { apply, destroy, getController };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
'@
}
