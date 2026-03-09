# Codex Workflow Commands

PowerShell helpers that mirror the existing Claude command flow.

## Commands
- Session context:
  - `pwsh -File tools/codex/session-start.ps1 -Project backend`
  - `pwsh -File tools/codex/session-start.ps1 -Project anki`
  - `pwsh -File tools/codex/session-start.ps1 -Project web`
  - `pwsh -File tools/codex/session-start.ps1 -Project all`
- Quality gates:
  - `pwsh -File tools/codex/check.ps1 -Project auto`
  - `pwsh -File tools/codex/check.ps1 -Project backend`
  - `pwsh -File tools/codex/check.ps1 -Project all`
- Contract checks:
  - `pwsh -File tools/codex/cross-check.ps1 -Area all`
  - `pwsh -File tools/codex/cross-check.ps1 -Area html`
- Session close:
  - `pwsh -File tools/codex/session-end.ps1 -Summary "short summary"`

## Notes
- These scripts do not auto-commit.
- They run inside the monorepo root and call each sub-project repo directly.
