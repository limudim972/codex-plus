# Live Debugging

Use this reference when inspecting Codex behavior in a running app, especially when verifying live surfaces or RTL layout.

## Live targets

- Prefer the live Codex debugger target instead of restarting the app.
- Check `http://127.0.0.1:18317/json/list` first.
- If IPv4 is unavailable, try the IPv6 loopback form.
- The active page usually appears as `app://-/index.html`.

## Important selectors

- Common Codex surface anchors: `[role="tabpanel"]`, `[data-tab-id]`, `[aria-label]`
- Plan tabpanel example: `[role="tabpanel"][aria-label="Plan"][data-tab-id="plan"]`
- Help button: `[aria-label="Help"]`
- Close button example: `[aria-label*="Close"]`

## Verification checklist

- Confirm the target surface exists before editing.
- Confirm the target has `dir="rtl"` after the fix when RTL is expected.
- Confirm computed `direction` is `rtl`.
- Confirm computed `text-align` is `right` or equivalent for the target.
- Confirm the title badge appears once, if used.
- Confirm code blocks and technical islands stay LTR.

## Practical notes

- Do not assume a browser-like panel is an iframe or webview; inspect the DOM first.
- A visible `HE` marker should be treated as a diagnostic cue, not the source of RTL behavior.
- If the title shows duplicate `HE` suffixes, normalize the title before writing it again.
- If a marker disappears after rerendering, reattach it through the live debugger or runtime observer.
- Use `scripts/codex_live_probe.js` for a quick read-only check of the live debugger target and an optional selector.
