# Plan Review Task

You are **{{REVIEWER_ID}}**, reviewing an implementation plan for the Memogenesis project.

## Instructions

1. Read the plan file at: `{{PLAN_FILE_PATH}}`
2. Read the root `CLAUDE.md` for project conventions and constraints.
3. Read any sub-project `CLAUDE.md` files referenced by the plan (e.g., `flashcard-backend/CLAUDE.md`, `flashcard-web/CLAUDE.md`, `flashcard-anki/CLAUDE.md`).
4. Evaluate the plan against these 8 criteria:
   - **Correctness**: Will the plan achieve its stated goals? Are there logical errors?
   - **Security**: Does the plan introduce security vulnerabilities or violate security constraints?
   - **Convention compliance**: Does the plan follow the project's established patterns and conventions?
   - **Completeness**: Are there missing steps, edge cases, or error handling gaps?
   - **Scope creep**: Does the plan include unnecessary work beyond the stated goal?
   - **Cross-project impact**: Does the plan affect multiple sub-projects? Are contracts maintained?
   - **Deployment coordination**: If API schemas change, does the plan follow backend-first deployment?
   - **Dependency risk**: Does the plan add new dependencies or rely on unstable/unverified tools?

## Verdict Rules

- **PASS** — No findings, or `info`-only findings.
- **PASS_WITH_EDITS** — Has `major` or `minor` findings, but no `critical` findings.
- **BLOCK** — At least one `critical` finding, OR you cannot complete the review (explain in `summary`).

You must NEVER return a verdict of `ERROR`. If you encounter a problem reviewing, use `BLOCK` and explain in `summary`.

## Finding Requirements

- `plan_section` is **required** for all findings. If a finding applies globally rather than to a specific step, use `"global"` as the `plan_section` value.
- Use sequential IDs: F1, F2, F3, etc.
- Be specific in `description` and `recommendation` — vague findings are not actionable.

## OUTPUT RULES

**Your entire response must be a single JSON object. Do not include any text before or after the JSON. Do not wrap it in markdown code fences. Do not add explanation. If you cannot complete the review for any reason, output a JSON object with `"verdict": "BLOCK"` and explain in `"summary"`.**

Output this exact JSON structure:

{"verdict":"PASS | PASS_WITH_EDITS | BLOCK","reviewer":"{{REVIEWER_ID}}","summary":"1-2 sentence assessment","findings":[{"id":"F1","severity":"critical | major | minor | info","category":"architecture | security | performance | correctness | convention | missing-requirement | scope-creep | dependency-risk","description":"What the issue is","recommendation":"What should change","plan_section":"Which step/section this applies to (use 'global' if not section-specific)"}]}
