# Gemini Architecture

Technical reference for the Memogenesis Gemini CLI orchestration layer (`GEMINI.md` + `.gemini/` + `tools/gemini/`).
Audience: senior developers extending or maintaining Gemini CLI automation in `flashcard-tools`.

---

## 1. Design Philosophy

The Gemini CLI setup for Memogenesis follows four core principles to ensure consistency and efficiency.

### Repo-local configuration as foundational mandate

`GEMINI.md` (root) is the primary instruction set for Gemini CLI in this repository. It auto-loads and takes absolute precedence. It consolidates:
- repository structure and project map
- technical stack and architectural principles
- cross-project API contracts and HTML rendering rules
- deployment coordination checklists
- critical constraints ("Never/Always" rules)

### Structured style guide for technical precision

Technical standards (TypeScript strict mode, Python type hints, React rules, Security) are isolated in `.gemini/styleguide.md`. This separates **architectural intent** (in `GEMINI.md`) from **implementation mechanics**, keeping the main context focused on goals while providing a deep-dive reference for code generation.

### Explicit PowerShell orchestration

Similar to the Codex setup, Gemini workflows are driven by explicit PowerShell scripts in `tools/gemini/`. This ensures:
- **Deterministic execution**: Scripts follow a fixed procedure (e.g., check → lint → test).
- **Environment parity**: Workflows run identically regardless of the AI tool being used.
- **Local debugging**: Developers can run the same scripts used by the AI to verify results.

### Strategic Delegation & Turn Efficiency

Gemini CLI's context window is its most precious resource. The architecture promotes:
- **Turning compression**: Utilizing parallel tool calls and requested context (before/after/context) to reduce round-trips.
- **Sub-agent delegation**: Using `codebase_investigator` for research and `generalist` for batch tasks to keep the main session history lean.

---

## 2. System Inventory

### Core Configuration

| Component | File | Purpose |
|-----------|------|---------|
| Root Instructions | `GEMINI.md` | Primary auto-loaded mandate for the repo |
| Style Guide | `.gemini/styleguide.md` | Consolidated coding standards and technical rules |
| Runtime Settings | `.gemini/settings.json` | CLI-specific configuration (e.g., sandbox: none) |

### Sub-Project Mandates

| Project | File | Purpose |
|---------|------|---------|
| Backend | `flashcard-backend/GEMINI.md` | Backend-specific status, tasks, and constraints |
| Anki Add-on | `flashcard-anki/GEMINI.md` | Add-on-specific status, tasks, and constraints |
| Web App | `flashcard-web/GEMINI.md` | Web-app-specific status, tasks, and constraints |

### Workflow Scripts (`tools/gemini/`)

| Workflow | Script | Description |
|----------|--------|-------------|
| Session Start | `session-start.ps1` | Loads context, reads logs, and checks git status |
| Quality Gates | `check.ps1` | Runs typecheck → lint → test (auto-detects projects) |
| Contract Check | `cross-check.ps1` | Audits API/HTML parity across projects using `rg` |
| Session End | `session-end.ps1` | Runs final gates and reminds about documentation |

---

## 3. Workflow Patterns

### Session Lifecycle

The standard development lifecycle follows a **Research -> Strategy -> Execution** pattern:

1. **Start**: `pwsh -File tools/gemini/session-start.ps1 -Project {project}`
2. **Research**: Map the codebase using `grep_search` and `glob`.
3. **Strategy**: Propose a plan and testing strategy.
4. **Implement**: Follow conventions in `.gemini/styleguide.md`.
5. **Verify**: Run `pwsh -File tools/gemini/check.ps1 -Project {project}`.
6. **End**: `pwsh -File tools/gemini/session-end.ps1 -Summary "summary"`.

### Technical Integrity & Validation

Validation is the only path to finality. A task is not complete until:
- **Behavioral correctness** is verified (tests pass).
- **Structural integrity** is confirmed (typecheck/lint pass).
- **Stylistic consistency** is maintained (styleguide followed).

### Deployment Coordination (The "Session 58" Rule)

When modifying API schemas:
1. Deploy **Backend** first.
2. Verify health.
3. Deploy **Client** (Anki or Web).
4. Never commit cross-project schema changes without deploying both sides in the same session.

---

## 4. Mapping from Other Systems

| Claude/Codex Concept | Gemini CLI Equivalent |
|----------------------|-----------------------|
| `CLAUDE.md` / `AGENTS.md` | `GEMINI.md` (root and sub-project) |
| `.claude/commands/` | `tools/gemini/*.ps1` scripts |
| `.claude/agents/` | Delegation to `codebase_investigator` or `generalist` |
| `.claude/skills/` | `.gemini/styleguide.md` + system instructions |
| Slash commands (`/check`) | Manual script invocation (`tools/gemini/check.ps1`) |

---

## 5. Extension Guide

### Update Implementation Rules
- Modify `.gemini/styleguide.md`. This is the single source of truth for technical "how-to".

### Evolve Workflow Automation
- Add or modify scripts in `tools/gemini/`.
- Ensure new scripts are documented in `tools/gemini/README.md`.

### Adding a New Sub-Project
- Create `{project}/GEMINI.md`.
- Update the "Repository Structure" and "Commands" sections in the root `GEMINI.md`.
- Update `tools/gemini/check.ps1` and `session-start.ps1` to include the new path.

---

## 6. File Index

- `GEMINI.md`
- `.gemini/settings.json`
- `.gemini/styleguide.md`
- `flashcard-backend/GEMINI.md`
- `flashcard-anki/GEMINI.md`
- `flashcard-web/GEMINI.md`
- `tools/gemini/session-start.ps1`
- `tools/gemini/check.ps1`
- `tools/gemini/cross-check.ps1`
- `tools/gemini/session-end.ps1`
- `tools/gemini/README.md`
