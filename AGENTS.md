# AGENTS.md

- In Codex Plus RTL launcher work, treat the absolute shortcut path as the launcher identity. A raw `.lnk` copy does not create a new instance by itself unless the shortcut is regenerated or rewritten so it carries its own path-derived launcher key.
- When changing launcher behavior, verify both the shortcut payload and the resulting `CODEX_PLUS_LAUNCHER_KEY` / per-launcher profile path.
