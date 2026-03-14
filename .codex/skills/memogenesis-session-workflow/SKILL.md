---
name: memogenesis-session-workflow
description: Run Memogenesis development sessions in a consistent way across backend, Anki add-on, and web app. Use when starting work, orienting on project state, selecting quality gates, and closing a session with verifiable checks and concise status output.
---

# Memogenesis Session Workflow

Follow this workflow in order. Keep output concise and action-oriented.

## 1. Start Session
1. Read `PRD.md`.
2. Read root `CLAUDE.md`.
3. Read the relevant sub-project `CLAUDE.md` + `docs/architecture.md`.
4. Read last 2 entries in relevant `docs/session-log.md`.
5. Read relevant `docs/backlog.md`.
6. Check git status in touched sub-project repos.

If the user did not specify project scope, infer from changed files or ask for scope (`backend`, `anki`, `web`, `all`).

## 2. Implement Work
1. Prefer minimal targeted changes.
2. Preserve cross-project API contract.
3. Keep sub-project boundaries intact (no mixed unrelated changes).

## 3. Run Quality Gates
Run project checks after changes:
- Backend: `npm run typecheck && npm run lint && npm run test`
- Anki: `flake8 src/ && mypy src/ && pytest tests/ -v`
- Web: `npm run typecheck && npm run lint && npm run test`

Use `tools/codex/check.ps1` when available.

## 4. Close Session
1. If checks fail, report exact failing step and stop.
2. If checks pass, update docs:
  - Append `docs/session-log.md`.
  - Update `docs/backlog.md` — mark done items, add new items.
  - Update architecture doc only for structural changes.
3. Summarize changed files, key behavior changes, and residual risks.

## References
- Read [session-map.md](references/session-map.md) for command and file map.
