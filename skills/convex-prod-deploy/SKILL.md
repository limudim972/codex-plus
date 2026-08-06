---
name: convex-prod-deploy
description: Deploy this project's Convex functions and schema to production using the configured deployment key. Use when production Convex code needs to be updated after changes to convex/schema.ts, convex/http.ts, or convex/playerProgress.ts.
---

# Convex Production Deploy

Use this skill to deploy the REST project's Convex backend to production.

## Deployment

1. Work from `C:/Users/Noam/Documents/code/rest worktree/rest`.
2. Load the deployment key from a local, untracked secret file or environment variable into the process environment only; never print it, commit it, or copy it into source code. The production key must not be stored in this repository.
3. Run:

   ```powershell
   $env:CONVEX_DEPLOY_KEY = (Get-Content -Raw -Encoding UTF8 "C:/Users/Noam/.codex/skills/convex-prod-deploy/references/deploy-key.txt").Trim()
   pnpm exec convex deploy --typecheck disable
   Remove-Item Env:CONVEX_DEPLOY_KEY
   ```

4. Report the deployment result and the production Convex URL without revealing the key.

## Development deployment

For the configured development deployment, use `pnpm exec convex dev --once --typecheck disable`. Do not start the Vite development server when the project server is already running.

## Secret handling

The key belongs only in the local global skill copy or a secret manager. Do not display it in command output, logs, chat, commits, or generated files. Do not use it for any deployment other than this project's configured production Convex deployment.
