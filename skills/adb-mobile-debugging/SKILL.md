---
name: adb-mobile-debugging
description: Debug local web applications on real Android devices over USB using ADB, including device authorization, reverse-port mapping, screenshots, Chrome remote debugging, and mobile layout or interaction verification. Use when Codex needs to test a localhost site on an Android phone, inspect Chrome on a connected device, reproduce mobile-only behavior, or collect Android browser evidence.
---

# ADB Mobile Debugging

Use this skill to verify a local web app on an authorized Android device. Prefer read-only inspection and reversible port mappings. Keep generated screenshots, UI dumps, and diagnostic logs in the workspace `temp/` directory.

## Workflow

### 1. Confirm the device

Run:

```powershell
adb devices -l
```

Continue only when the intended device appears with state `device`. If the list is empty, ask the user to connect and unlock the phone. If the state is `unauthorized`, ask the user to accept the USB debugging authorization prompt. Do not inspect unrelated devices when multiple devices are attached; select one explicitly with `adb -s <serial>`.

Record the device model and serial before testing.

### 2. Expose the local server

For a local server on port `3001`, map the computer port to the Android loopback interface:

```powershell
adb -s <serial> reverse tcp:3001 tcp:3001
adb -s <serial> reverse --list
```

Then the phone can use `http://127.0.0.1:3001/...`. Preserve the exact path and query parameters supplied by the user. Do not start or restart a development server when one is already running.

For another port, replace both port values. At the end of a test session, remove only mappings created by this session when they are no longer needed:

```powershell
adb -s <serial> reverse --remove tcp:3001
```

### 3. Open the page

If the environment allows an intent launch and the user asked to open the page, use Chrome with the exact URL. If launch commands are blocked by the host policy, start Chrome with:

```powershell
adb -s <serial> shell monkey -p com.android.chrome 1
```

Then give the user the local URL and ask them to open it manually. Do not repeatedly retry `adb shell input` commands when Android reports `INJECT_EVENTS`; this means the device blocks automated touch or key injection.

### 4. Capture visual and UI evidence

Save all artifacts under the workspace `temp/` directory:

```powershell
adb -s <serial> exec-out screencap -p > "temp/android-current.png"
adb -s <serial> shell uiautomator dump /sdcard/window-current.xml
adb -s <serial> shell cat /sdcard/window-current.xml > "temp/android-window-current.xml"
```

Use the image viewer for screenshots. Inspect UI XML only when it answers a focused question; do not dump or search broad device data.

### 5. Inspect Chrome through DevTools

When Chrome remote debugging is available, forward its DevTools endpoint:

```powershell
adb -s <serial> forward tcp:9223 localabstract:chrome_devtools_remote
Invoke-RestMethod "http://127.0.0.1:9223/json/list"
```

Select a `type: page` target by its exact URL or title. Inspect the target with Chrome DevTools Protocol or an available browser-control surface. For responsive web issues, collect:

- `window.innerWidth` and `window.innerHeight`
- `window.visualViewport` dimensions and scale
- the viewport meta tag
- `document.documentElement.scrollWidth` versus `clientWidth`
- overflowing elements and their computed styles
- console errors relevant to the page

Do not navigate or close unrelated user tabs. If the target list contains several copies of the same page, identify the correct target by URL, title, and current state before interacting.

Remove the forwarding created for the session when finished:

```powershell
adb -s <serial> forward --remove tcp:9223
```

## Failure handling

- `no devices/emulators found`: verify the cable, USB mode, unlock state, and USB debugging.
- `unauthorized`: wait for and accept the device authorization prompt, then rerun `adb devices -l`.
- `INJECT_EVENTS` or an input-security exception: stop automated touch/key attempts and ask the user to perform the interaction on the phone.
- Localhost does not load: verify the server is listening, confirm `adb reverse --list`, and check that the phone URL uses `127.0.0.1` with the mapped port.
- DevTools JSON is available but WebSocket attachment fails: keep the reverse/forward diagnostics, ask the user to leave the target page open, and report that the device page could not be controlled automatically.

## Evidence standards

Report concrete observations: device serial/model, mappings, exact URL, target title, screenshot path, viewport metrics, and the reproduced behavior. Distinguish clearly between what ADB confirmed and what was inferred from the page or screenshot. Do not claim a mobile bug is fixed solely from desktop emulation; verify on the physical device when the user requests real-device validation.
