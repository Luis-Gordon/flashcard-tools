# Agent Architecture

Technical reference for the Memogenesis `.claude/` agent orchestration system.
Audience: senior developers extending or maintaining the automation layer.

Companion document for Codex setup:
`docs/codex-architecture.md`

---

## 1. Design Philosophy

Four principles govern every decision in this system.

### Explicit commands over auto-delegation

Claude auto-delegates to subagents roughly 20% of the time when instructed via
CLAUDE.md routing rules. That's not reliable enough for workflows that must run
identically every session. Slash commands (`/session-start`, `/session-end`, etc.)
guarantee the right steps execute in the right order — the developer triggers
them, not a probabilistic routing heuristic.

### Context isolation as primary subagent value

The main context window fills fast: system prompts, tool definitions, MCP
schemas, and memory files consume 30,000–40,000 tokens before you type anything.
Performance degrades well before the 200K ceiling. Subagents exist primarily to
keep verbose output (1,700+ backend test results, full lint traces, git diffs)
out of the main conversation. The isolation benefit outweighs any parallelism or
specialization advantage.

### Model tiering by judgment required

| Tier | Model | When to use | Agents |
|------|-------|-------------|--------|
| Pattern-following | haiku | Execute a defined procedure with known steps | quality-gate, doc-updater, explorer |
| Judgment-requiring | sonnet | Evaluate trade-offs, prioritize issues, catch subtle bugs | reviewer |
| Never | opus | Cost prohibitive for delegated tasks; reserve for main context | — |

Haiku is the default because most agent work is mechanical: run commands, read
files, format output. Sonnet is reserved for the reviewer, which must weigh
severity, understand project conventions, and distinguish real issues from noise.
Opus is never used as a subagent — its cost multiplier doesn't justify the
marginal quality gain for procedural tasks.

### Automation with visibility

`lint:fix` auto-corrects code style, but session-end (step 3) always shows the
diff before proceeding. Invisible auto-fixes bypass the developer's learning loop
and can mask real issues. The pattern: automate the fix, surface the result,
require confirmation before moving on.

---

## 2. System Inventory

### Slash Commands

| Command | File | Purpose | Argument | Delegates to |
|---------|------|---------|----------|--------------|
| `/session-start` | `commands/session-start.md` | Load context (CLAUDE.md, session log, backlog, git status) | `backend`, `anki`, `web`, or `all` (required) | — (main context) |
| `/check` | `commands/check.md` | Run quality gates (typecheck → lint → test) | project name or omit for auto-detect | — (main context) |
| `/session-end` | `commands/session-end.md` | Gates → lint:fix → docs → commit prep | summary string (required) | doc-updater (step 5) |
| `/review` | `commands/review.md` | Code review against conventions + security | files, project, or commit range | reviewer agent |
| `/cross-check` | `commands/cross-check.md` | API contract consistency across 3 projects | `errors`, `endpoints`, `html`, `schemas`, `domains`, `limits`, or `all` | explorer agent |
| `/plan-review` | `commands/plan-review.md` | Cross-AI plan review via Codex + Gemini | path to plan file (required) | external CLIs (Codex, Gemini) via PowerShell runner |

### Agents

| Agent | File | Model | Tools | maxTurns | Purpose |
|-------|------|-------|-------|----------|---------|
| quality-gate | `agents/quality-gate.md` | haiku | Bash, Read | 18 | Run typecheck/lint/test, report table |
| doc-updater | `agents/doc-updater.md` | haiku | Read, Write, Edit, Grep, Glob, Bash | 15 | Update session log, CLAUDE.md status, architecture docs |
| explorer | `agents/explorer.md` | haiku | Read, Grep, Glob, Bash | 15 | Cross-project codebase exploration and contract tracing |
| reviewer | `agents/reviewer.md` | sonnet | Read, Grep, Glob, Bash | 20 | Code review with project-specific checklist |

> **MCP exclusion**: The three Haiku agents (quality-gate, doc-updater, explorer)
> set `mcpServers: []` in their frontmatter to exclude inherited MCP tool
> definitions (Stripe, Supabase, Context7). The reviewer inherits all MCP servers
> — it may benefit from Supabase/Context7 access during code review. See
> §4 "MCP server exclusion" for rationale.

### Skill

| Skill | File | Flags | Purpose |
|-------|------|-------|---------|
| API Contract | `skills/api-contract/SKILL.md` | `user-invocable: false`, `disable-model-invocation: true` | Passive reference: consolidated contract (error codes, HTML classes, limits, timeouts, endpoints, tiers) |

The skill is not callable — it's a structured reference document that Claude reads
when it needs contract details. Setting `disable-model-invocation: true` prevents
the model from autonomously pulling it into context, which would waste tokens when
the information isn't needed.

### Hook

| Event | Matcher | Action |
|-------|---------|--------|
| `SessionEnd` | `other\|prompt_input_exit` | Echo reminder: "Did you run /session-end before leaving?" |

Configured in `.claude/settings.local.json`.

---

## 3. Workflow Patterns

### Session lifecycle

```
/session-start {project}  →  implement  →  /check  →  /session-end "summary"  →  commit
```

Each command is manually triggered. No command auto-invokes another — the
developer controls progression through the pipeline.

### Session-end pipeline (6 steps)

```
1. Detect modified sub-projects          git status --short in each
2. Run quality gates with lint:fix       typecheck → lint:fix → test (per project)
3. Show lint:fix diff                    git diff --stat → full diff if changed
4. STOP if gates fail                    report failures, do not proceed
5. Update documentation                  delegate to doc-updater agent
6. Show commit preparation               suggested messages, wait for confirmation
```

Step 3 is the visibility gate: `lint:fix` changes are shown as a diff so the
developer can inspect auto-corrections before they become part of the commit.
Step 6 never auto-commits — each sub-project has its own git repo, and commits
require explicit confirmation.

### Review flow

```
/review [target]  →  reviewer agent reads CLAUDE.md(s)  →  reviews diff
                  →  produces Critical / Warnings / Suggestions (3-5 bullets each)
```

The reviewer uses sonnet because it must judge severity and weigh project-specific
conventions (strict TypeScript, Zod `.strict()`, `useShallow`, DOMPurify, etc.)
against generic best practices. Haiku follows instructions well but lacks the
judgment to distinguish a critical security issue from a style nitpick.

### Cross-check flow

```
/cross-check [area]  →  explorer agent  →  checks 6 contract areas  →  report
```

The six areas: error codes, endpoints, HTML classes (`fc-*`), request/response
schemas, domain list, and content limits. Each area has a source of truth
(typically backend) and two consumers (anki, web) that the explorer compares.

### Plan review flow

```
/plan-review {plan.md}  →  PowerShell runner (tools/plan-review/run-reviewers.ps1)
                        →  launches Codex + Gemini in parallel (5-min timeout each)
                        →  Claude parses verdicts (fail-closed)
                        →  dedup + conflict detection  →  aggregate verdict
                        →  patch preview or human escalation  →  up to 3 iterations
```

This is the only command that delegates to **external AI CLIs** rather than Claude
subagents. The PowerShell runner (`tools/plan-review/run-reviewers.ps1`) launches
Codex and Gemini as background jobs, each with a 5-minute timeout. Both reviewers
receive the same structured prompt (from `.claude/templates/plan-review-prompt.md`)
with the plan file path and reviewer ID substituted in.

**Why external CLIs, not Claude subagents?** The entire point is adversarial
diversity — having different model families review the same plan catches blind spots
that any single model would miss. Codex (OpenAI) and Gemini (Google) provide
genuinely independent perspectives.

**Parsing is fail-closed.** If a verdict file contains anything other than valid
JSON with the required schema, it's treated as `ERROR` — no heroic extraction of
JSON from markdown-fenced output. Required fields are validated at two levels:

- Top-level: `verdict` (enum) and `findings` (array)
- Per-finding: `severity`, `category`, `description`, `plan_section` (all non-empty
  strings). Malformed findings would poison downstream dedup and conflict detection.

**Synthesis pipeline** (runs in main context, not delegated):

1. **Dedup**: key = `plan_section` + `category` + first-60-chars-of-description.
   Matching findings merge with "both reviewers agree" annotation.
2. **Conflict detection**: two deterministic rules only — verdict conflict
   (PASS vs BLOCK) and severity conflict (critical/major vs minor/info on same
   dedup key). No fuzzy text comparison.
3. **Aggregate verdict**: conflicts → `NEEDS_HUMAN_REVIEW`, both ERROR → `ERROR`,
   either BLOCK → `BLOCK`, either PASS_WITH_EDITS → `PASS_WITH_EDITS`, both
   PASS → `PASS`.

**Iteration loop** (max 3): on PASS_WITH_EDITS or BLOCK, Claude generates a patch
preview for critical/major findings, presents it for human approval, applies
approved changes, and re-runs reviewers. Minor findings are listed but never
auto-applied. A convergence guard stops early if the dedup key set is identical
between iterations. After the final iteration, persistent major+ findings become
candidates for permanent CLAUDE.md rules (lessons learned).

**Runner details** (`tools/plan-review/run-reviewers.ps1`):

- Uses `Start-Process` with `.cmd` wrappers (`codex.cmd`, `gemini.cmd`) instead of
  `Start-Job`. On Windows, npm-installed CLIs are POSIX shell scripts that break
  inside `Start-Job`'s background process — `.cmd` wrappers are native Win32
  executables that work correctly with `Start-Process`.
- Both reviewers run in parallel via non-blocking `Start-Process -PassThru`, then
  `$proc.WaitForExit($timeout * 1000)` waits on each.
- Stdin is provided via `-RedirectStandardInput` from temp files (pipeline piping
  doesn't work with `Start-Process`).
- Models: Codex uses `codex-5.3` (`-m codex-5.3`); Gemini uses `gemini-3.1-pro`
  (`-m gemini-3.1-pro`).
- Gemini uses `-p ""` for non-interactive mode (no `--approval-mode plan` — that
  flag required an experimental setting and is unnecessary with `-p`).
- All `Set-Content` calls use `-Encoding utf8` to prevent Windows default encoding
  from corrupting non-ASCII characters (e.g., Japanese text in language reviews).
- Codex uses `--output-last-message FILE` (writes its own file); Gemini's output
  requires envelope unwrapping (`$envelope.response`) because the Gemini CLI
  returns a JSON wrapper around the actual response.
- All temp files (prompts, stdout, stderr — 6 total) are cleaned up in a `finally`
  block regardless of outcome.
- The bash command that invokes the runner uses a 10-minute timeout (the script's
  internal per-reviewer timeout is 5 minutes).

### Quality gate delegation

`/check` runs in the main context; `/session-end` runs gates in the main context
too (it needs the pass/fail result to decide whether to proceed). The quality-gate
agent exists for cases where you want to run gates in isolation — keeping 1,700+
lines of test output away from the main conversation.

---

## 4. Operational Heuristics

### Turn budget arithmetic

Agent `maxTurns` values are not arbitrary:

- **quality-gate (18)**: 3 projects × 3 checks (typecheck, lint, test) = 9 tool
  calls minimum. Add 50% margin for retries and output formatting → 14, round up
  to 18. Backend tests alone need a 5-minute timeout.
- **doc-updater (15)**: read git log + read session log + read CLAUDE.md + write
  session log + edit CLAUDE.md = 5 minimum per project. Three projects = 15.
- **explorer (15)**: 6 contract areas × ~2 reads each = 12, plus summary → 15.
- **reviewer (20)**: needs to read CLAUDE.md(s), run git diff, read changed
  files, cross-reference conventions — most variable workload, highest budget.

### Token budget: explorer map trimming

The explorer agent's "Key locations" section (`agents/explorer.md`) lists only
contract-relevant paths, not the entire codebase. This is deliberate — the
explorer's system prompt is part of its token budget, and listing every file in
the monorepo would consume context that should be spent on actual analysis.

### Hook semantics

The SessionEnd hook uses the `other|prompt_input_exit` matcher. Key decisions:

- **SessionEnd, not Stop**: `Stop` fires when Claude **finishes responding**
  (natural turn completion) — it triggers after every single response, not just at
  session end. That's far too frequent for a "did you wrap up?" reminder.
  `SessionEnd` fires once when the session actually ends, which is the correct
  trigger point. (Note: `Stop` does **not** fire on user interrupt via `/stop`.)
- **`other|prompt_input_exit`**: excludes `/clear` (which resets context but
  doesn't end the session). The matcher fires on normal exits and Ctrl+C.
- **Command type only**: hooks can run `command` or `intercept` types. This hook
  is `command` — it prints a reminder but doesn't block the exit. An `intercept`
  would force a response before allowing exit, which would be hostile UX.

### lint:fix asymmetry

- **Backend and web**: use `npm run lint:fix` (ESLint auto-fix)
- **Anki**: uses `flake8` only (no auto-fix equivalent in the Python pipeline)

This is why `session-end.md` step 3 says "check if lint:fix modified any files" —
it only applies to the TypeScript projects.

### Backend test timeout

Backend has 1,700+ tests. The quality-gate agent and `/check` command both
specify a 5-minute timeout for `npm run test`. This is the only check that needs
an explicit timeout — typecheck and lint complete in seconds.

### MCP server exclusion

The three Haiku agents set `mcpServers: []` in their frontmatter to opt out of
MCP tool definition inheritance. Without this, each agent invocation inherits
the full tool schemas for Stripe, Supabase, and Context7 — roughly 5–10K tokens
of definitions that the agent will never use. For Haiku agents doing mechanical
tasks (running tests, updating docs, tracing contracts), those tokens are pure
waste.

The reviewer is left unrestricted (no `mcpServers` field) because it may
legitimately benefit from Supabase or Context7 access when reviewing database
queries or checking library usage patterns.

This is the same philosophy as explorer map trimming (§4 above): agent system
prompts are part of the token budget, and every unnecessary token competes with
the actual work.

---

## 5. Extension Guide

### Adding a command

1. Create `.claude/commands/{verb}.md` (commands are verbs: check, review, start)
2. First line: one-sentence description of what the command does
3. Use `$ARGUMENTS` for user input; document whether it's required or optional
4. If delegating to an agent, name the agent explicitly in the instructions
5. Define an output format template — structured output prevents rambling
6. Add to the "Slash Commands" table in root `CLAUDE.md`

### Adding an agent

1. Create `.claude/agents/{noun}.md` (agents are nouns: reviewer, explorer, gate)
2. Frontmatter (YAML between `---` markers):
   ```yaml
   model: haiku          # default; use sonnet only for judgment tasks
   tools:
     - Read              # list only what the agent needs
     - Grep
   maxTurns: 15          # calculate: (min tool calls) × 1.5, round up
   ```
3. **Model selection heuristic**: if the agent follows a fixed procedure →
   haiku. If it must evaluate, prioritize, or make judgment calls → sonnet.
   Never use opus for agents (cost).
4. **Tool restriction rationale**: tools are a quality lever, not just a
   capability list. An agent with Write access can modify code; one without it
   is read-only by construction. The explorer and reviewer deliberately lack
   Write/Edit — they report findings, they don't fix them.
5. **MCP exclusion**: if the agent doesn't need MCP tools (Stripe, Supabase,
   Context7), add `mcpServers: []` to the frontmatter. This saves ~5–10K tokens
   per invocation by excluding inherited tool schemas. Only omit this field if
   the agent genuinely benefits from MCP access.
6. Add to the "Agents" table in root `CLAUDE.md`

### Adding a skill

1. Create `.claude/skills/{domain}/SKILL.md`
2. Frontmatter flags:
   - `user-invocable: false` — passive reference, not a command
   - `user-invocable: true` — appears as a `/skill-name` command
   - `disable-model-invocation: true` — prevent auto-loading into context
3. Skills consolidate scattered knowledge into a single source of truth.
   The api-contract skill exists because contract details were duplicated
   across three CLAUDE.md files — the skill is the canonical version.

### Adding a hook

1. Edit `.claude/settings.local.json` under the `hooks` key
2. Available events: `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`,
   `Stop`, `SubagentStart`, `SubagentEnd`
3. Matcher syntax: `type|pattern` — e.g., `other|prompt_input_exit`
4. **Limitation**: hooks run `command` (shell) or `intercept` (block + respond).
   Commands are fire-and-forget; intercepts can block operations.
5. Prefer `command` for reminders and notifications; use `intercept` only when
   you need to gate an action (e.g., preventing commits without review).

### Naming conventions

| Type | Convention | Examples |
|------|-----------|----------|
| Commands | Verbs (imperative) | `check`, `review`, `session-start` |
| Agents | Nouns (role) | `reviewer`, `explorer`, `quality-gate` |
| Skills | Domain nouns | `api-contract` |

---

## 6. Anti-Patterns

Failure modes observed in real multi-agent systems, and how this system avoids
each one. Sources: Anthropic docs, community post-mortems, and the research in
`agent-orchestration-research.md`.

### Context starvation

**Problem**: verbose tool output fills the main context window, degrading
performance well before the 200K token limit. Auto-compaction drops file paths,
error codes, and architectural decisions.

**How we avoid it**: quality-gate and explorer agents run in separate context
windows. Their verbose output (test results, file listings) never enters the main
conversation. Commands return structured summaries (tables, bullet points), not
raw output.

### Agents fighting over files

**Problem**: multiple agents editing the same file overwrite each other's changes.
The C compiler project lost work this way with 16 concurrent agents.

**How we avoid it**: agents in this system are either read-only (explorer,
reviewer — no Write/Edit tools) or write to documentation only (doc-updater —
writes to `docs/` and CLAUDE.md, never source code). No two agents can modify the
same file.

### Over-delegation

**Problem**: CLAUDE.md routing rules ("delegate all X to agent Y") are unreliable
because Claude auto-delegates only ~20% of the time.

**How we avoid it**: explicit `/commands` that the developer triggers. No routing
rules in CLAUDE.md — the Agent System section documents what exists but doesn't
instruct the model to auto-invoke anything.

### Unconstrained agents

**Problem**: agents with full tool access can wander — editing unrelated files,
running expensive commands, or entering loops.

**How we avoid it**: every agent has an explicit `tools` list in its frontmatter.
The reviewer gets Read/Grep/Glob/Bash (can investigate but not modify). The
quality-gate gets Bash/Read (can run checks and read output, nothing else). Tool
restriction is a quality lever — it prevents entire categories of misbehavior by
construction rather than by instruction.

### Time blindness

**Problem**: without turn limits, agents happily spend hours looping on failing
tests or exploring irrelevant files. Carlini's observation: "Left alone, Claude
will happily spend hours running tests instead of making progress."

**How we avoid it**: `maxTurns` on every agent acts as a circuit breaker. Budgets
are calculated from minimum required tool calls plus a 50% margin (see
§4 turn budget arithmetic). An agent that hits its turn limit returns whatever
it has — partial results are better than infinite loops.

### Cost multiplication

**Problem**: multi-agent workflows burn ~15× more tokens than single-session
equivalents. The C compiler project cost $20,000 across 2,000 sessions.

**How we avoid it**: haiku is the default agent model (cheapest). Sonnet is used
only for the reviewer (requires judgment). Opus is never used as a subagent.
Turn budgets cap the maximum cost per invocation. The system has 4 agents total —
enough to isolate key concerns, few enough to stay predictable.
