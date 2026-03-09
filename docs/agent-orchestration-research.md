# Agent orchestration in Claude Code: a practitioner's guide

**Claude Code's multi-agent system enables an orchestrator to spawn isolated subagents via the Task tool, each running in its own context window with customizable tools, models, and permissions.** This architecture — proven in production by Anthropic's own 16-agent C compiler project ($20,000, 100,000 lines of Rust) — provides the foundation for parallel fan-out, pipeline, and hub-and-spoke coordination patterns. The system has two tiers: stable subagents (one-way parent→child delegation) and experimental Agent Teams (full inter-agent communication). Most practitioners report that multi-agent setups are worthwhile for roughly **5% of development tasks** — large refactors, batch operations, and parallel code review — while single-session work remains optimal for everything else.

---

## How the Task tool and subagent spawning actually work

The Task tool is Claude Code's built-in mechanism for spawning subagents. When the main agent invokes it, a new agent instance starts with its own separate context window — completely isolated from the parent's conversation.

The **Task tool input schema** accepts four key fields: `description` (a 3–5 word label), `prompt` (the full task instructions), `subagent_type` (referencing built-in agents like "Explore" or custom agents from `.claude/agents/`), and optionally `resume` (an `agentId` from a previous execution to continue that agent's conversation with full prior context). The output returns `result` (the distilled answer), `usage` (token statistics), `total_cost_usd`, and `duration_ms`.

Each subagent execution receives a unique **agentId**, with its conversation stored in a separate transcript file (`agent-{agentId}.jsonl`). Background task output is **truncated to 30,000 characters** when it would overflow the API context, with a file path reference for the full output. This truncation is the key mechanism preventing subagent results from flooding the parent's context window.

Claude Code ships with three built-in subagents optimized for different use cases:

| Built-in Agent | Model | Mode | Tools | Purpose |
|---|---|---|---|---|
| **Explore** | Haiku | Read-only | Glob, Grep, Read, Bash (read-only) | Fast codebase search and analysis |
| **Plan** | Sonnet | Read-only | Read, Glob, Grep, Bash | Research during plan mode |
| **General-purpose** | Sonnet | Read+Write | All tools | Complex multi-step tasks |

The **critical architectural constraint** is that subagents cannot spawn other subagents — this prevents infinite nesting. Never include `Task` in a subagent's tools array. Multiple subagents can run concurrently; the bundled `/batch` skill decomposes work into **5–30 independent units**, spawning one background agent per unit in isolated git worktrees. There is no hard documented cap on parallel subagents, though practitioners commonly run 4–10 simultaneously. You can disable built-in agents selectively via `"permissions": { "deny": ["Task(Explore)", "Task(Plan)"] }` or the `--disallowedTools` CLI flag. The entire Task system can be disabled with `CLAUDE_CODE_ENABLE_TASKS=false`.

---

## Agent configuration: anatomy of `.claude/agents/` files

Custom agents are defined as **Markdown files with YAML frontmatter** stored in `.claude/agents/`. The filename becomes the agent identifier, and the Markdown body below the frontmatter becomes the agent's system prompt.

Here is the complete set of available frontmatter fields:

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Unique identifier (lowercase letters and hyphens) |
| `description` | Yes | Natural-language description; Claude uses this to decide when to delegate |
| `tools` | No | Comma-separated allowlist (inherits all tools if omitted) |
| `disallowedTools` | No | Comma-separated denylist, removed from inherited set |
| `model` | No | `sonnet`, `opus`, `haiku`, or `inherit` (default: `inherit`) |
| `permissionMode` | No | `default`, `acceptEdits`, `bypassPermissions`, `plan`, `ignore` |
| `skills` | No | Comma-separated skill names to preload into agent context |
| `maxTurns` | No | Maximum agentic turns before the subagent stops |
| `memory` | No | Persistent memory scope: `user`, `project`, or `local` |
| `mcpServers` | No | MCP servers available to this subagent |
| `hooks` | No | Lifecycle hooks (PreToolUse, PostToolUse, Stop, etc.) |
| `background` | No | Set `true` to always run as a background task |
| `isolation` | No | Set `"worktree"` to run in a temporary git worktree |

**Priority resolution** follows: project-level (`.claude/agents/`) overrides user-level (`~/.claude/agents/`), which overrides plugin-level agents. Programmatically defined agents (via SDK or `--agents` CLI flag) take precedence over filesystem-based agents with the same name.

A complete, production-quality agent definition looks like this:

```yaml
---
name: code-reviewer
description: Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.
tools: Read, Grep, Glob, Bash
model: sonnet
memory: user
---

You are a senior code reviewer ensuring high standards of code quality and security.

When invoked:
1. Run git diff to see recent changes
2. Focus on modified files
3. Begin review immediately

Review checklist:
- Code is simple and readable
- Functions and variables are well-named
- No duplicated code
- Proper error handling
- No exposed secrets or API keys

Provide feedback organized by priority:
- Critical issues (must fix)
- Warnings (should fix)
- Suggestions (consider improving)
```

Agents can also be defined inline via the CLI (`claude --agents '{JSON}'`) or programmatically through the SDK's `AgentDefinition` dataclass. The `/agents` interactive command manages all subagents within a session.

---

## Proven architectural patterns for multi-agent orchestration

Practitioners have converged on six distinct coordination topologies, each suited to different problem shapes. The most important finding from community experience is that **the right pattern depends entirely on task decomposability** — embarrassingly parallel tasks benefit enormously from fan-out, while tightly coupled work is better handled by a single session.

**Hub-and-Spoke** is the most common pattern. One orchestrator agent spawns specialized workers that each report back independently. The orchestrator synthesizes results. This matches Claude Code's native subagent architecture perfectly since subagents cannot communicate with each other — only with the parent.

**Plan-then-Execute** has emerged as the most effective pattern for complex work. The orchestrator first runs in plan mode to create a detailed task breakdown, then delegates each task to specialized workers. This two-phase approach prevents the common failure mode of workers drifting from architectural intent because each receives explicit, pre-validated instructions.

**Pipeline/Sequential** chains agents in order: Agent A's output feeds Agent B, which feeds Agent C. PubNub's production system implements this as a three-stage pipeline — `pm-spec` → `architect-review` → `implementer-tester` — with status flags (`READY_FOR_ARCH`, `READY_FOR_BUILD`, `DONE`) stored in a queue file and human-in-the-loop handoffs via SubagentStop hooks.

**Task Pool** works well for embarrassingly parallel work. The leader creates a queue of independent tasks, and workers self-assign from it. Anthropic's C compiler project used this with text files as locks in a `current_tasks/` directory, synchronized via git.

**Competing/Debate** deploys multiple agents on the same task with different approaches. The leader evaluates both outputs and picks the best. This is valuable for architectural decisions where the right approach is uncertain — for example, spawning one agent for incremental migration and another for complete rewrite, then comparing.

**Watchdog** pairs a worker with a monitor agent. The worker executes while the watcher validates output quality and can trigger rollbacks. This is critical for production operations needing safety guarantees.

For tasks requiring true inter-agent communication (not just parent-child), **Agent Teams** is the experimental Tier 2 system (enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Teams use seven primitives — TeamCreate, TaskCreate, TaskUpdate, TaskList, Task, SendMessage, TeamDelete — and teammates can message each other directly. However, **agent teams are significantly more token-intensive** since each teammate runs a full context window, and they cannot yet use custom `.claude/agents/` definitions as teammates.

---

## Optimal agent roles, models, and tool permissions

The community has converged on a consistent set of agent roles with clear tool permission boundaries. The fundamental principle is **least privilege**: read-only agents should never have write access, and implementation agents shouldn't have web search to prevent distraction.

| Role | Model | Tools | Rationale |
|---|---|---|---|
| **Planner/Architect** | Opus | Read, Grep, Glob, Search | Complex reasoning for decomposition; read-only prevents premature implementation |
| **Explorer/Researcher** | Haiku | Read, Grep, Glob, Bash (read-only) | Fast, cheap codebase scanning; isolation prevents accidental modifications |
| **Implementer/Maker** | Sonnet | Read, Write, Edit, Bash, Grep, Glob | Balanced capability for code generation; needs full write access |
| **Code Reviewer** | Sonnet | Read, Grep, Glob, Bash | Analysis requires reasoning; read-only prevents "fixing" instead of reviewing |
| **Tester** | Haiku | Read, Bash, Grep, Glob | Test execution is mechanical; Haiku handles it cheaply |
| **Security Auditor** | Sonnet | Read, Bash (scan commands), Grep, WebSearch | Security analysis needs deeper reasoning plus external vulnerability databases |
| **Documentation Writer** | Haiku | Read, Write, Grep, Glob | Docs generation is pattern-following; write access for output only |
| **Debugger** | Sonnet | Read, Bash, Grep, Glob | Root cause analysis needs reasoning; Bash for reproduction |

The **cost optimization pattern** runs the main orchestrator on Opus for complex reasoning while workers handle focused tasks on Sonnet or Haiku. The environment variable `CLAUDE_CODE_SUBAGENT_MODEL` sets the default worker model globally. A critical behavioral note from Anthropic: **Opus 4.6 has a "strong predilection for subagents"** and may spawn them when direct action would suffice — add explicit guidance about when delegation is and isn't warranted.

For system prompt design, effective agent prompts follow a consistent structure: role definition, trigger conditions ("When invoked..."), context discovery instructions (which files to read first, since subagents start with clean context), methodology steps, output format specification, and human-in-the-loop rules. The `description` field is critical — Claude uses it to decide when to auto-delegate. Using phrases like **"Use proactively"** or **"MUST BE USED when..."** improves auto-delegation reliability, though practitioners report that Claude still rarely delegates automatically without explicit CLAUDE.md routing rules.

---

## Context management: the core challenge of multi-agent work

Context management is the single most important concern in multi-agent orchestration. The nominal **200K token context window** drops to approximately **160K–170K tokens** after system overhead, and with multiple MCP servers enabled, can fall to **120K or lower**. Performance degrades well before the window fills due to the "lost-in-the-middle" attention problem, and auto-compaction is lossy — it drops file paths, error codes, and architectural decisions.

The fundamental value proposition of subagents is captured by a simple formula: a task requires `X` tokens of input context, accumulates `Y` tokens of working context, and produces a `Z`-token answer. Without subagents, running `N` tasks consumes `(X + Y + Z) × N` tokens in the main window. With subagents, the parent sees only the `Z`-token results while `(X + Y) × N` tokens are farmed out to isolated windows. **Three parallel subagents effectively give you 600K tokens of total context** without polluting the main session. Jason Liu documented that the same diagnostic task used 169,000 tokens (91% junk) with slash commands versus 21,000 tokens (76% useful) with subagents — **an 8× improvement in information density**.

The most effective coordination pattern is the **"file system as context manager"** approach. Every subagent reads a shared `context.md` first, does its specialized work, writes detailed findings to its own `.md` file, updates `context.md` with a 3-line summary, and returns a pointer ("Plan saved to [filename]. Read before proceeding.") rather than the full output. The orchestrator reads summaries, not full research. This yields **3–4× more efficient token usage** compared to direct context passing.

Practitioners have converged on a **three-layer persistent state system**:

- **CLAUDE.md** serves as the durable convention layer — coding standards, deployment patterns, verification requirements. This survives context compaction and is preloaded into every subagent's context. Keep it under **200 lines / 2,000 tokens** for efficiency.
- **TODO.md** tracks live work state using `[ ]` (pending), `[~]` (in progress), `[x]` (completed), and `[-]` (skipped) markers. The CLAUDE.md should instruct: "Always check TODO.md before starting work; update it as tasks complete."
- **PLAN.md** or **MULTI_AGENT_PLAN.md** holds the implementation plan with task breakdown, dependencies, and status. Architect agents write to this; builder agents read from it and update status on completion.

For context rotation when windows fill up, the **ROTATION-HANDOVER.md** pattern has the agent write current state to a handover file, a hook detects this and triggers `/clear`, and the SessionStart hook injects the handover content into the fresh session — creating automatic context rotation without human intervention.

---

## Real-world orchestration examples that reveal what works

**Anthropic's C compiler project** is the most thoroughly documented multi-agent deployment. Nicholas Carlini ran **16 parallel Claude agents** to build a Rust-based C compiler capable of compiling the Linux kernel. Over ~2,000 Claude Code sessions, the agents produced 100,000 lines of code. Each agent ran in its own Docker container with a bare git repo mounted, using an infinite loop harness (`while true; do claude --dangerously-skip-permissions -p "$(cat AGENT_PROMPT.md)"`). Task coordination used text-file locking in a `current_tasks/` directory with git sync preventing duplicate work. A key finding: agents kept hitting the same bugs and overwriting each other's fixes until a compiler oracle (GCC) was used to partition work so each agent fixed different bugs in different files.

**A 9-parallel-subagent code review system** spawns agents each focused on a different quality dimension — correctness, security, performance, error handling, code style, testing, documentation, simplicity, and change atomicity. The main agent synthesizes findings into a prioritized verdict: "Ready to Merge," "Needs Attention," or "Needs Work." This is implemented as a reusable `.claude/commands/code-review.md` slash command.

**OpenZeppelin's Sui contracts refactoring** used Agent Teams with four AI agents (analyzer, refactorers, coordinator) working on 625+ tests. The critical lesson: agents generated valid code that compiled and passed tests but **violated the refactoring's architectural goals** — a 77-line OR chain that was functionally correct but architecturally wrong. Only the leader agent's oversight caught this drift, not the spec itself. The run consumed **501K tokens in 30 minutes** using Haiku 4.5.

**PromptLayer's documentation pipeline** used 7 agents built with the Claude Code SDK, reducing content creation from 23 hours to 5 hours. For test writing, a developer used Ralph Wiggum loops to migrate integration tests to unit tests overnight, reducing test runtime from **4 minutes to 2 seconds**.

---

## Skills system integration with agents

The skills system (`.claude/skills/`) has been **merged with the custom commands system** — a file at `.claude/commands/review.md` and a skill at `.claude/skills/review/SKILL.md` both create the `/review` command. Skills add three capabilities beyond commands: a directory for supporting files (templates, scripts, examples), frontmatter to control invocation behavior, and automatic loading when contextually relevant.

Skills interact with agents through several mechanisms. The agent's `skills:` frontmatter field **preloads specific skills into the agent's context automatically**, giving the agent domain knowledge without consuming the parent's context window. Skills with `context: fork` run as subagents in isolated context, and the `agent:` field specifies which subagent type drives the forked execution. The bundled `/simplify` skill demonstrates this by spawning **three parallel review agents** (code reuse, code quality, efficiency) that aggregate findings and apply fixes.

Skill descriptions are loaded into context at session start with a budget of **2% of the context window** (fallback: 16,000 characters), configurable via `SLASH_COMMAND_TOOL_CHAR_BUDGET`. The `description` field is critical for auto-discovery — Claude uses semantic matching to decide when to invoke skills. However, practitioners report that automatic activation without hooks succeeds only about 20% of the time; hook-based skill activation (pattern matching on prompts and file paths via `skill-rules.json`) boosts this to approximately 84%.

Key SKILL.md frontmatter fields include `name`, `description`, `argument-hint`, `disable-model-invocation` (prevents auto-invocation), `user-invocable` (set false for background knowledge only), `allowed-tools`, `model`, `context` (set to `fork` for subagent execution), and `agent` (which subagent type runs forked skills). The `!`command`` syntax in skill content runs shell commands as preprocessing — output replaces the placeholder before Claude sees it.

---

## Slash commands as orchestration entry points

Slash commands (`.claude/commands/*.md`) serve as the user-facing entry points for multi-agent workflows. They support `$ARGUMENTS`, positional `$0`/`$1` variables, and dynamic context injection via `` !`shell command` `` syntax. The frontmatter supports `description`, `argument-hint`, `allowed-tools`, and `model` fields.

The most effective pattern uses **workflow commands** that orchestrate agents. The wshobson/commands repository (57 production commands) organizes these into `workflows/` for multi-agent orchestration and `tools/` for single-purpose utilities, invoked as `/workflows:feature-development implement OAuth2` or `/tools:security-scan`. A workflow command might instruct Claude to first delegate to a planner agent, then fan out to implementation agents, then invoke a reviewer.

Boris Cherny (Claude Code's creator) uses commands with inline bash to **pre-compute context** and minimize token usage — for example, a `/commit-push-pr` command that runs `git status` and `git diff --stat` inline so Claude receives the computed output rather than executing commands itself. Other proven command patterns include `/catchup` (reads all changed files in current branch), `/handover` (saves session state before ending), and `/check` (runs all quality checks in parallel).

Commands integrate with CI/CD pipelines through the SDK: `claude /cleanproject && claude /test && claude /commit` in GitHub Actions workflows. Subdirectories create namespaced commands (`.claude/commands/posts/new.md` → `/posts:new`), enabling organized command libraries.

---

## Ralph Wiggum and autonomous loop patterns

Ralph Wiggum is an **official Anthropic plugin** that creates autonomous development loops using a Stop hook. When installed (`/plugin install ralph-wiggum@claude-plugins-official`), the hook intercepts Claude's exit (code 2), re-feeds the original prompt, and Claude continues — seeing modified files and git history from previous iterations. The core invocation is:

```
/ralph-loop "Your task" --max-iterations N --completion-promise "DONE"
```

Anthropic's C compiler harness is described as "if you've seen Ralph-loop, this should look familiar" — a `while true` loop spawning fresh Claude sessions. The multi-agent version runs this in Docker containers with git synchronization. Community extensions add production-grade features: **ralph-orchestrator** (mikeyobrien) adds token tracking, spending limits, and git checkpointing; **ralph-claude-code** (frankbria) adds rate limiting (100 calls/hour), circuit breakers, and 5-hour API limit detection with auto-wait.

The **Oh My Claude Code (OMC)** framework explicitly integrates Ralph with multi-agent orchestration: "when you activate ralph mode, it automatically includes ultrawork's parallel execution." Ralph works best for large refactors, framework migrations, test coverage campaigns, and batch mechanical operations with clear completion criteria. It should **not** be used for ambiguous requirements (the loop won't converge), architectural decisions, or security-critical code. A critical limitation: `--completion-promise` uses exact string matching, which is unreliable — **`--max-iterations` is the real safety net**. Costs scale quickly: a 50-iteration loop can cost $50–100+ in API credits.

---

## Anti-patterns and failure modes to avoid

The most damaging anti-patterns fall into six categories, each documented through real production failures.

**Context starvation** is the most common failure. The 200K ceiling is misleading — system prompts, tool definitions, MCP schemas, and memory files consume **30,000–40,000 tokens before you type anything**. Performance degrades around 147K tokens, not 200K. Auto-compaction summarization drops file paths, error codes, and architectural decisions. The fix: put persistent instructions in CLAUDE.md (survives compaction), delegate large-output tasks to subagents, and run `/compact` manually at logical breakpoints with explicit preservation instructions.

**Agents fighting each other's changes** plagued the C compiler project: "Every agent would hit the same bug, fix that bug, and then overwrite each other's changes. Having 16 agents running didn't help because each was stuck solving the same task." The official docs warn: "If 2 teammates edit the same file, overwrites will occur." The solution is strict domain partitioning — each agent owns specific files or directories, never crossing boundaries. Git worktrees (via `isolation: worktree`) help isolate source code but agents still compete for shared resources.

**Over-delegation and shallow work** manifests when agents take shortcuts. In the OpenZeppelin refactoring, agents generated code that compiled and passed tests but violated the refactoring's architectural goals entirely. The leader agent's oversight caught this, not the spec. Additionally, **Claude rarely auto-delegates** despite documentation claims — the main agent typically handles everything itself. Explicit CLAUDE.md routing rules ("ALL technical issues MUST be handled by specialized subagents") are necessary to force delegation.

**Non-determinism ripple effects** make debugging multi-agent systems uniquely challenging. Changing one part of a workflow — a subagent's prompt, a command, the orchestrator's instructions — can unpredictably change behavior elsewhere. Minor changes to the lead agent can cascade into entirely different subagent behavior through emergent interactions.

**Time blindness** causes agents to spend hours on unproductive loops. Carlini noted: "Left alone, Claude will happily spend hours running tests instead of making progress." The fix: set `maxTurns` limits on subagents, print incremental progress markers, and include `--fast` options for test subsampling during development.

**Cost explosions** are the practical ceiling. The C compiler project cost **$20,000** across 2,000 sessions. Steve Yegge runs three concurrent Claude Max accounts for Gas Town. One Reddit user reported 4 hours of usage consumed in 3 prompts during a plan-mode refactoring. Multi-agent workflows burn approximately **15× more tokens than chat interactions** per Anthropic's own measurements.

---

## Conclusion

Claude Code's agent orchestration system provides a well-designed two-tier architecture — stable subagents for isolated delegation and experimental Agent Teams for inter-agent communication — but the gap between what's possible and what's practical remains significant. The strongest finding across all sources is that **context isolation is the primary value of subagents**, not parallelism or specialization. Each subagent's separate context window prevents the main conversation from being polluted by verbose tool output, and file-mediated coordination (writing results to `.md` files rather than returning them directly) amplifies this benefit by 3–4×.

The most reliable orchestration pattern is **Plan-then-Execute with hub-and-spoke delegation**: use Opus for planning and decomposition, Sonnet for implementation workers, and Haiku for read-only exploration, with strict file-ownership boundaries preventing agents from editing each other's work. CLAUDE.md serves as the durable orchestration hub, TODO.md tracks live state, and explicit routing rules compensate for Claude's reluctance to auto-delegate. The technology works best when tasks are embarrassingly parallel and have clear verification criteria — and practitioners should expect multi-agent work to cost 10–15× more tokens than single-session equivalents.