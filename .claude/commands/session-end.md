Complete the current development session with quality gates, documentation, and commit preparation.

Argument: $ARGUMENTS (required — brief summary of what was accomplished this session)

## Steps

### 1. Detect modified sub-projects

Run `git status --short` in each sub-project directory (`flashcard-backend/`, `flashcard-anki/`, `flashcard-web/`) to identify which projects have changes.

### 2. Run quality gates

For each modified sub-project, run the quality gates using `lint:fix` (not `lint`) to auto-fix what's possible:

**Backend:**
```bash
cd flashcard-backend && npm run typecheck && npm run lint:fix && npm run test
```

**Anki:**
```bash
cd flashcard-anki && flake8 src/ && mypy src/ && pytest tests/ -v
```

**Web:**
```bash
cd flashcard-web && npm run typecheck && npm run lint:fix && npm run test
```

### 3. Show lint:fix changes (if any)

After running `lint:fix`, check if it modified any files:

```bash
cd {project} && git diff --stat
```

If `lint:fix` changed files, show the diff so the user can inspect what was auto-fixed:

```
### Auto-fixed by lint:fix

**{project}**: {N} file(s) changed
{git diff output — full diff, these are typically small}
```

This ensures auto-fixes don't bypass review. The user should confirm these changes are acceptable before proceeding.

### 4. If quality gates FAIL → STOP

Report the failures clearly and stop. Do not proceed to documentation or commits.

```
❌ Quality gates failed — fix before completing session.

{failure details — first 15 lines per failure}
```

### 5. If quality gates PASS → Check deployment coordination

If **both** backend and a client project (web or anki) have changes, check for API contract changes that require coordinated deployment:

1. Check if any files in `flashcard-backend/src/lib/validation/` were modified (Zod request/response schemas)
2. Check if the client sends new fields to the backend (new properties in API request types/calls)

If either is true, warn:

```
⚠️ Cross-project schema changes detected

Backend validation schemas (`.strict()`) were modified alongside client changes.
The backend MUST be deployed before the client to avoid request rejection.

Deployment order:
1. Deploy backend: cd flashcard-backend && npm run deploy:staging
2. Verify: curl https://flashcard-backend-staging.../health/ready
3. Deploy client: cd flashcard-web && npm run deploy:staging
4. Smoke test on staging before deploying to production

See root CLAUDE.md § Deployment Coordination for full checklist.
```

### 6. Update documentation

For each modified sub-project, update documentation:

1. **Session log** (`{project}/docs/session-log.md`): Append a new entry following the existing format. Include:
   - Session number (increment from last entry)
   - Date
   - Summary of accomplishments (from the $ARGUMENTS and actual changes)
   - Key decisions made
   - Files modified
   - Test count if tests were changed

2. **CLAUDE.md status**: Update "Current Status" and "Next Session Tasks" sections in the sub-project's CLAUDE.md if the work changed them.

3. **Architecture doc** (`{project}/docs/architecture.md`): Only update if structural changes were made (new routes, new services, schema changes).

### 7. Show commit preparation

Display:
```
## Session Complete

### Changes by project

**{project}** ({N} files changed)
Suggested commit message:
> {concise message describing the changes}

### Ready to commit?
Confirm and I'll commit each sub-project separately.
```

**IMPORTANT**: Do NOT auto-commit. Wait for explicit user confirmation before committing. Each sub-project has its own git repo — commits must be made from within each sub-project directory.
