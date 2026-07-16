function Get-CodexRtlSharedPayload {
    @'
(function () {
  const RTL_RE = /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/g;
  const LTR_RE = /[A-Za-z\u00C0-\u024F]/g;
  const STRONG_RE = /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFFA-Za-z\u00C0-\u024F]/;

  function normalizeText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function stripDiagnosticPrefix(text) {
    return normalizeText(text)
      .replace(/^[A-Z]\d{2}\.\s*[^:\n]{1,80}:\s*/u, '')
      .replace(/^\d{1,3}\.\s*[^:\n]{1,80}:\s*/u, '')
      .trim();
  }

  function getMeaningfulText(input, skipSelector) {
    if (!input) return '';
    if (typeof input === 'string') return stripDiagnosticPrefix(input);

    const clone = input.cloneNode(true);
    if (skipSelector) {
      for (const technical of clone.querySelectorAll(skipSelector)) {
        technical.remove();
      }
    }
    return stripDiagnosticPrefix(clone.innerText || clone.textContent || '');
  }

  function classifyDirection(input, skipSelector) {
    const normalized = getMeaningfulText(input, skipSelector);
    if (!normalized) return 'neutral';

    const rtlCount = (normalized.match(RTL_RE) || []).length;
    const ltrCount = (normalized.match(LTR_RE) || []).length;

    if (rtlCount === 0) return 'ltr';

    const firstStrong = (normalized.match(STRONG_RE) || [''])[0];
    const firstStrongIsRtl = Boolean(firstStrong && firstStrong.match(RTL_RE));

    if (firstStrongIsRtl) return 'rtl';
    if (rtlCount >= 3 && rtlCount >= ltrCount * 0.25) return 'rtl';

    return 'ltr';
  }

  function ensureHelpers(scope) {
    if (scope.__CODEX_RTL_SHARED_HELPERS) return scope.__CODEX_RTL_SHARED_HELPERS;
    const helpers = {
      RTL_RE,
      LTR_RE,
      STRONG_RE,
      normalizeText,
      stripDiagnosticPrefix,
      getMeaningfulText,
      classifyDirection
    };
    scope.__CODEX_RTL_SHARED_HELPERS = helpers;
    return helpers;
  }

  ensureHelpers(window);
})();
'@
}
