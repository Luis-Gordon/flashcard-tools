Run quality gates (typecheck → lint → test) for the specified project(s).

Argument: $ARGUMENTS (optional — `backend`, `anki`, `web`, or `all`. If omitted, auto-detect from `git diff`.)

## Auto-detection (no argument)

If no argument is provided, detect affected projects:

```bash
cd flashcard-backend && git diff --name-only HEAD 2>/dev/null | head -1
cd flashcard-anki && git diff --name-only HEAD 2>/dev/null | head -1
cd flashcard-web && git diff --name-only HEAD 2>/dev/null | head -1
```

Run checks for any project that has uncommitted changes. If nothing is changed, report "No changes detected — specify a project explicitly."

## Quality gate commands

Run checks **sequentially** (stop on first failure within a project):

### Backend (`flashcard-backend/`)
```bash
cd flashcard-backend && npm run typecheck
cd flashcard-backend && npm run lint
cd flashcard-backend && npm run test
```

### Anki (`flashcard-anki/`)
```bash
cd flashcard-anki && flake8 src/
cd flashcard-anki && mypy src/
cd flashcard-anki && pytest tests/ -v
```

### Web (`flashcard-web/`)
```bash
cd flashcard-web && npm run typecheck
cd flashcard-web && npm run lint
cd flashcard-web && npm run test
```

## Output

Report a summary table with pass/fail per check. On failure, show the **first 15 lines** of output only.

```
## Quality Gates

| Project | Typecheck | Lint | Test | Status |
|---------|-----------|------|------|--------|
| backend | PASS      | PASS | PASS | ✅      |
| web     | PASS      | FAIL | —    | ❌      |

### Failures

**web / lint**:
{first 15 lines of lint output}
```

Notes:
- Use `—` for checks that were skipped due to an earlier failure
- Backend tests can take 2+ minutes (1700+ tests) — use a 5-minute timeout
- If a check fails, do NOT continue to the next check in that project (but DO continue to other projects)
