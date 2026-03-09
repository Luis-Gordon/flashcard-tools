# Memogenesis Style Guide

Consolidated cross-project conventions and standards for the Memogenesis (flashcard-tools) ecosystem.

## TypeScript (Backend & Web)
- **Strict Mode**: Must be enabled. No `any` — use `unknown` with runtime narrowing.
- **Imports**: Use type-only imports for types not used at runtime: `import type { User } from './types'`.
- **Validation (Zod)**: Use `.strict()` on all request schemas to reject unknown fields.
- **Interfaces vs Types**: Prefer interfaces for objects, types for unions.

## Python (Anki Add-on)
- **Compatibility**: Python 3.9+ (Anki's bundled version).
- **Type Hints**: Required on all signatures.
- **No `Any`**: Avoid `Any` except for Anki runtime types (`mw`, `Note`, `Collection`) which lack stubs. Use `# type: ignore[...]` if necessary.
- **Config**: Access via `mw.addonManager.getConfig(__name__)`.

## React (Web App)
- **React 19**: Use latest React patterns.
- **Zustand**: Selector hooks MUST use `useShallow` to prevent infinite re-render loops.
- **Sanitization**: Use `DOMPurify` for all card HTML rendering.
- **Styling**: Tailwind CSS v4 only. No inline styles.
- **Memoization**: Use `React.memo` + `useCallback` for list items with callbacks.

## Security Rules
- **No Secrets**: NEVER log, print, or commit secrets, API keys, or sensitive credentials.
- **Input Validation**: ALWAYS validate all input with Zod (backend) or type checking/validation (clients).
- **Internal Errors**: NEVER return internal error details (stack traces, DB errors) to clients.
- **XSS Prevention**: ALWAYS sanitize user-provided HTML before rendering.

## API Contract & HTML Rules
- **Required Fields**:
  - Every request MUST include `product_source` (`'anki_addon'` or `'web_app'`).
  - Every response MUST include `request_id`.
- **Structured HTML**:
  - Use `fc-` prefix for all CSS classes.
  - Structure: `fc-front`/`fc-back` → `fc-section` blocks → `fc-heading` + `fc-content`.
  - Section types: `fc-meaning`, `fc-example`, `fc-notes`, `fc-meta`, `fc-formula`, `fc-code`, `fc-source`.
- **Furigana**: Use `<ruby>kanji<rt>reading</rt></ruby>` for per-kanji annotations. Only on kanji.
- **Timeouts**: Claude 60s, TTS 15s, Unsplash 10s.
