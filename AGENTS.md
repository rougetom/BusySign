# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **Cloudflare Worker + Durable Object** (`busy-sign`), written in TypeScript. It serves a landscape FREE/BUSY door-sign web page and accepts microphone-status heartbeats. Standard commands live in `package.json` and `README.md`; only the non-obvious notes are captured here.

### Scope in the cloud VM
- The **Worker** (`src/`, tests in `test/`) is the in-scope service and runs fully on Linux.
- The **Mac reporter** (`mac/MicReporter.swift`, `mac/install.sh`) is macOS-only (Core Audio + menu bar app) and cannot be built or run in this Linux VM. It is out of scope here.

### Running / testing (see `package.json`)
- Dev server: `npm run dev` (wrangler dev, serves on `http://localhost:8787`). Run it in a long-lived terminal, not in `install`/`start`.
- Tests: `npm test` (vitest via `@cloudflare/vitest-pool-workers`). Typecheck: `npx tsc -p tsconfig.test.json --noEmit`.

### Non-obvious gotchas
- `.dev.vars` is gitignored and required for `npm run dev` (wrangler loads `STATUS_SECRET` from it). Create it with `cp .dev.vars.example .dev.vars`; the example secret is `change-me`. Tests do NOT need it — the secret is injected as `test-secret` via `vitest.config.ts` miniflare bindings.
- The installed Workers runtime only supports compatibility dates up to a certain point, so `wrangler.jsonc`'s newer `compatibility_date` triggers a harmless "Falling back to ..." warning in tests/dev. This is expected, not an error.
- Manual smoke test of the core flow (dev server running):
  ```bash
  curl -X POST http://127.0.0.1:8787/status \
    -H "Authorization: Bearer change-me" -H "content-type: application/json" \
    -d '{"busy":true,"timezone":"Europe/London"}'
  curl http://127.0.0.1:8787/api/status   # -> {"mic":"busy",...}
  ```
  The sign page (`GET /`) updates live over the `/ws` websocket; no reload needed.
- Endpoints: `GET /` (page), `GET /api/status` (JSON state), `POST /status` (heartbeat, Bearer `STATUS_SECRET`), `GET /ws` (websocket), `GET /manifest.webmanifest`.
