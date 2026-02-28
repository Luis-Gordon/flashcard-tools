# Flashcard Tools
AI-powered flashcard generation and enhancement ecosystem (**Memogenesis**): serverless API + Anki desktop add-on + web app.

## Repository Structure
```
flashcard-tools/
├── flashcard-backend/   # Cloudflare Workers API (Hono, TypeScript)
├── flashcard-anki/      # Anki desktop add-on (Python, PyQt6)
└── flashcard-web/       # Web app (Vite, React, Cloudflare Workers) — Phase 4a (export) complete, Phase 4b (billing) next
```

Each sub-project has its own CLAUDE.md, architecture doc, and session log. The PRD is consolidated at the repo root (`PRD.md`). **Always read the sub-project CLAUDE.md before working in that directory.**

## Commands

### Backend (`flashcard-backend/`)
```bash
npm run dev              # wrangler dev --local
npm run test             # vitest (unit + integration)
npm run test:unit        # unit tests only (Node pool)
npm run test:integration # integration tests only (Workers pool)
npm run typecheck        # tsc --noEmit
npm run lint:fix         # eslint src/ --fix
npm run deploy:staging   # wrangler deploy --env staging
```

### Anki Add-on (`flashcard-anki/`)
```bash
pytest tests/ -v         # Run all tests
flake8 src/              # Lint
mypy src/                # Type check
python tools/package.py  # Build .ankiaddon
```

### Web App (`flashcard-web/`)
```bash
npm run dev              # Vite dev server (plain SPA, no Workers runtime)
npm run build            # Production build (prebuild runs prerender)
npm run test             # Vitest
npm run typecheck        # tsc --noEmit
npm run lint:fix         # eslint src/ --fix
npm run deploy           # wrangler deploy
```

## Tech Stack

| Layer | Stack |
|-------|-------|
| Backend runtime | Cloudflare Workers, Hono v4.x, TypeScript strict |
| Database | Supabase (PostgreSQL), Supabase Auth |
| AI | Claude API (`claude-sonnet-4-5-20250929` primary, `claude-haiku-4-5-20251001` cost-sensitive) |
| TTS | OpenAI TTS API → Cloudflare R2 cache |
| Images | Unsplash API |
| Payments | Stripe (subscription + metered overage billing, Phase 5b complete) |
| Web app | Vite 6, React 19, Tailwind v4, shadcn/ui, Zustand, React Router 7 |
| Anki add-on | Python 3.9+, PyQt6, requests |
| Validation | Zod (backend), type hints + TypedDict (add-on) |

## API Contract (Cross-Cutting)

The Anki add-on and web app are the primary API consumers. These contracts are enforced on both sides:

**Every request** must include `product_source` (`'anki_addon'` or `'web_app'`) in the body.
**Every response** includes `request_id` (success and error).

### Error Handling Contract
| Code | HTTP | Backend Behavior | Add-on Behavior |
|------|------|-----------------|-----------------|
| `UNAUTHORIZED` | 401 | Return error | Clear token → login dialog |
| `USAGE_EXCEEDED` | 402 | Return error + limits | Show upgrade message |
| `RATE_LIMITED` | 429 | Return `retry_after` | Auto-retry (max 2, cap 60s), then toast |
| `CONFLICT` | 409 | Duplicate email signup | Show "account already exists" message |
| `VALIDATION_ERROR` | 400 | Return field errors | Show user-friendly message |
| `CONTENT_TOO_LARGE` | 413 | Reject before processing | Show size limit message |
| `INTERNAL_ERROR` | 500 | Log full trace, return `request_id` only | Show "Something went wrong" + `request_id` |

Full endpoint list in each sub-project's CLAUDE.md. Key routes: `/auth/*`, `/cards/generate`, `/cards/enhance`, `/cards` (CRUD), `/assets/tts`, `/assets/image`, `/billing/*`, `/account/*`.

### Content Limits
| Type | Max Size |
|------|----------|
| Text (raw) | 100KB |
| URL (fetched content) | 100KB after extraction |
| PDF file | 10MB |

## Architecture Principles

- **Backend is stateless** — all state in Supabase + R2, Workers handle no persistent connections
- **Add-on never blocks main thread** — all API calls via QThread workers
- **Prompts are versioned** — `src/lib/prompts/{generation,enhancement}/{name}-v{semver}.ts`, never edit in-place
- **Hook-based prompt architecture** — all 10 domains use hooks for both generation and enhancement; master base + domain hook + optional sub-hook (LANG: JA, ZH, KO, RU, AR, CEFR default)
- **Enhancements are additive** — original card content is always preserved
- **Undo is mandatory** — `mw.checkpoint()` before any card modifications

### Structured HTML Output Contract
All card content uses structured HTML with `fc-` prefixed CSS classes — this is the contract between backend prompts (which generate the HTML) and the Anki add-on (which styles and renders it).

- **Class prefix**: `fc-` on everything — avoids collisions with Anki's own styles
- **Structure**: `fc-front`/`fc-back` → `fc-section` blocks → `fc-heading` + `fc-content`
- **Section types**: `fc-meaning`, `fc-example`, `fc-notes`, `fc-meta`, `fc-formula`, `fc-code`, `fc-source`
- **Meta elements**: `fc-tag` (badges), `fc-register` (formality)
- **LANG-specific**: `fc-word`, `fc-reading` (furigana), `fc-jp`/`fc-en` (bilingual)
- **Furigana**: `<ruby>kanji<rt>reading</rt></ruby>` — per-kanji annotation, never on hiragana/katakana/English
- **Single source of truth**: Backend prompts define the HTML structure; `src/styles/stylesheet.py` in the add-on defines the CSS
- Changes to class names or structure must be coordinated across both projects

## Cross-Project Conventions

### Backend (TypeScript)
- Strict mode, type-only imports, no `any`
- Zod validation in `src/lib/validation/{domain}.ts` with `.strict()`
- Routes split by action: `generate.ts`, `enhance.ts` composed by thin `cards.ts` router
- Backend external API timeouts: Claude 60s, TTS 15s, Unsplash 10s
- Client-side timeouts: generate 60s, enhance 120s, TTS 15s, image 10s

### Web App (TypeScript/React)
- React 19, Vite 6, Tailwind v4 with CSS-first config
- Zustand stores (cards, auth, settings)
- DOMPurify for card HTML sanitization
- All API calls include `product_source: 'web_app'`

### Add-on (Python)
- Python 3.9+ compatible (Anki's bundled version)
- Type hints on all signatures; no `Any` except Anki runtime types (`mw`, `Note`, `Collection`) which lack stubs
- All HTTP through `src/api/client.py` with transparent token refresh and proactive expiry check
- Config via `mw.addonManager.getConfig(__name__)`
- Sync guard: `ApiWorker` checks `sync_guard.is_sync_in_progress()` before executing

## CRITICAL Constraints

> **Authoritative source**: Each sub-project's CLAUDE.md has the full, canonical constraints and boundaries. Below is the cross-project summary — if they diverge, the sub-project file wins.

- **NEVER** store passwords — JWT tokens only
- **NEVER** return internal error details to clients (backend)
- **NEVER** modify cards without user confirmation (add-on)
- **NEVER** make API calls during Anki sync
- **NEVER** commit secrets — use `wrangler secret put` (backend)
- **ALWAYS** validate input with Zod before processing (backend)
- **ALWAYS** include `request_id` in every response (backend)
- **ALWAYS** include `product_source` in every request (add-on)

## Boundaries

### ⚠️ Ask First
- Adding new environment variables or external API integrations
- Changing database schema or Supabase migrations
- Modifying rate limits, pricing, or content size limits
- Adding new Python dependencies (must be bundled with Anki)
- Batch operations on > 100 cards

### 🚫 Never
- Commit API keys, tokens, or secrets
- Store raw user content longer than 30 days
- Skip validation for "trusted" sources
- Block Anki's main thread during API calls

## Documentation Map
| Document | Location | Purpose |
|----------|----------|---------|
| Backend CLAUDE.md | `flashcard-backend/CLAUDE.md` | Full backend dev guide |
| Anki CLAUDE.md | `flashcard-anki/CLAUDE.md` | Full add-on dev guide |
| PRD | `PRD.md` (repo root) | Full ecosystem requirements (all 4 PRDs) |
| Web App CLAUDE.md | `flashcard-web/CLAUDE.md` | Full web app dev guide |
| Backend architecture | `flashcard-backend/docs/architecture.md` | Living system state |
| Anki architecture | `flashcard-anki/docs/architecture.md` | Living system state |
| Session logs | `{project}/docs/session-log.md` | Append-only history |
| Billing spec | `flashcard-backend/docs/billing-spec.md` | Stripe billing design |
| Product Backlog | PRD.md § Product Backlog | Open design questions + planned features |
| Project backlogs | `{project}/docs/backlog.md` | Per-project task tracking |

**Rule**: If PRD and CLAUDE.md conflict, PRD wins.

## Session Workflow
1. **Identify scope** — which sub-project(s) does this touch?
2. **Read sub-project CLAUDE.md** — it has project-specific conventions and status
3. **Check recent context** — read the last 1-2 entries in the sub-project's `docs/session-log.md`
4. **Implement** — follow sub-project conventions
5. **Run quality gates** — both projects must pass their respective checks
6. **Update docs** — session log, architecture (if structure changed), CLAUDE.md status
7. **Commit and push** — each sub-project has its own git repo; commit from within the sub-project directory

## Non-Goals (Current Phase)
- Android app client (gated on Gate 4 demand data)
- WebSocket connections
- Team/organization accounts
- Custom card templates
- API key auth (JWT only)
