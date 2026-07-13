# Codex Desktop internals discovered during Codex Plus navigation work

This records the current Codex Desktop behavior investigated for reliable clicks on Codex Plus-created synthetic thread rows. These are private implementation details and can change between releases.

## Runtime and ASAR

Codex Desktop is an Electron application. Its bundled web UI normally runs at `app://-/index.html` and is stored in an `app.asar` archive under the installed WindowsApps directory.

Codex Plus debug instances use a loopback port, a scoped user-data directory, and a window ordinal:

```text
--remote-debugging-port=<port>
--remote-debugging-address=127.0.0.1
--user-data-dir=<profile>
--codex-plus-window-title-ordinal=<ordinal>
```

The port and profile must be paired because multiple Codex windows may be running. The repository ASAR helpers in `src/shared/asar.ps1` read archive entries without unpacking or modifying the application.

Important shipped assets included:

```text
sidebar-thread-navigation-<hash>.js
app-server-manager-signals-<hash>.js
use-navigate-to-local-conversation-<hash>.js
worktree-init-row-<hash>.js
development-<hash>.js
src-<hash>.js
```

Hashes are release-specific, so runtime code should resolve names from the main script using stable prefixes.

## React fibers and app scope

React attaches an internal fiber to rendered elements under a property beginning with `__reactFiber$`. Fibers expose `memoizedProps`, `memoizedState`, `return`, and `child`.

Walking `return` follows component ancestry. Walking a function component's hook list follows `memoizedState`, then `next`.

The mounted Codex app scope is held in React hook state. The useful object has this shape:

```text
candidate.node.store
candidate.get
candidate.set
```

It is accessed with `scope.get(signal, key?)` and `scope.set(signal, value)`. It is not a stable global. A real Codex-rendered sidebar row is the safest fiber starting point; synthetic rows may not own a fiber.

## Thread IDs and locations

Codex uses local thread keys such as `local:<conversation-id>`. Synthetic rows generally store the bare conversation ID. The implementation trims, lowercases, and removes a leading `local:` or `remote:` prefix before using an ID.

Sidebar location values include:

```text
project:<project-id>
flat-chats
```

These describe sidebar selection state. They are not the main conversation URL.

## Native thread navigation

The sidebar navigation module and app-server manager perform separate parts of navigation.

The app-server side is equivalent to:

```text
manager = scope.get(appServer.c, 'local')
appServer.Et(scope, conversationId, 'local')
manager.activateThreadSummary(conversationId)
```

`manager.getConversation(conversationId)` can be used as a sanity check when available.

The sidebar navigation module's `navigation.t` updates the internal sidebar route/location. It does not, by itself, change the main conversation.

The native row component, found in `worktree-init-row-<hash>.js` (minified as `rr`), effectively does:

```text
dispatch/prepare navigation
onBeforeNavigate()
activateThreadSummary(conversationId)
navigateToLocalConversation(conversationId)
startTransition(() => {
  onSelect()
  onClick()
})
```

The missing operation in the first direct implementation was `navigateToLocalConversation`.

## React Router

`use-navigate-to-local-conversation-<hash>.js` wraps React Router's `useNavigate` hook. The imported route builders reduce to:

```text
Ui(value) = value
Tt(value) = '/local/' + value
```

The router was not exposed as a usable `window.__reactRouterDataRouter` in the investigated page. The mounted router provider was visible through fiber props, however. Its props contained `location` and a `navigator` with:

```text
createHref
createURL
encodeLocation
push
replace
go
listen
```

The native-equivalent main-view transition is:

```text
routerNavigator.push('/local/' + conversationId)
```

This is distinct from updating the sidebar route atom.

## Why the first attempt looked successful

The first direct path activated the thread and called the sidebar navigation function. That changed internal sidebar atoms and could leave a project collapsed, but the main conversation stayed on the previous thread because React Router had not moved.

A native click changed the main content. Therefore the reliable verification signal is rendered conversation content, not only sidebar state.

## Synthetic rows

Codex Plus-created rows use attributes including:

```text
data-codex-plus-sidebar-synthetic-row
data-codex-plus-thread-id
data-codex-plus-source-list-label
data-codex-plus-source-row-text
data-codex-plus-thread-wired
```

They can contain cloned or wrapped native row markup. Nested native attributes may therefore describe a different original row than the outer synthetic target. The outer synthetic row's thread ID is the intended target.

The handler stops the synthetic event from being treated as a click on the nested native row, tries direct Codex navigation, and falls back to locating the source row and expanding the project/list if internal objects cannot be found.

## Current direct algorithm

```text
1. Read the synthetic row conversation ID.
2. Find a real sidebar React fiber.
3. Find the app scope from React hooks.
4. Resolve sidebar-navigation and app-server modules dynamically.
5. Find the mounted React Router navigator in fiber props.
6. Get the local app-server manager.
7. Activate the thread summary.
8. Push /local/<conversation-id> through React Router.
9. Update Codex sidebar route/location state.
10. Use the source-row fallback if an internal step is unavailable.
```

The implementation is in `src/codex/sidebar-paging.ps1`. The installed copy must stay synchronized at `C:\Users\Noam\AppData\Local\Codex Plus\runtime\src\codex\sidebar-paging.ps1`.

## Verification rules

- Inspect existing debug ports and profile pairs before restarting.
- Use repository DevTools helpers for read-only inspection.
- Use real mouse input for UI clicks.
- Do not use a live script-injection helper as a test mechanism.
- After runtime changes, launch a fresh Plus instance through the installed launcher Desktop\Codex Plus.lnk
- Verify the exact synthetic row and its initial state.
- Verify the main conversation title/content after clicking.
- Verify the project remains collapsed/hidden when that is part of the test.

The decisive check is: before, the main view shows conversation A; after a real click on the synthetic row for B, the main view shows conversation B.

## Working-thread spinner

Native thread rows expose their React `statusState` through the live row fibers. A thread that is currently working has `statusState.type === "loading"`; this is independent of whether that thread is the currently selected route. The native row may therefore be working while `isActive` is false.

Synthetic rows still mirror selection with `data-app-action-sidebar-thread-active="true"` and `aria-current="page"`, but `syncSyntheticThreadActiveState()` builds a separate working-thread set from native sidebar rows and their React fibers. It preserves Codex's native `.animate-spin` indicator and adds the Plus fallback spinner when a working native row has no indicator; the same working ID drives the synthetic mirror, so changing the selected synthetic thread does not move the spinner.

Both indicators are attached to the inner thread button, not the outer drag/list wrapper. The Plus fallback uses the native `52px` right-side indicator geometry and remains visible while the row is hovered. Synthetic labels prefer the matching native row's rendered title by thread ID, with the snapshot title used only as a fallback.

## Fragility notes

React fiber names, hook layouts, minified names, ASAR hashes, app-scope signal shapes, router nesting, local/remote route formats, and synthetic row markup can all change. Feature-detect methods and preserve the source-row fallback. Never treat a sidebar route update alone as proof that the main conversation opened.
