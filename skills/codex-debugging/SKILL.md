---
name: codex-debugging
description: Inspect and verify live Codex surfaces, debugger targets, and browser-like panels; use when checking the running app, finding the correct DOM target, or validating view behavior without changing the RTL runtime.
---

# Codex Debugging

## Purpose

Use this skill when you need to inspect a running Codex process, confirm which surface is active, or verify that a UI change landed in the right document.

This repo-local copy includes a Codex Plus method for attaching to an already-running desktop instance through its loopback DevTools port.

## Workflow

1. Inspect the running Codex target before restarting anything.
2. If a live UI change is requested, fix the running surface first, verify it in the live UI, and only then change the persisted script or launcher.
3. Launch Codex Plus through the installed launcher path when you need a fresh Plus window.
   - Prefer `C:\Users\Noam\AppData\Local\Codex Plus\runtime\launch-codex-plus.vbs` or an installed `Codex Plus.lnk`.
   - Do not launch raw `ChatGPT.exe` when the goal is to reproduce Codex Plus runtime behavior.
   - The launcher sets up the scoped profile, debug port, splash helper, and watchdog flow used by Codex Plus.
   - Before launching, record the existing Codex Plus `--remote-debugging-port` and `--user-data-dir` pairs.
   - After launching, attach only to the newly appeared port/profile pair, not to any pre-existing Codex window.
4. Resolve the active debug port for the running Codex instance.
   - Check the running `ChatGPT.exe` command line for `--remote-debugging-port=...`.
   - If working in Codex Plus, prefer the launcher-scoped port for the instance you are inspecting.
   - Pair the port with the matching `--user-data-dir` so you stay attached to the intended window.
   - If you just launched a fresh window, restrict attachment to the port/profile pair that did not exist before launch.
   - Do not assume `18317` or the saved state port; use the actual live port when one is already running.
5. Open the debugger list from `http://127.0.0.1:<port>/json/list` or the IPv6 loopback equivalent when needed.
6. Identify the active surface:
   - main chat surface
   - tabpanel or other app panel
   - browser/resource panel
   - separate frame or target, if present
7. Verify the exact node or state source before changing behavior.
   - Use stable selectors for the relevant surface.
   - Do not assume a browser-like panel is an iframe or webview.
8. Verify live results in DevTools.
   - Check computed `direction`, `text-align`, and `unicode-bidi` when relevant.
   - Confirm the target surface exists and is the one you expect.
9. If the UI does not visibly expose the data you need, inspect client-side state separately from the rendered DOM.
10. Use the live probe script or the PowerShell helper for a quick read-only check of the current debugger target.

## Codex Plus Method

When working inside this repo, prefer the checked-in helper at `tools/invoke-codex-devtools.ps1`.

Use it to attach to an already-running Codex Plus window that was launched with `--remote-debugging-port`.

Examples:

```powershell
powershell -NoProfile -File tools\invoke-codex-devtools.ps1 -Port 18320 -Expression "document.title"
```

```powershell
powershell -NoProfile -File tools\invoke-codex-devtools.ps1 -Port 18320 -Expression "JSON.stringify(Array.from(document.querySelectorAll('div[data-app-action-sidebar-project-row]')).map((row) => ({ text: row.innerText, id: row.getAttribute('data-app-action-sidebar-project-id') })))"
```

Use this method before adding new launcher logic when the goal is inspection only.

### Port resolution

When the port is unknown:

- inspect running `ChatGPT.exe` processes and read `--remote-debugging-port=...`
- prefer the process with the matching `--user-data-dir` for the launcher-scoped instance you care about
- infer the live port from the visible browser-process command line before trusting `Codex Plus\state.json`
- if a saved state port and the live process port disagree, use the live process port
- when launching a new window for debugging, diff the before/after process list and use only the newly introduced port/profile pair
- if multiple Codex Plus windows are open, keep the port and `user-data-dir` paired so you inspect the correct window

### Inspection order

1. Check the DevTools target list for the chosen port.
2. Confirm the active `page` target is the Codex app page, usually `app://-/index.html`.
3. Query the DOM for the surface you care about.
4. If the DOM is insufficient, inspect client-side state or global stores next.
5. Only after that should you decide whether launcher/runtime changes are needed.

### Verification method

Use a consistent live-verification loop when checking UI behavior:

1. Verify in the repo first when a local automated test exists.
2. Launch or attach to the real desktop surface that users run.
3. Resolve the live debug port from the running process command line, not from an assumed default.
4. Inspect the exact DOM node or state source that drives the behavior before interacting with it.
5. Record the initial state using stable facts such as attributes, visibility, text, counts, or computed styles.
6. Trigger the real interaction on the exact control you inspected.
7. Record the resulting state using the same measurements so the before and after comparison is explicit.
8. If runtime-installed files are involved, restart the desktop app and repeat the live check on the fresh instance.

When writing down verification results, prefer concrete observations over impressions:

- which process and debug port were used
- which surface or list was inspected
- what the initial state was
- what interaction was triggered
- what changed afterward
- whether the result still held after restart

## Practical Rules

- Prefer live debugger verification over restarting Codex when possible.
- Keep the scope limited to inspection and validation.
- If a marker or title is used for debugging, treat it as a diagnostic aid rather than the actual fix.
- Distinguish these three questions clearly:
  - is the app running with a live debug port
  - is the data present in client state
  - is the data rendered in the DOM
- When verifying sidebar or pager behavior, identify the exact list container first:
  - confirm the section `role="list"` and its `aria-label`
  - distinguish real pager controls from ordinary row buttons with the same text
  - check the current loaded-state attribute before and after interaction
- A UI control can look correct but still be wired to the wrong surface or wrong row:
  - do not assume a visible `Show more` label belongs to the section you care about
  - verify the pager node is the one inside the intended list, not a row action elsewhere
  - use a real mouse click or direct element click on the exact control you identified
- If a click appears to do nothing, inspect the live DOM for:
  - duplicate lists or duplicate pager rows
  - hidden buttons with the same text
  - stale state attributes that never change after the interaction
- When validating data-bearing surfaces:
  - do not assume visible text is the full source of truth
  - confirm whether the required value lives in attributes, adjacent nodes, or client state
  - record whether your conclusion came from DOM inspection or state inspection

## References

- See [Live Debugging](references/live-debugging.md) for debugger notes and verification checks.
- See [Probe Script](scripts/codex_live_probe.js) for the read-only debugger probe.
- See `tools/invoke-codex-devtools.ps1` for the Codex Plus live DevTools helper.
