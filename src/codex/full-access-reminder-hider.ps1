function Get-CodexFullAccessReminderHiderPayload {
    @'
(function () {
  const MARKER = 'data-codex-plus-full-access-reminder';
  const NEW_MESSAGE = 'full access is on';
  const OLD_MESSAGE = 'chatgpt will be able to run commands';
  const handledThreads = new Set();

  function normalize(text) {
    return String(text || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function hideReminder(root) {
    if (!root || root.hasAttribute(MARKER)) return;
    root.setAttribute(MARKER, 'true');
    root.style.setProperty('display', 'none', 'important');
  }

  function getThreadKey() {
    const conversation = document.querySelector('[data-thread-find-target="conversation"]');
    const threadNode = conversation?.closest('[data-thread-id], [data-conversation-id]') || conversation;
    const threadId = threadNode?.getAttribute('data-thread-id') || threadNode?.getAttribute('data-conversation-id');
    if (threadId) return 'thread:' + threadId;
    return 'url:' + window.location.pathname;
  }

  function scan(root) {
    if (!root) return;
    const threadKey = getThreadKey();
    if (handledThreads.has(threadKey)) return;
    const ownerDocument = root.ownerDocument || document;
    const walker = ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let textNode = root.nodeType === Node.TEXT_NODE ? root : walker.nextNode();
    while (textNode) {
      // A linear text-node walk avoids both layout work and the quadratic cost
      // of repeatedly reading descendant textContent from every nested div.
      const text = normalize(textNode.nodeValue);
      if (text && (text.includes(NEW_MESSAGE) || text.includes(OLD_MESSAGE))) {
        const element = textNode.parentElement?.closest('p, span, div');
        if (element) {
          hideReminder(element);
          handledThreads.add(threadKey);
        }
        return;
      }
      textNode = walker.nextNode();
    }
  }

  if (window.__CODEX_PLUS_FULL_ACCESS_REMINDER_HIDER) return;
  window.__CODEX_PLUS_FULL_ACCESS_REMINDER_HIDER = true;
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType === Node.ELEMENT_NODE) scan(node);
        else if (node.parentElement) scan(node.parentElement);
      }
    }
  });
  const start = () => {
    scan(document.body || document.documentElement);
    observer.observe(document.documentElement, { childList: true, subtree: true });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
'@
}
