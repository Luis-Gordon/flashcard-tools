# Plan Review Tools

PowerShell script that invokes Codex CLI and Gemini CLI as plan reviewers in parallel, capturing structured JSON verdicts.

## Usage

```powershell
pwsh -ExecutionPolicy Bypass -File tools/plan-review/run-reviewers.ps1 -PlanFile <path-to-plan.md> -OutputDir .claude/review-output
```

## Prerequisites

- **Windows**: `codex.cmd` and `gemini.cmd` must be on PATH (installed via `npm install -g @openai/codex` and `npm install -g @anthropic-ai/gemini-cli` respectively). The script uses `.cmd` wrappers — POSIX shell scripts don't work with `Start-Process` on Windows.
- `.claude/review-output/` is gitignored — verdict files persist for inspection but aren't committed

## How It Works

1. Reads the plan-review prompt template from `.claude/templates/plan-review-prompt.md`
2. Substitutes `{{PLAN_FILE_PATH}}` and `{{REVIEWER_ID}}` for each reviewer
3. Writes prompts to temp files for stdin redirection
4. Launches both CLIs in parallel using `Start-Process` with `-RedirectStandardInput`
5. Waits for both with a 300s timeout
6. Codex writes output directly via `--output-last-message`; Gemini output is parsed from its JSON envelope (`response` field)

## Output

Creates two files in the output directory:
- `codex-verdict.json` — Codex's structured review verdict
- `gemini-verdict.json` — Gemini's structured review verdict

Each file contains a JSON object with: `verdict`, `reviewer`, `summary`, `findings[]`.

## Error Handling

- **Timeout**: 300s per reviewer. On timeout, the process is killed and an `ERROR` verdict is written.
- **CLI failure**: Non-zero exit code writes an `ERROR` verdict with the exit code and stderr content.
- **Gemini output parsing**: If the `response` field is missing from Gemini's JSON envelope, an `ERROR` verdict is written.
- **Cleanup**: All temp files are removed in a `finally` block regardless of outcome.

## Hardening Options

- **Codex `--output-schema`**: If Codex output compliance proves unreliable, add `--output-schema .claude/templates/plan-review-schema.json` to the `codex exec` invocation in the script. This enforces the verdict schema at the model level.
