# Codex Instructions for flashcard-tools

## Purpose
Use this repo-level memory as the Codex equivalent of Claude memory + CLAUDE.md guidance for Memogenesis (flashcard-tools).

## Session Start Protocol
1. Read `PRD.md`.
2. Read root `CLAUDE.md`.
3. Read relevant sub-project `CLAUDE.md` and `docs/architecture.md`.
4. Read the last 2 entries in `{project}/docs/session-log.md`.
5. Read `{project}/docs/backlog.md`.
6. Check git status in each touched sub-project repo.

## Project Map
- `flashcard-backend/`: Cloudflare Workers API (Hono + TS)
- `flashcard-anki/`: Anki add-on (Python + PyQt6)
- `flashcard-web/`: React SPA (Vite + TS)

## Cross-Project Contract Rules
- Include `product_source` in every client request body.
- Include `request_id` in every backend response (success and error).
- Keep `fc-*` HTML contract synchronized across:
  - backend prompt output
  - anki stylesheet (`src/styles/stylesheet.py`)
  - web sanitizer/rendering
- Enforce content limits: text 100KB, URL extracted 100KB, PDF 10MB.
- Enforce error code contract (`VALIDATION_ERROR`, `UNAUTHORIZED`, `USAGE_EXCEEDED`, `RATE_LIMITED`, `CONTENT_TOO_LARGE`, `CONFLICT`, `INTERNAL_ERROR`).

## Quality Gates
- Backend: `npm run typecheck && npm run lint && npm run test`
- Anki: `flake8 src/ && mypy src/ && pytest tests/ -v`
- Web: `npm run typecheck && npm run lint && npm run test`

Use `tools/codex/check.ps1` for a single entrypoint.

## Documentation Maintenance Rules
- Append only to `docs/session-log.md`.
- Update `CLAUDE.md` current status and next tasks after meaningful work.
- Update `docs/architecture.md` only for structural changes.
- If PRD and CLAUDE conflict, PRD wins.

## Ask-First Boundaries
- New env vars, external integrations, DB schema changes, rate-limit/pricing changes.
- Add-on: note type/template changes, >100 card batch operations.
- Web: new analytics/tracking scripts, new persistence layer.

## Never Rules
- Never commit secrets.
- Never expose internal backend error details.
- Never block Anki main thread for API calls.
- Never bypass validation on backend input.

## Local Codex Skills
Use the following local skills for this repo:
- `.codex/skills/memogenesis-session-workflow/SKILL.md`
- `.codex/skills/memogenesis-contract-auditor/SKILL.md`
- `.codex/skills/memogenesis-doc-maintenance/SKILL.md`

Trigger guidance:
- Use `memogenesis-session-workflow` for orientation, planning, and running checks.
- Use `memogenesis-contract-auditor` when reviewing endpoint/error/html/schema/domain/limit consistency across backend/anki/web.
- Use `memogenesis-doc-maintenance` when updating session logs, CLAUDE status, and architecture docs.

## Hook Equivalents
Use these scripts as Codex equivalents to session hooks and slash commands:
- `tools/codex/session-start.ps1`
- `tools/codex/check.ps1`
- `tools/codex/cross-check.ps1`
- `tools/codex/session-end.ps1`
