---
name: memogenesis-contract-auditor
description: Audit cross-project API and rendering contracts for Memogenesis. Use when backend/client changes may drift across error handling, endpoint paths, request-response schemas, domain support, content limits, or `fc-*` HTML class compatibility.
---

# Memogenesis Contract Auditor

Run focused contract checks and report only actionable mismatches.

## Audit Areas
- `errors`: error codes/status handling consistency
- `endpoints`: route path + method parity
- `schemas`: request/response field parity
- `domains`: domain enum + selector parity
- `html`: `fc-*` class parity between backend prompts and client renderers
- `limits`: content-size and timeout parity

## Workflow
1. Determine requested audit scope (default `all`).
2. Read contract sources listed in [contract-map.md](references/contract-map.md).
3. Compare backend source of truth with Anki and web clients.
4. Report by severity:
  - Critical: runtime breakage or data loss risk
  - Warning: inconsistent behavior with workaround
  - Note: drift that is harmless now but risky later
5. Provide concrete fix locations per mismatch.

## Output Contract
Return:
1. Areas checked
2. Confirmed consistent items
3. Inconsistencies with file paths and exact fields/values
4. Suggested update order (backend first vs clients first)

Do not dump full files. Cite paths and short snippets only.
