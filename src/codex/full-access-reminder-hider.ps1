function Get-CodexFullAccessReminderHiderPayload {
    @'
(function () {
  const MARKER = 'data-codex-plus-full-access-reminder';
  const NEW_MESSAGE = 'full access is on';
  const OLD_MESSAGE = 'chatgpt will be able to run commands';

  function normalize(text) {
    return String(text || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function hideReminder(root) {
    if (!root || root.hasAttribute(MARKER)) return;
    root.setAttribute(MARKER, 'true');
    root.style.setProperty('display', 'none', 'important');
  }

  function scan() {
    for (const element of document.querySelectorAll('body p, body span, body div')) {
      const text = normalize(element.innerText || element.textContent);
      if (!text || (!text.includes(NEW_MESSAGE) && !text.includes(OLD_MESSAGE))) continue;
      const childMatch = Array.from(element.children).some((child) => {
        const childText = normalize(child.innerText || child.textContent);
        return childText.includes(NEW_MESSAGE) || childText.includes(OLD_MESSAGE);
      });
      if (!childMatch) hideReminder(element);
    }
  }

  if (window.__CODEX_PLUS_FULL_ACCESS_REMINDER_HIDER) return;
  window.__CODEX_PLUS_FULL_ACCESS_REMINDER_HIDER = true;
  const observer = new MutationObserver(scan);
  const start = () => {
    scan();
    observer.observe(document.documentElement, { childList: true, subtree: true });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
'@
}
