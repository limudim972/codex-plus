function Get-CodexActivityOnboardingHiderPayload {
    @'
(function () {
  if (window.__CODEX_PLUS_ACTIVITY_ONBOARDING_HIDER) return;
  window.__CODEX_PLUS_ACTIVITY_ONBOARDING_HIDER = true;
  const style = document.createElement('style');
  style.setAttribute('data-codex-plus-activity-onboarding-css', 'true');
  style.textContent = [
    '[role="tooltip"][data-side="left"][class*="bg-token-text-link-foreground"][class*="rounded-2xl"] {',
    '  display: none !important;',
    '}'
  ].join('\n');
  (document.head || document.documentElement).appendChild(style);
})();
'@
}
