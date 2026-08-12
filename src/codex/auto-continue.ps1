function Get-CodexAutoContinuePayload {
@'
(() => {
  if (window.__CODEX_PLUS_AUTO_CONTINUE) return;
  window.__CODEX_PLUS_AUTO_CONTINUE = true;

  const AUTO_EVENT = 'codex-plus-auto-continue';
  const AUTO_STATUS_EVENT = 'codex-plus-auto-continue-status';
  const AUTO_STATE_KEY = 'codex-plus-auto-continue-error-session';

  const emitStatus = (detail) => {
    window.dispatchEvent(new CustomEvent(AUTO_STATUS_EVENT, { detail }));
  };

  const errorText = (error) => {
    const message = error?.message || error?.error || error;
    return String(message || 'unknown error').replace(/\s+/g, ' ').trim().slice(0, 240);
  };

  const getReactScope = () => {
    const getFiber = (element) => {
      const key = element && Object.keys(element).find((candidate) => candidate.startsWith('__reactFiber$'));
      return key ? element[key] : null;
    };
    for (const candidate of [
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-thread-id]')),
      ...Array.from(document.querySelectorAll('[data-app-action-sidebar-project-row]'))
    ]) {
      let fiber = getFiber(candidate);
      let depth = 0;
      while (fiber && depth < 200) {
        let hook = fiber.memoizedState;
        let hookDepth = 0;
        while (hook && hookDepth < 100) {
          const value = hook.memoizedState?.current;
          if (value?.node?.store && typeof value.get === 'function' && typeof value.set === 'function') return value;
          hook = hook.next;
          hookDepth += 1;
        }
        fiber = fiber.return;
        depth += 1;
      }
    }
    return null;
  };

  const getLocalManager = () => {
    const scope = getReactScope();
    for (const [family, members] of scope?.node?.familyBindings?.entries?.() || []) {
      for (const [key] of members?.entries?.() || []) {
        try {
          const manager = scope.get(family, key);
          if (manager && typeof manager.sendRequest === 'function' && typeof manager.hydrateBackgroundThreads === 'function') {
            return manager;
          }
        } catch {}
      }
    }
    return null;
  };

  const continueErroredThread = async (session) => {
    const threadId = String(session || '').trim();
    if (!threadId) {
      const result = { ok: false, reason: 'missing-session' };
      emitStatus({ ...result, message: 'Auto-continue could not start: missing session id.' });
      return result;
    }
    if (sessionStorage.getItem(AUTO_STATE_KEY) === threadId) {
      const result = { ok: false, reason: 'already-attempted', session: threadId };
      emitStatus({ ...result, message: 'Auto-continue was already attempted for this session.' });
      return result;
    }
    sessionStorage.setItem(AUTO_STATE_KEY, threadId);
    const manager = getLocalManager();
    if (!manager) {
      sessionStorage.removeItem(AUTO_STATE_KEY);
      const result = { ok: false, reason: 'conversation-manager-unavailable', session: threadId };
      emitStatus({ ...result, message: 'Auto-continue could not start: the conversation manager was unavailable.' });
      return result;
    }
    try {
      try {
        await manager.sendRequest('thread/resume', { threadId });
      } catch (error) {
        sessionStorage.removeItem(AUTO_STATE_KEY);
        const result = { ok: false, reason: 'thread-resume-failed', session: threadId, error: errorText(error) };
        emitStatus({ ...result, message: 'Auto-continue failed while resuming the thread: ' + result.error });
        return result;
      }
      try {
        await manager.sendRequest('turn/start', {
          threadId,
          clientUserMessageId: crypto.randomUUID(),
          input: [{ type: 'text', text: 'continue', text_elements: [] }]
        });
      } catch (error) {
        sessionStorage.removeItem(AUTO_STATE_KEY);
        const result = { ok: false, reason: 'turn-start-failed', session: threadId, error: errorText(error) };
        emitStatus({ ...result, message: 'Auto-continue failed while starting the new turn: ' + result.error });
        return result;
      }
      const result = { ok: true, reason: 'started', session: threadId };
      emitStatus({ ...result, message: 'Auto-continue started.' });
      return result;
    } catch (error) {
      sessionStorage.removeItem(AUTO_STATE_KEY);
      const result = { ok: false, reason: 'unexpected-error', session: threadId, error: errorText(error) };
      emitStatus({ ...result, message: 'Auto-continue failed: ' + result.error });
      return result;
    }
  };

  const canHandleErroredThread = () => Boolean(getLocalManager());
  const prefersErroredThread = (detail) => {
    const threadId = String(detail?.session || '').trim();
    const manager = getLocalManager();
    if (!manager || !threadId || typeof manager.getConversation !== 'function') return false;
    try { return Boolean(manager.getConversation(threadId)); } catch { return false; }
  };

  window.__CODEX_PLUS_AUTO_CONTINUE_CAN_HANDLE_ERROR = canHandleErroredThread;
  window.__CODEX_PLUS_AUTO_CONTINUE_PREFERS_ERROR = prefersErroredThread;
  window.__CODEX_PLUS_AUTO_CONTINUE_HANDLE_ERROR = (detail) => continueErroredThread(detail?.session);
  window.__CODEX_PLUS_AUTO_CONTINUE_LAST_PROMISE = null;
  window.addEventListener(AUTO_EVENT, (event) => {
    const promise = Promise.resolve(window.__CODEX_PLUS_AUTO_CONTINUE_HANDLE_ERROR(event.detail));
    window.__CODEX_PLUS_AUTO_CONTINUE_LAST_PROMISE = promise;
    void promise;
  });
})();
'@
}
