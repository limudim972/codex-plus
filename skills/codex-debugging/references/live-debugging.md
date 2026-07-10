# Live Debugging

Use this reference when inspecting Codex behavior in a running app, especially when verifying live surfaces or browser-like panels.

## Live targets

- Prefer the live Codex debugger target instead of restarting the app.
- Check `http://127.0.0.1:<port>/json/list` for the actual running port.
- If IPv4 is unavailable, try the IPv6 loopback form.
- The active page usually appears as `app://-/index.html`.
- In Codex Plus, the actual live port may be launcher-scoped rather than `18317`. Inspect the running `ChatGPT.exe` command line or use the persisted launcher state to find the active port.

## Finding the right instance

- Read the running desktop process command line, not just the process name.
- Match these fields together when multiple windows are open:
  - `--remote-debugging-port`
  - `--user-data-dir`
  - launcher-specific profile path
- Prefer the browser process entry point, not crashpad, GPU, or utility children.

## Important selectors

- Common Codex surface anchors: `[role="tabpanel"]`, `[data-tab-id]`, `[aria-label]`
- Plan tabpanel example: `[role="tabpanel"][aria-label="Plan"][data-tab-id="plan"]`
- Help button: `[aria-label="Help"]`
- Close button example: `[aria-label*="Close"]`
- Project rows in the sidebar: `div[data-app-action-sidebar-project-row]`
- Project labels in the sidebar: `[data-app-action-sidebar-project-label]`

## Verification checklist

- Confirm the target surface exists before editing.
- Confirm the computed `direction` when validating layout behavior.
- Confirm the computed `text-align` when validating text flow.
- Confirm the target is the correct document or panel.
- Confirm code blocks and technical islands remain unaffected when you are only inspecting layout behavior.
- Confirm whether the data you need is rendered in the DOM, stored in attributes, or only present in client state.
- Keep DOM findings and state findings separate in your notes.

## Codex Plus practical notes

- `tools/invoke-codex-devtools.ps1` is the repo helper for live DevTools evaluation against a running Codex Plus window.
- Use the helper first for read-only inspection before introducing new launcher or runtime behavior.
- If needed, inspect client-side state separately from DOM rendering.

## State inspection notes

- Start with DOM inspection because it is the closest match to user-visible behavior.
- If the DOM does not answer the question, inspect client-side globals, stores, or serialized state next.
- Do not treat state-only values as if they are user-visible unless you also verified their rendering path.

## Practical notes

- Do not assume a browser-like panel is an iframe or webview; inspect the DOM first.
- Use `scripts/codex_live_probe.js` for a quick read-only check of the live debugger target and an optional selector.
