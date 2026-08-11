function Get-CodexAutoContinuePayload {
@'
(() => {
  if (window.__CODEX_PLUS_AUTO_CONTINUE) return;
  window.__CODEX_PLUS_AUTO_CONTINUE = true;

  const AUTO_EVENT = 'codex-plus-auto-continue';
  const AUTO_STATE_KEY = 'codex-plus-auto-continue-error-session';

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
    if (!threadId) return false;
    if (sessionStorage.getItem(AUTO_STATE_KEY) === threadId) return false;
    sessionStorage.setItem(AUTO_STATE_KEY, threadId);
    const manager = getLocalManager();
    if (!manager) return false;
    try {
      await manager.sendRequest('thread/resume', { threadId });
      await manager.sendRequest('turn/start', {
        threadId,
        clientUserMessageId: crypto.randomUUID(),
        input: [{ type: 'text', text: 'continue', text_elements: [] }]
      });
      return true;
    } catch {
      return false;
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
  window.addEventListener(AUTO_EVENT, (event) => {
    void window.__CODEX_PLUS_AUTO_CONTINUE_HANDLE_ERROR(event.detail);
  });
})();
'@
}
