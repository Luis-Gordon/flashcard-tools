# Doc Update Rules

## Files to Update
- `flashcard-backend/docs/session-log.md`
- `flashcard-backend/docs/backlog.md`
- `flashcard-backend/docs/architecture.md`
- `flashcard-anki/docs/session-log.md`
- `flashcard-anki/docs/backlog.md`
- `flashcard-anki/docs/architecture.md`
- `flashcard-web/docs/session-log.md`
- `flashcard-web/docs/backlog.md`
- `flashcard-web/docs/architecture.md`

## Session Log Entry Requirements
- Match existing format exactly.
- Increment session number from latest entry.
- Include date and concise summary.
- Include objective facts only from:
  - git diff/status
  - commands/tests run
  - files changed

## Backlog Update Requirements
- Mark completed items done or remove them from `docs/backlog.md`.
- Add new work items discovered during the session.
- Do not rewrite unrelated sections.

## Architecture Update Rule
Update only for structural changes:
- route additions/removals
- service/middleware architecture shifts
- schema or integration changes

Skip architecture updates for pure bug fixes, refactors without behavior change, or docs-only edits.
