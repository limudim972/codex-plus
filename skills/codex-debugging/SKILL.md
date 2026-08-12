---
name: codex-debugging
description: Inspect and verify Codex Plus surfaces and debugger targets in a newly launched isolated Plus window; use when checking the app, finding the correct DOM target, or validating live behavior. Never attach to a pre-existing user window unless the user explicitly identifies that window and directs inspection there.
---

# Codex Debugging

## Purpose

Use this skill when you need to inspect a running Codex process, confirm which surface is active, or verify that a UI change landed in the right document.

This repo-local copy includes a Codex Plus method for attaching to an already-running desktop instance through its loopback DevTools port.

## Window isolation rule

- Use the debugger only on a fresh Codex Plus window launched by the agent for the current verification.
- Before launch, record all existing `--remote-debugging-port` and `--user-data-dir` pairs without attaching to their DevTools targets. Treat them as user windows and exclude them from inspection.
- After launch, attach only to the newly created port/profile pair and its exact `app://-/index.html` target.
- If the launcher fails to create a new renderer, reuses an existing window, or the fresh renderer exits, stop. Do not fall back to a pre-existing window.
- A user may override this rule only by explicitly directing inspection of a specific existing window, port, profile, or ordinal. A general request to inspect or verify the app is not an override.
- A window the agent launched earlier in the same verification remains an eligible test window. Close or replace only agent-created windows when a fresh runtime load is required.

## Workflow

1. Record existing Codex Plus process identities before launch, but do not attach to or inspect their debugger targets.
2. Launch Codex Plus through the Desktop installer only when live verification actually requires a new renderer/runtime instance—most importantly after changes to the Codex payload, injected UI, or other behavior that is loaded only during startup. Do not launch a new instance merely because installer files, the session monitor, or another background/runtime script changed; those changes can be verified with source/runtime checks and tests, and already-open Plus windows will not load them until they are closed and a new one is started.
   - Prefer the Desktop shortcut at Desktop\Codex Plus Install Local.lnk.
   - The installer runs the local checkout with `-LocalDev`, synchronizes the installed runtime, and launches a fresh Codex Plus window. Do not separately copy runtime files or inject the changed script into an existing window.
   - Run the local installer synchronously so it chooses a free random port and returns it on stdout. Capture the machine-readable `CODEX_PLUS_LAUNCH_PORT=<port>` line; do not scan the post-launch process list to discover the port:
     ```powershell
     $repoRoot = 'C:\Users\Noam\Documents\code\codex-plus'
     $launchOutput = & (Join-Path $repoRoot 'Codex Plus Install Local.bat') 2>&1
     $portLine = @($launchOutput | Where-Object { $_ -match '^CODEX_PLUS_LAUNCH_PORT=(\d+)$' }) | Select-Object -Last 1
     if (-not $portLine) { throw 'Codex Plus installer did not return a launch port.' }
     $requestedPort = [int](($portLine -split '=', 2)[1])
     ```
   - The installer checks the selected loopback port before launch and returns the exact port only after starting the fresh window.
   - After launching a fresh Plus window, wait 60 seconds before attaching to its debugger or inspecting its UI. This gives the launcher, profile, splash flow, and renderer time to settle.
   - Do not launch raw ChatGPT.exe when the goal is to reproduce Codex Plus runtime behavior.
   - The installer and launcher set up the scoped profile, requested debug port, splash helper, and watchdog flow used by Codex Plus.
   - Before launching, record the existing Codex Plus --remote-debugging-port and --user-data-dir pairs.
   - After launch, use the returned port and attach only to the matching newly appeared port/profile pair, not to any pre-existing Codex window.
   - If you updated a Codex payload or injected renderer behavior, do not inject the script into an already-open page; launch a fresh Plus window and verify the change there.
   - For installer, launcher, session-monitor, or other non-renderer runtime changes, do not launch or restart a Plus window unless the user explicitly requests live verification. Record that existing windows retain the old loaded code and that the change will apply to the next fresh launch.
3. Resolve the debug port only for the fresh agent-launched Codex instance.
   - Check the running `ChatGPT.exe` command line for `--remote-debugging-port=...`.
   - Use the launcher-scoped port for the new instance you are inspecting.
   - Pair the port with the matching `--user-data-dir` so you stay attached to the intended window.
   - If you just launched a fresh window, restrict attachment to the port/profile pair that did not exist before launch.
   - Do not assume `18317` or use a saved state port belonging to an older window.
4. Open the debugger list from `http://127.0.0.1:<port>/json/list` or the IPv6 loopback equivalent when needed.
5. Identify the active surface:
   - main chat surface
   - tabpanel or other app panel
   - browser/resource panel
   - separate frame or target, if present
6. Verify the exact node or state source before changing behavior.
   - Use stable selectors for the relevant surface.
   - Do not assume a browser-like panel is an iframe or webview.
   - Do not trust a window title, launcher result, or saved state file by itself; verify the fresh session by matching the live process, debug port, user-data-dir, and visible window title together before you inspect the DOM.
7. Verify live results in DevTools.
   - Check computed `direction`, `text-align`, and `unicode-bidi` when relevant.
   - Confirm the target surface exists and is the one you expect.
8. If the UI does not visibly expose the data you need, inspect client-side state separately from the rendered DOM.
9. Use the live probe script or the PowerShell helper for a quick read-only check of the current debugger target.

## Codex Plus Method

When working inside this repo, prefer the checked-in helper at `tools/invoke-codex-devtools.ps1`.

Use it only after selecting the exact fresh Codex Plus window launched for the current verification.

Examples:

```powershell
powershell -NoProfile -File tools\invoke-codex-devtools.ps1 -Port 18320 -Expression "document.title"
```

```powershell
powershell -NoProfile -File tools\invoke-codex-devtools.ps1 -Port 18320 -Expression "JSON.stringify(Array.from(document.querySelectorAll('div[data-app-action-sidebar-project-row]')).map((row) => ({ text: row.innerText, id: row.getAttribute('data-app-action-sidebar-project-id') })))"
```

Use this method before adding new launcher logic when the goal is inspection only.

### Port resolution

When resolving the fresh launch port:

- diff the pre-launch and post-launch `ChatGPT.exe` process sets and read `--remote-debugging-port=...` only from the newly created process
- require the matching new `--user-data-dir` for the launcher-scoped instance
- infer the live port from the visible browser-process command line before trusting `Codex Plus\state.json`
- if a saved state port and the live process port disagree, use the live process port
- when launching a new window for debugging, diff the before/after process list and use only the newly introduced port/profile pair
- if multiple Codex Plus windows are open, exclude every pair that existed before the current launch
- if no unique new pair exists, stop instead of attaching to an older window

### Inspection order

1. Check the DevTools target list for the chosen port.
2. Confirm the active `page` target is the Codex app page, usually `app://-/index.html`.
3. Query the DOM for the surface you care about.
4. If the DOM is insufficient, inspect client-side state or global stores next.
5. Only after that should you decide whether launcher/runtime changes are needed.

### Avatar overlay and duplicate page targets

Fresh Codex Plus profiles can expose more than one `page` target on the same debug port. A common pair is:

- `app://-/index.html?initialRoute=/avatar-overlay` — the transient avatar/splash overlay.
- `app://-/index.html` — the real Codex renderer containing the sidebar and conversation surface.

Both targets can have the title `Codex`, so never select the first page by title or list order. Query `/json/list`, then select the target whose URL is exactly `app://-/index.html` (without `initialRoute` or another query string). Preserve its exact target `id` and use that ID with the helpers:

```powershell
$targets = Invoke-RestMethod -Uri 'http://127.0.0.1:<port>/json/list' -UseBasicParsing
$targets | Where-Object { $_.type -eq 'page' } | Select-Object id,title,url

powershell.exe -NoProfile -File tools\invoke-codex-devtools.ps1 `
  -Port <port> -Id <main-page-id> -Expression "location.href"

powershell.exe -NoProfile -File tools\invoke-codex-devtools-mouse.ps1 `
  -Port <port> -Id <main-page-id> -X 260 -Y 399
```

If only the avatar-overlay page exists, wait and re-query `/json/list` on the same port. If the exact main page appears, attach to that new target. If the overlay remains after the launcher settling window, record the fresh live verification as incomplete; do not silently attach to an older Codex Plus window. Do not use computer-use to click or dismiss the overlay: Codex desktop automation is outside that skill's allowed scope.

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
   - Prefer a fresh launcher-scoped Plus copy over hot script injection whenever you need to verify a local runtime change.

When writing down verification results, prefer concrete observations over impressions:

- which process and debug port were used
- which surface or list was inspected
- what the initial state was
- what interaction was triggered
- what changed afterward
- whether the result still held after restart

### Codex Plus UI-specific checks

- Do not treat `data-app-action-sidebar-thread-active` as the only proof that a synthetic thread opened. Confirm the URL, conversation id, composer content, project label, and other live composer markers as well.
- Preserve the full identity of every inspected window as a tuple of `port`, matching `--user-data-dir`, and window ordinal. When comparing old and new windows, attach only to the port/profile pair introduced by the fresh launch.
- A fresh Plus profile may initially show `avatar-overlay`; follow the duplicate-target procedure above and verify the exact main page target before inspecting the composer.
- For visual comparisons, measure the actual UI as well as its text: use `getBoundingClientRect()`, computed height and width, classes, icon presence, `pointer-events`, and `tabindex`. Compare the same composer row in the old and new windows.
- Persistent composer snapshots are session state. When their structure changes, bump the storage key version so stale serialized markup cannot make a new runtime appear unchanged.
- Distinguish the live composer controls from the persistent informational copy. A persistent control with `pointer-events: none` is not an interactive source of truth and must not be clicked during verification.
- When testing a synthetic-row click, target the real descendant with `role="button"` when present, rather than assuming the outer `role="listitem"` wrapper owns the click handler.
- Context that must survive the native new-chat navigation cannot rely only on `window` globals. Persist it in `sessionStorage`, and clear it only after the live composer itself reflects the restored project and other settings.

## Practical Rules

- Prefer debugger verification in a fresh agent-launched Codex Plus window; never reuse a user window for convenience.
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
- For open/close controls, verify both directions explicitly:
  - capture the expanded state and visible list before clicking
  - click the exact control you inspected
  - confirm `aria-expanded`, hidden state, and list visibility after collapse
  - click again and confirm the state returns to the original open form
- When validating data-bearing surfaces:
  - do not assume visible text is the full source of truth
  - confirm whether the required value lives in attributes, adjacent nodes, or client state
  - record whether your conclusion came from DOM inspection or state inspection

## References

- See [Probe Script](scripts/codex_live_probe.js) for the read-only debugger probe.
- See `tools/invoke-codex-devtools.ps1` for the Codex Plus live DevTools helper.
