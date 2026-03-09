Cross-AI plan review: invoke Codex and Gemini as reviewers, synthesize findings, and present patch preview for human approval.

Argument: $ARGUMENTS (required — path to the plan file to review)

## Step 1: Validate

Verify the plan file at `$ARGUMENTS` exists and is a markdown file. Stop if not found.

## Step 2: Invoke reviewers

Run the PowerShell runner script:

```bash
pwsh -ExecutionPolicy Bypass -File tools/plan-review/run-reviewers.ps1 -PlanFile "$ARGUMENTS" -OutputDir ".claude/review-output"
```

Use a 10-minute timeout for the bash command (the script has its own 5-min per-reviewer timeout internally).

## Step 3: Parse verdicts (fail-closed)

Read both verdict files:
- `.claude/review-output/codex-verdict.json`
- `.claude/review-output/gemini-verdict.json`

**Parsing rule:** Attempt to parse each file as JSON. If parsing fails for ANY reason (markdown fencing, preamble text, invalid JSON), treat that reviewer's result as `ERROR` immediately. Do NOT attempt to extract a JSON block from mixed content. A false verdict is worse than no verdict.

Validate required fields:
- Top-level: `verdict` must be one of `PASS`, `PASS_WITH_EDITS`, `BLOCK`, `ERROR`. `findings` must be an array.
- Per-finding: Each object in `findings` must contain `severity`, `category`, `description`, and `plan_section` (all strings, non-empty). If any finding is missing a required field, treat the entire verdict as `ERROR` — malformed findings would poison dedup and conflict detection.

If any validation check fails, treat as `ERROR`.

## Step 4: Synthesize findings

### 4a. Deduplication

**Dedup key:** `plan_section` + `category` + `description_hash`

The `description_hash` is the first 60 characters of the `description` field, lowercased with runs of whitespace collapsed to a single space.

If both reviewers produce findings with the same dedup key, merge into one finding noting both reviewers agree.

### 4b. Conflict detection (2 deterministic rules only)

1. **Verdict conflict:** One reviewer returns PASS or PASS_WITH_EDITS, the other returns BLOCK.
2. **Severity conflict:** Same dedup key, one reviewer rates `critical` or `major`, the other rates `minor` or `info`.

No fuzzy text comparison. No "opposing recommendation" detection.

### 4c. Compute aggregate verdict

Priority order:
- Conflicts detected → `NEEDS_HUMAN_REVIEW`
- Both ERROR → `ERROR`
- One ERROR → continue with other reviewer's verdict only
- Either BLOCK → `BLOCK`
- Either PASS_WITH_EDITS → `PASS_WITH_EDITS`
- Both PASS → `PASS`

## Step 5: Report

Display structured results:

```
## Plan Review Results (iteration N/3)

**Plan**: {path}
**Codex**: {verdict} | **Gemini**: {verdict} | **Aggregate**: {verdict}

### Agreed findings (both reviewers)
- [{severity}] {description} — {recommendation}

### Codex-only findings
- [{severity}] {id}: {description} — {recommendation}

### Gemini-only findings
- [{severity}] {id}: {description} — {recommendation}

### Conflicts (requires human decision)
- **Verdict conflict**: Codex says {verdict}, Gemini says {verdict}
- **Severity conflict**: {dedup key} — Codex: {severity}, Gemini: {severity}
```

Omit empty sections.

## Step 6: Branch on aggregate verdict

| Aggregate | Iteration | Action |
|-----------|-----------|--------|
| `PASS` | any | Report success. Ask user to proceed with execution. |
| `PASS_WITH_EDITS` | 1 or 2 | Generate patch preview → present to human → await approval. |
| `PASS_WITH_EDITS` | 3 | Stop. Surface remaining findings to human. Trigger lessons-learned (Step 7). |
| `BLOCK` | 1 or 2 | Generate patch preview from critical+major findings → present → await approval. |
| `BLOCK` | 3 | Stop. Surface remaining findings to human. Trigger lessons-learned (Step 7). |
| `NEEDS_HUMAN_REVIEW` | any | Stop. Present conflicts with both positions stated. |
| `ERROR` (both) | any | Stop. Report CLI failures. |
| `ERROR` (one) | any | Continue with other reviewer's verdict only. |

### Patch preview format (for PASS_WITH_EDITS or BLOCK, iteration < 3)

Read the plan file and generate a structured diff for each non-conflicting finding with severity `critical` or `major`:

```
## Proposed Plan Changes (iteration N)

### From finding F2 [critical/architecture] (agreed by both reviewers)
**Section**: "Step 3: Database Schema"
**Change**: Add migration rollback step
**Before**: (quote relevant section)
**After**: (show revised section)

### Deferred to human (minor findings — not auto-applied)
- [minor] F3: Consider adding retry logic to webhook handler

Apply these changes and re-run reviewers? (yes / no / edit manually)
```

- `info` findings: omitted from patch preview entirely.
- `minor` findings: listed under "Deferred to human" — never auto-applied.
- Wait for explicit human approval before applying changes.

If human approves → apply changes to the plan file → re-invoke reviewers (back to Step 2, increment iteration).
If human rejects → stop. Human edits manually and re-runs `/plan-review` when ready.

### State tracking across iterations

Track:
- `iteration_count` (1-based, max 3)
- `previous_finding_keys` — set of dedup keys from previous iteration
- `addressed_findings` — findings present in iteration N but absent in iteration N+1

**Convergence guard:** If the set of dedup keys is identical between iteration N and N+1, stop early — no progress is being made.

## Step 7: Lessons learned

Fires when:
- Final verdict is PASS (clean or after iterations), OR
- Iteration cap reached (3 iterations without PASS)

For each `major`+ finding from earlier iterations that was addressed (present in iteration N, absent in N+1):
1. Draft a candidate CLAUDE.md rule
2. Present EACH candidate individually to the user for approval (not batch)
3. If approved, delegate to `doc-updater` agent to apply that specific rule

When iteration cap is reached, the most persistent findings are the best candidates for permanent rules.
