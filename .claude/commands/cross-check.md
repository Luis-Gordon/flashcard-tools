Check API contract consistency across all three sub-projects (backend, anki, web).

Argument: $ARGUMENTS (optional — specific area to check: `errors`, `endpoints`, `html`, `schemas`, `domains`, `limits`, `deploy`, or `all`. Defaults to `all`.)

## Instructions

Delegate this to an explorer agent. The Memogenesis monorepo has a tightly coupled API contract between three projects:

- **Backend** (`flashcard-backend/`): Hono API — defines routes, error codes, Zod schemas, HTML output
- **Anki add-on** (`flashcard-anki/`): Python desktop client — consumes API, renders HTML
- **Web app** (`flashcard-web/`): React SPA — consumes API, renders HTML

### Checks to perform

#### 1. Error codes (`errors`)
- **Source of truth**: `flashcard-backend/src/middleware/errorHandler.ts` + root `CLAUDE.md` error table
- **Anki**: `flashcard-anki/src/api/client.py` — verify all error codes are handled
- **Web**: `flashcard-web/src/lib/api.ts` — verify all error codes are handled
- Check for: missing error code handlers, inconsistent error messages, unhandled HTTP status codes

#### 2. Endpoints (`endpoints`)
- **Source of truth**: `flashcard-backend/src/index.ts` + route files in `src/routes/`
- **Anki**: `flashcard-anki/src/api/` — verify endpoint paths and methods match
- **Web**: `flashcard-web/src/lib/api.ts` — verify endpoint paths and methods match
- Check for: endpoints defined in backend but missing from clients, mismatched HTTP methods

#### 3. HTML classes (`html`)
- **Source of truth**: Backend prompt files in `flashcard-backend/src/lib/prompts/hooks/`
- **Anki**: `flashcard-anki/src/styles/stylesheet.py` — verify all `fc-*` classes have CSS rules
- **Web**: Search for `fc-` class references in web rendering components
- Check for: `fc-*` classes used in prompts but missing from stylesheets, orphaned CSS rules

#### 4. Request/response shapes (`schemas`)
- **Source of truth**: `flashcard-backend/src/lib/validation/` (Zod schemas)
- **Anki**: TypedDicts and type hints in `flashcard-anki/src/api/`
- **Web**: TypeScript types in `flashcard-web/src/types/`
- Check for: fields present in Zod schemas but missing from client types, type mismatches

#### 5. Domain list (`domains`)
- **Source of truth**: `flashcard-backend/src/lib/prompts/hooks/hook-registry.ts` (generation hooks) + `flashcard-backend/src/lib/prompts/hooks/enhance-hook-registry.ts` (enhancement hooks)
- **Anki**: Domain selector in generate/enhance UI dialogs — search for domain strings in `flashcard-anki/src/ui/`
- **Web**: Domain selector in generate form — search for domain strings in `flashcard-web/src/` (likely in a form component or validation)
- **Validation**: `flashcard-backend/src/lib/validation/cards.ts` — domain enum in Zod schema
- Check for: domains registered in backend hooks but missing from client UI selectors, mismatched domain keys, sub-hook options not exposed to clients

#### 6. Content limits (`limits`)
- **Source of truth**: `flashcard-backend/src/middleware/contentSize.ts` + root CLAUDE.md
- **Anki**: Client-side size validation before sending
- **Web**: Client-side size validation before sending
- Check for: mismatched limits, missing client-side validation

#### 7. Deployment version skew (`deploy`)
- **Check**: Compare the latest git commit in each sub-project with the last deployed version on staging
  - Backend: `cd flashcard-backend && git log --oneline -1` vs. check staging health endpoint timestamp or `wrangler deployments list --env staging`
  - Web: `cd flashcard-web && git log --oneline -1` vs. `wrangler deployments list --env staging`
- **Check**: If validation schemas (`flashcard-backend/src/lib/validation/*.ts`) have uncommitted or undeployed changes while a client has been deployed more recently, flag as critical
- **Why**: The backend uses `.strict()` Zod schemas — any new request field added in backend code but not deployed will cause the old deployed backend to reject requests from a newly deployed client

### Output format

```
## Cross-Project Contract Check

### ✅ Consistent
- {area}: {brief description}

### ⚠️ Inconsistencies Found
- **{area}**: {description of mismatch}
  - Backend: {what backend defines}
  - Anki: {what anki has}
  - Web: {what web has}
  - **Fix**: {which project(s) need updating}

### Summary
{N} areas checked, {M} inconsistencies found.
```

Return concise summaries with file paths — never dump full file contents. Focus on actionable inconsistencies, not exhaustive listings.
