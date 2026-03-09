Load context for a development session on the Memogenesis monorepo.

Argument: $ARGUMENTS (required — one of: `backend`, `anki`, `web`, or `all`)

## Steps

1. **Read root context**: Read `CLAUDE.md` (repo root) to understand the cross-project contract, commands, and conventions.

2. **Read sub-project context** based on argument:
   - `backend` → Read `flashcard-backend/CLAUDE.md`
   - `anki` → Read `flashcard-anki/CLAUDE.md`
   - `web` → Read `flashcard-web/CLAUDE.md`
   - `all` → Read all three sub-project CLAUDE.md files

3. **Read recent session history**: Read the last 2 entries from the relevant `{project}/docs/session-log.md` file(s). Only read the tail — these files are large. Use `tail -80` on each relevant session log to capture the last 2 entries.

4. **Read backlog**: Read the relevant `{project}/docs/backlog.md` file(s).

5. **Check git status**: Run `git status --short` in each relevant sub-project directory to see any uncommitted work.

## Output

Produce a concise summary (max 40 lines) with these sections:

```
## Session Context: {project(s)}

### Current Status
- {1-2 lines from CLAUDE.md "Current Status" per project}

### Recent Work
- {3-5 bullet points from last 2 session log entries}

### Uncommitted Changes
- {git status summary, or "Clean" if nothing}

### Top Backlog Items
- {3-5 highest priority items from backlog}

### Reminders
- {Any critical constraints or "ask first" items relevant to this project}
```

Keep it terse — this is a quick orientation, not a deep dive.
