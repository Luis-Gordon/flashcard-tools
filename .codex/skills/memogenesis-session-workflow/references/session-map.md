# Memogenesis Session Map

## Core Context Files
- `PRD.md`
- `CLAUDE.md`
- `flashcard-backend/CLAUDE.md`
- `flashcard-backend/docs/architecture.md`
- `flashcard-anki/CLAUDE.md`
- `flashcard-anki/docs/architecture.md`
- `flashcard-web/CLAUDE.md`
- `flashcard-web/docs/architecture.md`

## Quality Gates
- Backend:
  - `cd flashcard-backend`
  - `npm run typecheck`
  - `npm run lint`
  - `npm run test`
- Anki:
  - `cd flashcard-anki`
  - `flake8 src/`
  - `mypy src/`
  - `pytest tests/ -v`
- Web:
  - `cd flashcard-web`
  - `npm run typecheck`
  - `npm run lint`
  - `npm run test`

## Fast Orientation
- Session log tail:
  - `Get-Content {project}/docs/session-log.md -Tail 80`
- Backlog:
  - `Get-Content {project}/docs/backlog.md`
- Repo status:
  - `cd {project}; git status --short`
