---
name: memogenesis-doc-maintenance
description: Maintain Memogenesis living documentation after implementation work. Use when appending session logs, updating project CLAUDE status/next tasks, and keeping architecture docs aligned with real structural changes.
---

# Memogenesis Doc Maintenance

Maintain docs with strict evidence from git and changed files.

## Required Inputs
- Project scope (`backend`, `anki`, `web`, or combinations)
- Work summary
- Current git diff/status

## Workflow
1. Read tail of target `docs/session-log.md` and match existing entry format.
2. Append a new session entry:
  - Increment session number
  - Date
  - What changed
  - Key decisions
  - Tests run and outcomes
  - Files changed
3. Update relevant `CLAUDE.md`:
  - Current status
  - Next session tasks
4. Update architecture doc only if structure changed:
  - new routes/services/middleware
  - data schema changes
  - integration changes
5. Keep entries concise and factual. Do not invent data.

## Guardrails
- Append-only for session logs.
- Preserve existing heading structure and wording style.
- If work is partial or checks failed, state that explicitly.

## References
- Read [doc-update-rules.md](references/doc-update-rules.md).
