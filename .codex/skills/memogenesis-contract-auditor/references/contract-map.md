# Contract Map

## Backend Source of Truth
- Errors: `flashcard-backend/src/middleware/errorHandler.ts`
- Entry routes: `flashcard-backend/src/index.ts`
- Route files: `flashcard-backend/src/routes/*.ts`
- Validation schemas: `flashcard-backend/src/lib/validation/*.ts`
- Limits: `flashcard-backend/src/middleware/contentSize.ts`
- Domain hooks: `flashcard-backend/src/lib/prompts/hooks/hook-registry.ts`
- Enhancement hooks: `flashcard-backend/src/lib/prompts/hooks/enhance-hook-registry.ts`

## Anki Client
- API client: `flashcard-anki/src/api/client.py`
- Endpoint wrappers: `flashcard-anki/src/api/`
- UI domain selectors: `flashcard-anki/src/ui/`
- HTML stylesheet contract: `flashcard-anki/src/styles/stylesheet.py`

## Web Client
- API client: `flashcard-web/src/lib/api.ts`
- Type definitions: `flashcard-web/src/types/`
- Domain constants/selectors: `flashcard-web/src/lib/constants/` and form components
- Sanitized HTML rendering: `flashcard-web/src/components/cards/SanitizedHTML.tsx`

## Global Contract Docs
- `CLAUDE.md`
- `PRD.md`
