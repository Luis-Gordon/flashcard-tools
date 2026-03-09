Review uncommitted code changes against project conventions and security constraints.

Argument: $ARGUMENTS (optional — specific files, commit range, or project name. If omitted, reviews all uncommitted changes.)

## Instructions

Delegate this review to the `reviewer` agent by launching it with subagent_type "general-purpose" and the following prompt. If the reviewer agent file exists at `.claude/agents/reviewer.md`, use it as an agent instead.

### What to review

- If no argument: review all uncommitted changes across all sub-projects (`git diff` + `git diff --cached` in each)
- If a project name (`backend`, `anki`, `web`): review only that project's changes
- If specific files: review only those files
- If a commit range (e.g., `HEAD~3..HEAD`): review that range

### Review checklist

Read the relevant sub-project CLAUDE.md(s) first, then check:

**TypeScript (backend, web):**
- Strict mode compliance — no `any`, use `unknown` with narrowing
- Type-only imports where applicable (`import type { ... }`)
- Zod schemas use `.strict()` to reject unknown fields
- No internal error details exposed to clients

**Python (anki):**
- Type hints on all function signatures
- No `Any` except for Anki runtime types (`mw`, `Note`, `Collection`)
- Config access via `mw.addonManager.getConfig(__name__)`

**React (web):**
- `useShallow` on Zustand store selectors
- DOMPurify used for card HTML sanitization
- No inline styles — Tailwind/CSS classes only

**Security:**
- No hardcoded secrets, API keys, or tokens
- No internal error details exposed to clients
- DOMPurify used where user HTML is rendered
- Input validation before processing

**API Contract:**
- `product_source` included in client requests
- `request_id` included in all responses
- `fc-*` HTML classes follow the structured HTML contract
- Error codes match the contract table in root CLAUDE.md

**Cross-project:**
- If HTML structure (`fc-*` classes) changed in backend prompts → check that anki `stylesheet.py` and web rendering still match
- If error handling changed → check both client implementations

### Output format

```
## Code Review

### Critical (must fix)
- {issue with file:line reference}

### Warnings (should fix)
- {issue with file:line reference}

### Suggestions (nice to have)
- {issue with file:line reference}
```

Limit to 3-5 bullets per category. Focus on real issues, not style nitpicks.
