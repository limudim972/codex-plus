# Codex Plus

**A local enhancement layer for Codex Desktop on Windows.**

Codex Plus is based on the upstream [`codex-rtl-fix`](https://github.com/Ben-Boaron0/codex-rtl-fix) repository and extends that foundation for our own Codex-enhancement workflow.

Codex Plus installs a small local runtime that launches Codex through `Codex Plus` shortcuts, opens a loopback-only DevTools port, and injects an idempotent runtime patch into the renderer. It does not modify the Microsoft Store package under `WindowsApps`.

## Attribution

This project is derived from [`Ben-Boaron0/codex-rtl-fix`](https://github.com/Ben-Boaron0/codex-rtl-fix). We keep that upstream work as the technical foundation for Codex Plus.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6.svg)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE.svg)](#requirements)

## What It Does

- Creates `Codex Plus` shortcuts that launch Codex with local enhancement injection.
- Leaves text direction and bidirectional layout to Codex’s native RTL support.

## Requirements

| Requirement | Notes |
| :--- | :--- |
| **Windows 10 / 11** | Codex Desktop installed |
| **Windows PowerShell** | Windows PowerShell 5.1 (`powershell.exe`) or PowerShell 7 (`pwsh`) |
| **Administrator** | Not required for the normal install flow |

## Quick Install

Open **Windows PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/limudim972/codex-plus/main/install.ps1 | iex
```

The installer downloads `patch.ps1`, stages the required module files, and opens the Codex Plus menu without prompting for elevation by default.

## If You Prefer To Run From A Local Checkout

```powershell
git clone https://github.com/limudim972/codex-plus.git
cd codex-plus
powershell.exe -ExecutionPolicy Bypass -File .\patch.ps1
```

The local installer can reserve an exact DevTools port before opening the new Codex Plus window:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -LocalDev -Port 30113
```

The installer stops if that loopback port is already in use; it does not switch to another port.

## How It Works

Codex Plus keeps the Microsoft Store installation untouched and works entirely through a local runtime under `%LOCALAPPDATA%\Codex Plus`.

At patch time it:

1. Copies the signed runtime files into the local runtime folder.
2. Creates or refreshes `Codex Plus` shortcuts in writable user-facing locations.
3. Launches Codex with:
   - `--remote-debugging-port=<port>`
   - `--remote-debugging-address=127.0.0.1`
4. Injects the remaining Codex Plus enhancements through DevTools:
   - `Page.addScriptToEvaluateOnNewDocument` for future documents
   - `Runtime.evaluate` for the currently open document

The payload is idempotent and reapplies itself when Codex recreates relevant DOM surfaces.

## Menu

When you run the tool, the menu offers:

```text
Codex Desktop: Found

  1. Patch Codex Plus
  2. Restore Codex Plus
  3. Exit
```

- `Patch Codex Plus` installs the local runtime, creates or refreshes `Codex Plus` shortcuts, and relaunches Codex with enhancements if needed.
- `Restore Codex Plus` removes the local runtime launcher artifacts and owned `Codex Plus` shortcuts.

## Using It

- Launch Codex through a `Codex Plus` shortcut when you want the enhanced runtime.
- Launch the same `Codex Plus` shortcut again to restart only that shortcut's own session; other Codex sessions stay open.
- Launch Codex through the normal Codex shortcut when you want the unpatched app.
- If Codex is already open during patch or restore, the tool may restart it so the runtime state is consistent.

## Troubleshooting

**Codex Desktop was not found**

Install or reopen Codex Desktop, then run Codex Plus again.

**Codex Plus enhancements are not visible**

Launch Codex through a `Codex Plus` shortcut, not the original Codex shortcut. If the shortcut is missing, run `Patch Codex Plus` again.

**Controlled Folder Access warns about Codex**

Codex Plus stores its runtime under `%LOCALAPPDATA%\Codex Plus` and launches Codex with local DevTools flags so it can inject enhancements. If Controlled Folder Access is enabled, allow Codex or keep Codex workspaces outside protected folders.

**Windows PowerShell shows `Import-Module ... AuditToString is already present`**

This is a cosmetic warning from the Appx module when running under PowerShell 7. It does not affect the tool. You can safely ignore it, or switch to Windows PowerShell (`powershell.exe`) to suppress it.

## Build a Single-EXE Installer

On Windows, run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\build-exe-installer.ps1
```

This creates `dist\CodexPlus-Setup.exe`, a self-extracting installer containing the checked-in PowerShell runtime and modules. Codex Desktop must already be installed, but the end user only needs to run the one EXE. The default IExpress build requires only Windows; the alternative .NET builder requires the .NET 8 SDK.

### Installer files

| File | Needed to build the EXE? | Needed by the end user? | Purpose |
|---|---:|---:|---|
| `build-exe-installer.ps1` | Yes | No | Builds the Windows IExpress EXE. |
| `install.ps1` | Yes | No | Embedded installer entry point. |
| `patch.ps1` | Yes | No | Embedded runtime setup and menu logic. |
| `src/**/*.ps1` | Yes | No | Embedded runtime modules and Codex Plus features. |
| `dist/CodexPlus-Setup.exe` | No | Yes | The only Codex Plus file the end user needs to run. |

The EXE temporarily extracts the embedded scripts during installation and removes them afterward. The original `src/`, `install.ps1`, and `patch.ps1` files are not copied beside the EXE.

## Graphics Driver Check

Codex Plus checks the current Windows graphics-adapter status before launching from the desktop shortcut. If the adapter is missing or unhealthy, Plus asks whether to open the official driver-update page for the detected manufacturer. The same driver/version warning is suppressed for seven days after it is shown, and the check never installs a driver automatically.

Plus also checks for an existing Codex process whose threads remain suspended for at least five seconds while it has no visible window. In that case it stops the new launch and recommends uninstalling Codex, rebooting Windows, and reinstalling it from the Microsoft Store.

## Version Compatibility Gate

After Codex Desktop updates, launch a fresh Codex Plus instance from the current Codex chat. Resolve its new debug port/profile pair, then run:

```powershell
powershell.exe -NoProfile -File tools\test-codex-version-compatibility.ps1 -Port <new-port> -ExpectedProfile "<new-profile>"
```

The runner never launches or terminates Codex. It first runs every checked-in offline test, then attaches only to the supplied live instance and verifies the injected globals, sidebar DOM, React app scope, React Router navigator, current bundled navigation modules, local app-server manager, and real synthetic-thread navigation while the source project stays closed.

A complete pass is recorded at `%LOCALAPPDATA%\Codex Plus\compatibility.json` with the installed Codex package version and a fingerprint of the checked-in Codex Plus runtime. A new Codex version or runtime change requires another live pass. Use `-Force` to repeat the live check for the same combination, or `-OfflineOnly` to run only the fast regression suite.

## Security And Verification

`install.ps1` downloads `patch.ps1` and the module files it needs, then stages them locally before running the patch. `patch.ps1` still pins SHA-256 hashes for every dot-sourced module it loads.

For local development, run the installer from a checkout you trust and review the files in `src/` before patching a machine you care about.

## Support Status

> [!CAUTION]
> This tool changes desktop app behavior in unsupported ways. Use it at your own risk.

By using it, you accept that:

1. You trust the code you are running on your machine.
2. Modifying Codex behavior may not align with vendor support expectations or terms.
3. Enhancements depend on launching Codex through Codex Plus-created shortcuts.
4. This is a stopgap until Codex provides native RTL support.

## License

MIT
