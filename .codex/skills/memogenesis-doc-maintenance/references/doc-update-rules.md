# Doc Update Rules

## Files to Update
- `flashcard-backend/docs/session-log.md`
- `flashcard-backend/CLAUDE.md`
- `flashcard-backend/docs/architecture.md`
- `flashcard-anki/docs/session-log.md`
- `flashcard-anki/CLAUDE.md`
- `flashcard-anki/docs/architecture.md`
- `flashcard-web/docs/session-log.md`
- `flashcard-web/CLAUDE.md`
- `flashcard-web/docs/architecture.md`

## Session Log Entry Requirements
- Match existing format exactly.
- Increment session number from latest entry.
- Include date and concise summary.
- Include objective facts only from:
  - git diff/status
  - commands/tests run
  - files changed

## CLAUDE.md Update Requirements
- Reflect newly completed work in "Current Status".
- Adjust "Next Session Tasks" based on unfinished items.
- Do not rewrite unrelated sections.

## Architecture Update Rule
Update only for structural changes:
- route additions/removals
- service/middleware architecture shifts
- schema or integration changes

Skip architecture updates for pure bug fixes, refactors without behavior change, or docs-only edits.
