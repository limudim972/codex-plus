# Runtime Files

Use these files when changing how Codex launches or renders RTL.

## Launcher chain

- `C:\Users\Noam\AppData\Local\Codex RTL Fix\runtime\launch-codex-rtl.vbs`
  - Starts PowerShell with the Codex RTL runtime.
  - Usually only hands off to the patch script.

- `C:\Users\Noam\AppData\Local\Codex RTL Fix\runtime\patch.ps1`
  - Verifies bundled module hashes.
  - Chooses whether to install, restore, or launch Codex RTL.
  - Must be updated whenever the payload file changes.

- `C:\Users\Noam\AppData\Local\Codex RTL Fix\runtime\src\codex\rtl-payload.ps1`
  - Contains the runtime DOM logic that applies RTL behavior.
  - This is where to change target selectors, title markers, badges, and direction logic.

## What to edit for RTL changes

- Add or update surface selectors in the payload.
- Set or refine `dir="rtl"` on the target surface.
- Adjust `text-align` and `unicode-bidi` for blocks, lists, and blockquotes.
- Keep code blocks and technical islands LTR.
- Add or remove visible markers such as `HE` only if needed for verification.
- Update the hash entry in `patch.ps1` after any payload edit.

## Common checks

- If the launcher fails with a hash mismatch, the payload changed but the manifest did not.
- If the RTL fix works only until restart, the change likely needs to stay in `rtl-payload.ps1`.
- If the visible marker is confusing, hide it after verification and keep only the RTL logic.
