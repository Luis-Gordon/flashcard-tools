# Flashcard Tools (Memogenesis)
AI-powered flashcard generation and enhancement ecosystem: serverless API + Anki desktop add-on + web app.

## Repository Structure
```
flashcard-tools/
â”œâ”€â”€ flashcard-backend/   # Cloudflare Workers API (Hono, TypeScript)
â”œâ”€â”€ flashcard-anki/      # Anki desktop add-on (Python, PyQt6)
â””â”€â”€ flashcard-web/       # Web app (Vite, React, Cloudflare Workers)
```

Each sub-project has its own `GEMINI.md`, architecture doc, and session log. **Always read the sub-project GEMINI.md before working in that directory.** Use `@file` to include relevant files in your prompt.

## Commands

### Backend (`flashcard-backend/`)
```bash
npm run dev              # wrangler dev --local
npm run test             # vitest (unit + integration)
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
npm run dev              # Vite dev server
npm run build            # Production build
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
| AI | Claude API (claude-sonnet-4-5 primary, claude-haiku-4-5 cost-sensitive) |
| TTS | OpenAI TTS API â†’ Cloudflare R2 cache |
| Images | Unsplash API |
| Web app | Vite 6, React 19, Tailwind v4, shadcn/ui, Zustand, React Router 7 |
| Anki add-on | Python 3.9+, PyQt6, requests |

## API Contract (Cross-Cutting)

See [.gemini/styleguide.md](.gemini/styleguide.md) for detailed conventions.

### Error Handling Contract
Codes: `UNAUTHORIZED` (401), `USAGE_EXCEEDED` (402), `RATE_LIMITED` (429), `CONFLICT` (409), `VALIDATION_ERROR` (400), `CONTENT_TOO_LARGE` (413), `INTERNAL_ERROR` (500).

### Content Limits
- Text (raw): 100KB
- URL (fetched): 100KB after extraction
- PDF file: 10MB

## Architecture Principles
- **Backend is stateless** â€” all state in Supabase + R2.
- **Add-on never blocks main thread** â€” all API calls via QThread workers.
- **Prompts are versioned** â€” hooks-based architecture, never edit in-place.
- **Enhancements are additive** â€” original card content is always preserved.
- **Undo is mandatory** â€” `mw.checkpoint()` before any card modifications.

## Structured HTML Output Contract
All card content uses `fc-` prefixed CSS classes. See style guide for details.

## Deployment Coordination
**Lesson from Session 58 outage**: Adding a new field to any request schema is a **breaking change** due to `.strict()` Zod validation.

1. **Backend-first deployment**: Deploy backend â†’ verify health â†’ deploy client.
2. **Coordinated deploys**: Deploy and verify both in the same session.
3. **CORS allowlist**: Update `ALLOWED_ORIGINS` in `wrangler.jsonc` before client deploy.
4. **Staging web app**: Use `npm run deploy:staging` to pick up `.env.staging`.

## Session Workflow
1. **Start session** â€” run `pwsh -File tools/gemini/session-start.ps1 -Project {project}`
2. **Orient** â€” Read relevant `{project}/GEMINI.md` and recent session log entries.
3. **Implement** â€” follow conventions in [.gemini/styleguide.md](.gemini/styleguide.md).
4. **Check quality** â€” run `pwsh -File tools/gemini/check.ps1 -Project {project}`
5. **End session** â€” run `pwsh -File tools/gemini/session-end.ps1 -Summary "summary"`
6. **Deploy** â€” follow the Deployment Coordination checklist above.
7. **Commit and push** â€” commit from within each sub-project directory.

## Critical Constraints
- **NEVER** store passwords or commit secrets.
- **NEVER** return internal error details to clients.
- **NEVER** modify cards without user confirmation.
- **NEVER** make API calls during Anki sync.
- **ALWAYS** validate input with Zod.
- **ALWAYS** include `request_id` in response and `product_source` in request.

## Boundaries
### âš ï¸ Ask First
- New env vars, external integrations, DB schema changes, rate-limit/pricing changes.
- Batch operations on > 100 cards.
- Deploying to production.

### ðŸš« Never
- Commit API keys or secrets.
- Skip validation for "trusted" sources.

## Documentation Map
| Document | Purpose |
|----------|---------|
| `flashcard-backend/GEMINI.md` | Backend dev guide |
| `flashcard-anki/GEMINI.md` | Anki add-on dev guide |
| `flashcard-web/GEMINI.md` | Web app dev guide |
| `PRD.md` | Full ecosystem requirements |
| `.gemini/styleguide.md` | Cross-project conventions |
| `tools/gemini/README.md` | Workflow scripts documentation |

## Non-Goals
- Android/iOS app client (future).
- WebSocket connections.
- Custom card templates.
