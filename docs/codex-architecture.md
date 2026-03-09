# Codex Architecture

Technical reference for the Memogenesis Codex orchestration layer (`AGENTS.md` + `.codex/skills` + `tools/codex`).
Audience: senior developers extending or maintaining Codex automation in `flashcard-tools`.

---

## 1. Design Philosophy

Four principles govern this Codex setup.

### Repo-local memory as source of truth

`AGENTS.md` is the Codex memory anchor for this repository. It consolidates:
- session startup protocol
- cross-project API contract invariants
- quality gate defaults
- doc-maintenance rules
- "ask first" and "never" boundaries

The goal is to keep behavioral guidance close to code, not in scattered personal/global state.

### Skills over long always-on prompts

Codex skills are loaded when relevant; they are not all injected into every turn.
This keeps base context lean and pushes detailed procedures into targeted skill docs.

### Scripted workflows over implicit hooks

Claude-style hooks/slash commands are mirrored with explicit PowerShell entrypoints:
- `tools/codex/session-start.ps1`
- `tools/codex/check.ps1`
- `tools/codex/cross-check.ps1`
- `tools/codex/session-end.ps1`

This favors deterministic invocation and easy local debugging.

### Contract safety first

The architecture assumes backend/client drift is the highest recurring risk.
One skill (`memogenesis-contract-auditor`) and one script (`cross-check.ps1`) are dedicated to contract parity checks.

---

## 2. System Inventory

### Memory Layer

| Component | File | Purpose |
|-----------|------|---------|
| Repo memory | `AGENTS.md` | Codex operating contract for Memogenesis |

### Skills

| Skill | File | Purpose | References |
|-------|------|---------|------------|
| Session workflow | `.codex/skills/memogenesis-session-workflow/SKILL.md` | Start/execute/close sessions with consistent gates | `references/session-map.md` |
| Contract auditor | `.codex/skills/memogenesis-contract-auditor/SKILL.md` | Cross-project API/rendering consistency checks | `references/contract-map.md` |
| Doc maintenance | `.codex/skills/memogenesis-doc-maintenance/SKILL.md` | Session logs + CLAUDE.md + architecture updates | `references/doc-update-rules.md` |

### Hook/Command Equivalents

| Workflow | Script | Equivalent role |
|----------|--------|-----------------|
| Session start context load | `tools/codex/session-start.ps1` | `/session-start` |
| Quality gates | `tools/codex/check.ps1` | `/check` + quality-gate agent |
| Cross-project contract check | `tools/codex/cross-check.ps1` | `/cross-check` + explorer agent |
| Session close checklist | `tools/codex/session-end.ps1` | `/session-end` (+ reminder discipline) |

### Operator Reference

| File | Purpose |
|------|---------|
| `tools/codex/README.md` | Usage examples for all scripts |

---

## 3. Workflow Patterns

### Session lifecycle

```
tools/codex/session-start.ps1
  → implement
  → tools/codex/check.ps1
  → tools/codex/cross-check.ps1 (as needed)
  → tools/codex/session-end.ps1
  → per-project commit
```

### Session-start behavior

`session-start.ps1` is read-heavy and prints:
1. root context targets (`PRD.md`, `CLAUDE.md`)
2. sub-project CLAUDE + architecture pointers
3. session-log tails
4. backlog contents when present
5. git status per selected project

This is a deterministic orientation pass, not a semantic summarizer.

### Check behavior

`check.ps1` supports `-Project auto|backend|anki|web|all`.

- `auto`: detects dirty sub-project repos by `git status --short`
- each project runs checks sequentially
- stops at first failure inside a project
- continues to other selected projects
- prints final pass/fail table

### Cross-check behavior

`cross-check.ps1` supports:
- `errors`, `endpoints`, `html`, `schemas`, `domains`, `limits`, `all`

It uses `rg` pattern scans across backend + Anki + web to quickly surface drift candidates.
It is a fast pre-review signal, not a complete semantic proof.

### Session-end behavior

`session-end.ps1` executes:
1. quality gates (`check.ps1 -Project auto`)
2. doc update checklist reminder
3. pending change summaries by sub-project
4. explicit note to commit each repo separately

It does not auto-edit docs and does not auto-commit.

---

## 4. Mapping from Existing `.claude/` System

| Existing Claude component | Codex equivalent |
|---------------------------|------------------|
| root + sub-project `CLAUDE.md` loading | `AGENTS.md` + `session-start.ps1` procedure |
| `/session-start` command | `tools/codex/session-start.ps1` |
| `/check` command + quality-gate agent | `tools/codex/check.ps1` |
| `/cross-check` + explorer agent | `tools/codex/cross-check.ps1` + `memogenesis-contract-auditor` skill |
| `/session-end` + doc-updater agent | `tools/codex/session-end.ps1` + `memogenesis-doc-maintenance` skill |
| `api-contract` passive skill | `memogenesis-contract-auditor` references + `AGENTS.md` contract section |
| SessionEnd reminder hook | `session-end.ps1` as explicit closing step |

Important distinction:
- Claude setup uses subagents and runtime hook handlers.
- Codex setup here is skill-first plus script-driven orchestration.

---

## 5. Extension Guide

### Add a new Codex skill

1. Create under `.codex/skills/{skill-name}/`.
2. Add frontmatter with `name` + trigger-rich `description`.
3. Keep `SKILL.md` procedural and concise.
4. Add `references/` only for content that should load on demand.
5. Update `AGENTS.md` "Local Codex Skills" section.

### Add a new workflow script

1. Add `tools/codex/{name}.ps1`.
2. Keep parameters explicit (`ValidateSet` where possible).
3. Prefer non-destructive defaults.
4. Add usage examples to `tools/codex/README.md`.
5. Reference it from `AGENTS.md` if it is part of default workflow.

### Evolve contract checks

1. Extend `cross-check.ps1` with new `-Area` values.
2. Update `.codex/skills/memogenesis-contract-auditor/references/contract-map.md`.
3. Keep backend source-of-truth paths current.

---

## 6. Known Limitations

### No true event hooks in this layer

The current Codex setup does not register runtime hook callbacks equivalent to Claude plugin hook events.
Behavior is enforced by explicit script invocation and `AGENTS.md` instructions.

### No dedicated Codex subagent files yet

This system currently encodes agent responsibilities as skills + scripts.
If future Codex runtime supports stable subagent manifests for this repo, add them as a separate layer instead of overloading skills.

### `cross-check.ps1` is heuristic

Pattern scanning catches many parity issues quickly but can miss semantic mismatches.
Use full code review for final verification.

---

## 7. Validation Status

The three custom Codex skills were validated with the `quick_validate.py` utility after installing `PyYAML`:
- `memogenesis-session-workflow`: valid
- `memogenesis-contract-auditor`: valid
- `memogenesis-doc-maintenance`: valid

---

## 8. File Index

- `AGENTS.md`
- `.codex/skills/memogenesis-session-workflow/SKILL.md`
- `.codex/skills/memogenesis-session-workflow/references/session-map.md`
- `.codex/skills/memogenesis-contract-auditor/SKILL.md`
- `.codex/skills/memogenesis-contract-auditor/references/contract-map.md`
- `.codex/skills/memogenesis-doc-maintenance/SKILL.md`
- `.codex/skills/memogenesis-doc-maintenance/references/doc-update-rules.md`
- `tools/codex/session-start.ps1`
- `tools/codex/check.ps1`
- `tools/codex/cross-check.ps1`
- `tools/codex/session-end.ps1`
- `tools/codex/README.md`
