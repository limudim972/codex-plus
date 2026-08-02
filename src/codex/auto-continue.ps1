function Get-CodexAutoContinuePayload {
@'
(() => {
  if (window.__CODEX_PLUS_AUTO_CONTINUE) return;
  window.__CODEX_PLUS_AUTO_CONTINUE = true;

  const KEY = 'codex-plus-auto-continue';
  const RESPONSE_KEY = 'codex-plus-auto-continue-response';
  const WAIT_MS = 20000;
  const RETRY_MS = 5000;
  const STABLE_MS = 1500;

  const visible = (el) => {
    if (!el || !el.isConnected) return false;
    const style = getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' && el.getClientRects().length > 0;
  };

  const text = (el) => ((el?.innerText || el?.getAttribute('aria-label') || el?.getAttribute('title') || '') + '').replace(/\s+/g, ' ').trim();

  const isWorking = () => /working|generating|thinking|running/i.test(document.body?.innerText || '') &&
    !Array.from(document.querySelectorAll('button,[role="button"]')).some((el) => visible(el) && /continue generating|continue|resume/i.test(text(el)));

  const getLatestAssistant = () => {
    const annotated = Array.from(document.querySelectorAll('[data-response-annotation-conversation][data-response-annotation-target]'));
    if (annotated.length) return annotated.at(-1);
    const assistants = Array.from(document.querySelectorAll('[data-message-author-role="assistant"],[data-author-role="assistant"]'));
    return assistants.at(-1) || null;
  };

  const responseState = (response) => {
    const actions = Array.from(response?.querySelectorAll('button,[role="button"]') || []);
    const hasActionLine = actions.some((el) => /^(copy|copy message)$/i.test(text(el))) &&
      actions.some((el) => /^continue in new chat from here$/i.test(text(el)));
    const hasFeedback = actions.some((el) => /^(good response|bad response|like|dislike)$/i.test(text(el)));
    const annotation = response?.matches?.('[data-response-annotation-conversation]')
      ? response
      : response?.querySelector('[data-response-annotation-conversation]');
    const target = annotation?.getAttribute('data-response-annotation-target') || '';
    const conversation = annotation?.getAttribute('data-response-annotation-conversation') || '';
    return { hasActionLine, hasFeedback, key: conversation + ':' + target };
  };

  const tryContinue = () => {
    if (isWorking()) return;
    const response = getLatestAssistant();
    if (!response) return;
    const state = responseState(response);
    if (!state.hasActionLine || state.hasFeedback) return;
    if (state.key && sessionStorage.getItem(RESPONSE_KEY) === state.key) return;
    const composer = Array.from(document.querySelectorAll('textarea,[contenteditable="true"],[role="textbox"]')).find((el) => visible(el));
    if (!composer) return;
    const current = (composer.value ?? composer.textContent ?? '').trim();
    if (current) return;

    const now = Date.now();
    const last = Number(sessionStorage.getItem(KEY) || 0);
    if (now - last < WAIT_MS) return;
    const observedAt = Number(sessionStorage.getItem(KEY + '-observed-at') || 0);
    if (now - observedAt < STABLE_MS) return;
    sessionStorage.setItem(RESPONSE_KEY, state.key || String(now));
    sessionStorage.setItem(KEY, String(now));
    if ('value' in composer) {
      const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(composer), 'value')?.set;
      setter?.call(composer, 'continue');
    } else {
      composer.textContent = 'continue';
    }
    composer.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: 'continue' }));
    composer.focus();
    setTimeout(tryContinue, RETRY_MS);
  };

  const observer = new MutationObserver(() => {
    sessionStorage.setItem(KEY + '-observed-at', String(Date.now()));
    setTimeout(tryContinue, STABLE_MS);
  });
  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-label'] });
  setInterval(tryContinue, RETRY_MS);
  tryContinue();
})();
'@
}
