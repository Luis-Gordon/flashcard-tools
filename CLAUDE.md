# Flashcard Tools
AI-powered flashcard generation and enhancement ecosystem (**Memogenesis**): serverless API + Anki desktop add-on + web app.

## CRITICAL Constraints
- **NEVER** store passwords — JWT tokens only
- **NEVER** return internal error details to clients (backend)
- **NEVER** modify cards without user confirmation (add-on)
- **NEVER** make API calls during Anki sync
- **NEVER** commit secrets — use `wrangler secret put`
- **NEVER** make code changes during a `/review` — reviews are read-only; report findings and stop
- **ALWAYS** validate input with Zod before processing (backend)
- **ALWAYS** include `request_id` in every response (backend)
- **ALWAYS** include `product_source` in every request (clients)

## Deployment Coordination

> **Lesson from Session 58 outage**: The backend uses `.strict()` Zod validation on all request schemas. Adding a new field to any request schema is a **breaking change** — the deployed backend will reject requests containing the new field.

1. **Backend-first deployment**: Deploy backend → verify health → deploy client
2. **Coordinated deploys**: When changes span backend + client, deploy and verify both in the same session
3. **CORS allowlist**: Add new client URLs to `ALLOWED_ORIGINS` in `wrangler.jsonc` **before** deploying client
4. **Staging web app**: Always use `npm run deploy:staging` (not manual `build` + `deploy --env staging`). The script handles `--mode staging`.
5. **Checklist**: typecheck + test → deploy staging → curl health/ready → deploy client staging → smoke test → production

## Boundaries

### Ask First
- Adding new environment variables or external API integrations
- Changing database schema or Supabase migrations
- Modifying rate limits, pricing, or content size limits
- Adding new Python dependencies (must be bundled with Anki)
- Batch operations on > 50 cards
- Deploying to production (always deploy + verify staging first)

### Never
- Commit API keys, tokens, or secrets
- Store raw user content longer than 30 days
- Skip validation for "trusted" sources
- Block Anki's main thread during API calls

## Commands

### Backend (`flashcard-backend/`)
| Command | Purpose |
|---------|---------|
| `npm run dev` | wrangler dev --local |
| `npm run test` | vitest (unit + integration) |
| `npm run typecheck` | tsc --noEmit |
| `npm run lint:fix` | eslint src/ --fix |
| `npm run deploy:staging` | wrangler deploy --env staging |

### Anki Add-on (`flashcard-anki/`)
| Command | Purpose |
|---------|---------|
| `pytest tests/ -v` | Run all tests |
| `flake8 src/` | Lint |
| `mypy src/` | Type check |

### Web App (`flashcard-web/`)
| Command | Purpose |
|---------|---------|
| `npm run dev` | Vite dev server |
| `npm run test` | Vitest |
| `npm run typecheck` | tsc --noEmit |
| `npm run lint:fix` | eslint src/ --fix |
| `npm run deploy:staging` | Build with --mode staging + deploy |

## Documentation & Workflow

| Document | Location |
|----------|----------|
| PRD (source of truth) | `PRD.md` (repo root) |
| Backend dev guide | `flashcard-backend/CLAUDE.md` |
| Anki dev guide | `flashcard-anki/CLAUDE.md` |
| Web app dev guide | `flashcard-web/CLAUDE.md` |
| Architecture docs | `{project}/docs/architecture.md` |
| Session logs | `{project}/docs/session-log.md` |
| Billing spec | `flashcard-backend/docs/billing-spec.md` |

**Rule**: If PRD and CLAUDE.md conflict, PRD wins.

**Session workflow**: `/session-start {project}` → implement → `/check` → `/session-end "summary"` → deploy if needed → commit and push.

## Repository Structure
```
flashcard-tools/
├── flashcard-backend/   # Cloudflare Workers API (Hono, TypeScript)
├── flashcard-anki/      # Anki desktop add-on (Python, PyQt6)
└── flashcard-web/       # Web app (Vite, React, Cloudflare Workers)
```
Each sub-project has its own CLAUDE.md, architecture doc, and session log. **Always read the sub-project CLAUDE.md before working in that directory.**
