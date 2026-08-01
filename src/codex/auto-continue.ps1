function Get-CodexAutoContinuePayload {
@'
(() => {
  if (window.__CODEX_PLUS_AUTO_CONTINUE) return;
  window.__CODEX_PLUS_AUTO_CONTINUE = true;

  const KEY = 'codex-plus-auto-continue';
  const WAIT_MS = 20000;
  const RETRY_MS = 5000;

  const visible = (el) => {
    if (!el || !el.isConnected) return false;
    const style = getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' && el.getClientRects().length > 0;
  };

  const text = (el) => ((el?.innerText || el?.getAttribute('aria-label') || el?.getAttribute('title') || '') + '').replace(/\s+/g, ' ').trim();

  const isWorking = () => /working|generating|thinking|running/i.test(document.body?.innerText || '') &&
    !Array.from(document.querySelectorAll('button,[role="button"]')).some((el) => visible(el) && /continue generating|continue|resume/i.test(text(el)));

  const hasLatestCompletedAssistant = () => {
    const users = Array.from(document.querySelectorAll('[data-message-author-role="user"],[data-author-role="user"]'));
    const assistants = Array.from(document.querySelectorAll('[data-message-author-role="assistant"],[data-author-role="assistant"]'));
    const latestUser = users.at(-1);
    const latestAssistant = assistants.at(-1);
    if (!latestUser || !latestAssistant || latestAssistant.compareDocumentPosition(latestUser) & Node.DOCUMENT_POSITION_FOLLOWING) return false;
    const actions = Array.from(latestAssistant.querySelectorAll('button,[role="button"]')).filter(visible).map(text);
    const hasNeutralToolbar = actions.some((value) => /^(copy|copy message|share|regenerate|retry)$/i.test(value));
    const hasFeedback = actions.some((value) => /^(good response|bad response|like|dislike)$/i.test(value));
    return hasNeutralToolbar && hasFeedback;
  };

  const tryContinue = () => {
    if (isWorking()) return;
    if (!document.querySelector('[data-message-author-role="user"],[data-author-role="user"]')) return;
    if (hasLatestCompletedAssistant()) return;
    const composer = Array.from(document.querySelectorAll('textarea,[contenteditable="true"],[role="textbox"]')).find((el) => visible(el));
    if (!composer) return;
    const current = (composer.value ?? composer.textContent ?? '').trim();
    if (current) return;

    const now = Date.now();
    const last = Number(sessionStorage.getItem(KEY) || 0);
    if (now - last < WAIT_MS) return;
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

  setInterval(tryContinue, RETRY_MS);
  tryContinue();
})();
'@
}
