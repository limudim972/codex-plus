---
name: codex-rtl
description: Modify the local Codex RTL runtime, launcher, and payload; use when changing Hebrew/Arabic layout behavior, title badges, surface selectors, or launch-time RTL persistence.
---

# Codex RTL

## Purpose

Use this skill when Codex RTL behavior needs to persist across launches. This skill focuses on the local runtime bundle, launcher, and payload that make the app render RTL correctly.

## RTL Runtime Files

When the user asks to make Codex RTL, modify the local runtime bundle that drives the launcher and payload:

- `C:\Users\Noam\AppData\Local\Codex RTL Fix\runtime\launch-codex-rtl.vbs`
- `C:\Users\Noam\AppData\Local\Codex RTL Fix\runtime\patch.ps1`
- `C:\Users\Noam\AppData\Local\Codex RTL Fix\runtime\src\codex\rtl-payload.ps1`

Treat these as the main Codex RTL implementation points:

- `launch-codex-rtl.vbs` starts the PowerShell runtime.
- `patch.ps1` verifies bundled module hashes and chooses the launch path.
- `src/codex/rtl-payload.ps1` contains the actual DOM/runtime RTL behavior.

When updating RTL behavior, check for these kinds of changes:

- surface selectors for the target UI
- `dir`, `text-align`, and `unicode-bidi` handling
- title badges or other visible confirmation markers
- any module hash entries in `patch.ps1` that must be updated after payload edits

## Practical Rules

- Always fix the live Codex surface first when it is running, then verify the change in the UI, and only after that update the persisted runtime script.
- If the live surface cannot be reached, note that explicitly and fall back to script changes with a verification step once the app relaunches.
- Keep unrelated surfaces stable while changing the target surface.
- If a title badge duplicates, normalize the title suffix before writing it again.
- If a marker is visible only as a debug aid, keep it hidden once RTL is confirmed.
- If the runtime payload changes, update the manifest hash in `patch.ps1` before expecting the launcher to accept it.

## References

- See [Runtime Files](references/runtime-files.md) for the Codex RTL launcher and payload locations.
