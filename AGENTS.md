# AGENTS.md
- IMPORTANT: when changing repo code that affects runtime behavior, update both the checked-in source and the installed desktop/runtime copy together so Codex Plus stays in sync.
- When changing repo code that affects runtime behavior, update the checked-in source and the installed desktop/runtime copy together so the deployed Codex Plus behavior stays in sync with the repo.
- After changing repo code, allways update the live runtime code and launch a fresh Codex Plus instance and verify the live result before reporting completion.
- Keep reusable helper scripts under `tools/`.
- For live Codex Plus app debugging in this repo, inspect already-running debug ports with `tools/invoke-codex-devtools.ps1` before adding new launcher logic or assuming the current DOM shape.
- Treat `skills/codex-debugging/` as the repo-owned source of Codex Plus debugging guidance for this project.
- Use `scratch/` for temporary throwaway files and local experiments.
- When the use write C it mean commit.
must read skills\codex-debugging\SKILL.md first before doing anything related to codex plus.
