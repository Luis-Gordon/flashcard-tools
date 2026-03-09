# Gemini Workflow Tools

PowerShell helper scripts for the Memogenesis monorepo, adapted for use with Gemini CLI. These scripts mirror the functionality of the `tools/codex/` helpers.

## Scripts

### `session-start.ps1`
Loads context for a development session.
```powershell
pwsh -File tools/gemini/session-start.ps1 -Project [backend|anki|web|all]
```

### `check.ps1`
Runs quality gates (typecheck, lint, test) for modified or specified projects.
```powershell
pwsh -File tools/gemini/check.ps1 -Project [auto|backend|anki|web|all]
```

### `cross-check.ps1`
Audits cross-project API and rendering contracts.
```powershell
pwsh -File tools/gemini/cross-check.ps1 -Area [all|errors|endpoints|html|schemas|domains|limits]
```

### `session-end.ps1`
Completes a session by running checks and reminding about documentation updates.
```powershell
pwsh -File tools/gemini/session-end.ps1 -Summary "Summary of work"
```

## Workflow Integration
These scripts are intended to be used as part of the Gemini CLI session workflow. See the root [GEMINI.md](../../GEMINI.md) for details on how to integrate them into your development process.
