# Anki Add-on ↔ Web App: Feature Discrepancy Report

> **Date**: 2026-03-13
> **Method**: Full source read of `flashcard-anki/src/` and `flashcard-web/src/`, cross-referenced against PRD.md (PRD 1 §Shared Backend Endpoints, PRD 2, PRD 3, Product Backlog, Cross-Product Considerations).
> **Scope**: Code-level feature inventory comparison. No recommendations — findings only.

---

## 1. Features the web app has that the add-on lacks

| Feature | Web App Location | PRD Reference | Add-on Status | Notes |
|---------|-----------------|---------------|---------------|-------|
| **User signup** | `routes/Signup.tsx`, `stores/auth.ts` | PRD 3 Phase 1 | Absent | Add-on only has login. Account creation requires web app or direct Supabase. |
| **Directive mode (`content_type='prompt'`)** | `GenerateForm.tsx` contentType toggle, `stores/cards.ts` | PRD 1 POST /cards/generate contract | Absent | Add-on hardcodes `content_type: "text"` in `api/cards.py:69`. No UI to switch modes. |
| **URL content type** | `GenerateForm.tsx` contentType selector | PRD 1 `content_type: 'url'` | Absent | Add-on only supports text input. |
| **PDF content type** | `GenerateForm.tsx` contentType selector | PRD 1 `content_type: 'pdf'` | Absent | Add-on only supports text input. |
| **User guidance (focus highlights)** | `GenerateForm.tsx` — select up to 5 text snippets (80 chars each), floating button | PRD 1 `user_guidance` field; Product Backlog item 2 | Absent | No `user_guidance` reference in add-on source. |
| **User guidance (free-text)** | `GenerateForm.tsx` — 500-char guidance textarea | PRD 1 `user_guidance` field; Product Backlog item 2 | Absent | Same — field not sent by add-on. |
| **Source language selector** | `GenerateForm.tsx`, `stores/cards.ts` sends `source_language` | PRD 1 Backend multi-language (Session 55) | Absent | No `source_language` reference in add-on source. |
| **Output language selector** | `GenerateForm.tsx`, `stores/cards.ts` sends `output_language` | PRD 1 Backend multi-language (Session 55) | Absent | No `output_language` reference in add-on source. Backend backlog explicitly lists "Anki add-on: language preference in settings" as remaining UI work. |
| **Expanded lang sub-hooks (zh, ko, ar, ru)** | `GenerateForm.tsx:70-77` — 6 options: ja, zh, ko, ar, ru, default | PRD 1 Sub-hooks table lists all 6 LANG sub-hooks | Partial | Add-on `constants.py:36-39` only offers 2: "Japanese → English" (ja) and "Other Language (CEFR)" (default). |
| **Card library (persistent server-side)** | `routes/app/Library.tsx`, calls `GET /cards` | PRD 3 Phase 3 | Absent | Add-on creates cards directly in Anki. No server-side library browsing. PRD Shared Endpoints table marks `/cards` (library) as web-only. |
| **Card editing (server-side)** | `Library.tsx`, calls `PATCH /cards/:id` | PRD 3 Phase 3 | Absent | Add-on edits Anki notes locally. |
| **Card deletion (server-side)** | `Library.tsx`, calls `DELETE /cards/:id` and `DELETE /cards` (bulk) | PRD 3 Phase 3 | Absent | Same as above. |
| **Multi-format export (APKG, CSV, MD, JSON)** | `routes/app/Export.tsx`, `lib/export/*` | PRD 3 Phase 4a | Absent | Add-on inserts directly into Anki — no export needed. By design. |
| **Billing management (checkout, portal, upgrade)** | `routes/app/Billing.tsx`, `UpgradeModal.tsx`, calls `POST /billing/checkout`, `GET /billing/portal` | PRD 3 Phase 4b; PRD Cross-Product: "Billing UI lives exclusively in the web app" | Absent | By design — PRD specifies billing is web-only. Add-on shows usage but has no upgrade flow. |
| **GDPR data export** | `routes/app/Settings.tsx`, calls `GET /account/export` | PRD 3 Phase 5 | Absent | No `account/export` call in add-on. |
| **GDPR account deletion** | `routes/app/Settings.tsx`, calls `DELETE /account` | PRD 3 Phase 5 | Absent | No `DELETE /account` call in add-on. |
| **Password change** | `routes/app/Settings.tsx`, calls `supabase.auth.updateUser()` | PRD 3 Phase 5 | Absent | Add-on has login/logout only. |
| **Dark mode / theme toggle** | `stores/settings.ts`, `main.tsx`, `App.tsx` | PRD 3 Phase 5 | N/A | Not applicable — Anki has its own night mode. Add-on FC stylesheet handles `.nightMode`. |
| **Dedicated usage endpoint** | `lib/hooks/useUsage.ts`, calls `GET /usage/current` | PRD 1 `/usage/current`; PRD 2 API table lists it | Absent | PRD 2 says add-on should call `/usage/current`. In code, add-on only reads `usage` from generate/enhance response — never calls `/usage/current` standalone. |
| **Usage progress bar / detailed billing display** | `routes/app/Billing.tsx` — tier, period, overage, cost | PRD 3 Phase 4b | Absent | Add-on shows only "X free remaining" or "paid plan" from generate response. |
| **Rejection visibility** | `routes/app/Generate.tsx`, `CardReview.tsx` — shows `rejectedCards` and `unsuitableContent` | Product Backlog item 1 | Absent | No `rejected` or `unsuitable` parsing in add-on source. Response fields are silently dropped. |
| **Card count expectations messaging** | `CardReview.tsx` — "Generated X of Y (Z filtered by quality checks)" using `lastMaxCards` | Product Backlog item 1; Web Session 29 | Absent | Add-on only shows total generated count. |
| **Error boundary (crash recovery)** | `components/ErrorBoundary.tsx` | PRD 3 Phase 5 | N/A | Not applicable — Anki handles add-on crashes differently. |
| **Pre-rendered marketing pages** | `routes/Landing.tsx`, `Pricing.tsx`, `Privacy.tsx`, `Terms.tsx` | PRD 3 Phase 1 | N/A | Web-only by nature. |
| **User language preference setting** | `routes/app/Settings.tsx`, calls `PATCH /account/language` | Backend backlog: "Account settings endpoint for updating user_language" | Absent | Add-on has no language preference in settings. Backend backlog explicitly lists this as remaining. |
| **Extension handoff (URL params)** | `GenerateForm.tsx` reads `?content=&source_url=&domain=` | PRD 4 / PRD 3 Phase 2 | N/A | Web-only by nature. |

---

## 2. Features the add-on has that the web app lacks

| Feature | Add-on Location | PRD Reference | Web App Status | Notes |
|---------|----------------|---------------|----------------|-------|
| **Card enhancement** | `api/enhance.py`, `enhance/processor.py`, `ui/dialogs/enhance.py` | PRD 2 Phase 4; PRD Shared Endpoints: `/cards/enhance` marked "✓ (future)" for web | Absent | Web app has no enhance endpoint calls, no enhance UI. PRD Cross-Product table explicitly marks this as "future" for web. |
| **TTS generation & playback** | `enhance/media.py`, `api/generate_with_assets.py`, review dialog `_TtsPlayButton` | PRD 2 Phase 5; PRD Shared Endpoints: `/assets/tts` marked "✓ (future)" for web | Absent | No `/assets/tts` or `/assets/image` calls in web app source. |
| **Image search & attachment** | `enhance/media.py`, `api/generate_with_assets.py` | PRD 2 Phase 5; PRD Shared Endpoints: `/assets/image` marked "✓ (future)" for web | Absent | Same as TTS — marked future in PRD. |
| **Generate-with-assets pipeline** | `api/generate_with_assets.py` — chains generate → enhance (asset-only) → download | PRD 2 Phase 5 | Absent | Web app generates cards only. No post-generation asset enrichment. |
| **CSS stylesheet injection into note types** | `styles/stylesheet.py`, `ui/dialogs/styles.py` | PRD 2 Phase 7c | N/A | Web app renders `fc-*` HTML via DOMPurify + Tailwind arbitrary selectors. Anki needs explicit CSS injection into note types. |
| **Direct Anki note creation** | `generate/processor.py` — `create_notes_in_anki()`, `create_notes_with_media()` | PRD 2 Phase 3 | N/A | Web app exports via APKG/CSV/etc. Different by architecture. |
| **Browser context menu integration** | `hooks.py` — right-click "Enhance with AI" in card browser | PRD 2 Phase 4 | N/A | Anki-specific UI pattern. |
| **Anki sync guard** | `utils/sync_guard.py` — blocks API calls during Anki sync | PRD 2 Boundaries | N/A | Anki-specific constraint. |
| **Undo support via `mw.checkpoint()`** | `generate/processor.py`, `enhance/processor.py` | PRD 2 Boundaries | N/A | Web app has undo-delete (5s timer) for library only. Generation is non-destructive (Zustand state). |
| **Configurable enhancement defaults** | `utils/config.py` — persistent defaults for context, tags, formatting, TTS, images | PRD 2 Phase 6 | N/A | Web app has no enhancement feature. |
| **TTS direction filtering** | `api/generate_with_assets.py` — `_filter_tts_by_direction()` strips non-target-language TTS based on direction tags | PRD 2 Phase 5 | Absent | Web app has no TTS handling. |

---

## 3. Behavioural divergences on shared features

| Feature | Anki Add-on Behaviour | Web App Behaviour | Delta |
|---------|----------------------|-------------------|-------|
| **Auth provider** | Direct `POST /auth/login` and `POST /auth/refresh` to backend. Tokens stored in Anki config (plaintext JSON). | Supabase Auth client (`supabase.auth.signInWithPassword`, `signUp`, `getSession`). Tokens managed by Supabase JS SDK. | Different auth mechanisms against the same Supabase instance. Add-on calls backend auth endpoints; web app calls Supabase client directly. |
| **401 handling** | Transparent refresh via `POST /auth/refresh` → retry once. If still 401, raises `AuthenticationError` → UI shows error. | `notifyUnauthorized()` → debounced (1s cooldown) → toast "Session expired" → `signOut()` → redirect to `/login`. No retry. | Add-on retries silently; web app signs out immediately. |
| **402 handling** | Shows static message: "Free tier limit reached. Please upgrade to continue generating/enhancing." No link to web app. | Shows `UpgradeModal` with tier comparison table and direct Stripe Checkout redirect. | Add-on dead-ends; web app provides an upgrade path. |
| **Usage display** | Reads `usage.free_remaining` from generate response only. Shows "(X free remaining)" or "(paid plan)" in review dialog header. Never calls `/usage/current`. | Calls `GET /usage/current` on app load and after each generation (via `USAGE_CHANGED_EVENT`). Shows tier, cards used/limit, progress bar, overage cost, period dates in sidebar and billing page. | Add-on usage display is reactive (generation response only) and limited to free-tier info. Web app is proactive and comprehensive. |
| **Domain selector** | Flat dropdown with 10 domains as `(display, value)` tuples. No descriptions or icons. | Grid of 10 domain cards with icons, labels, and descriptions. 3-column responsive layout. | Visual presentation only; same 10 domain values. |
| **Lang sub-hook selector** | 2 options: "Japanese → English" (`ja`), "Other Language (CEFR)" (`default`). | 6 options: Japanese (`ja`), Chinese (`zh`), Korean (`ko`), Arabic (`ar`), Russian (`ru`), Other (`default`). | Web app exposes all 6 backend sub-hooks; add-on exposes only 2. |
| **hook_key conditional inclusion** | `hook_key` included at top level of request body only when domain is `"lang"`. Set to `None` otherwise. | `hookKey` conditionally spread into request: `...(hookKey ? { hook_key: hookKey } : {})`. Set to `undefined` for non-lang domains. | Functionally equivalent — both omit `hook_key` for non-lang domains. |
| **Content type** | Hardcoded to `"text"`. No URL/PDF/prompt mode. | User-selectable: text, url, pdf, prompt. Content type sent in request. | Add-on supports only text; web app supports all 4 backend content types. |
| **Max cards control** | `QSpinBox` with range 1–50, default from settings. | Slider with range 1–50, default 10. | Same range, different control widget. |
| **Card review/editing** | `ReviewDialog` with editable `QTextEdit` for front/back, `QLineEdit` for tags. Select/deselect checkboxes. No notes editing. | `CardEditor` component with front/back/tags/notes inline editing. SanitizedHTML preview. Select/delete individual cards. | Web app includes notes editing in review; add-on does not. Web app shows rendered HTML; add-on shows raw text. |
| **Rejected cards handling** | `api/cards.py` does not parse `rejected` or `unsuitable_content` from response. Fields silently dropped. | Stored in `rejectedCards` and `unsuitableContent` state. Displayed in `CardReview` with reasons. Collapsible unsuitable content section. | Add-on discards quality feedback; web app displays it. |
| **HTML sanitization** | Custom `HTMLParser`-based sanitizer in `utils/sanitize.py`. Blocklist approach: strips dangerous tags, blocks JS URLs, preserves `fc-*` and `<ruby>`. | DOMPurify with strict tag/attribute allowlist in `SanitizedHTML.tsx`. Allowlist-only approach. | Both sanitize, but different mechanisms. Add-on is blocklist-based; web app is allowlist-based. |
| **fc-* CSS rendering** | Requires explicit stylesheet injection into Anki note types (`styles/stylesheet.py`). User-initiated via "Install Card Styles" dialog. | Tailwind arbitrary selectors in `CardReview.tsx` (e.g., `[&_.fc-word]:font-semibold`). Applied automatically during render. | Different rendering approach appropriate to each platform. |
| **Generate timeout** | 60s (`api/client.py`). | 90s (AbortController in `api.ts`). | Web app has 30s more buffer. Backend Claude API timeout is 60s in both cases. |
| **429 retry mechanism** | `time.sleep(retry_after)` capped at 60s, max 2 retries. Blocking sleep on background thread. | Abort-aware async wait using `setTimeout` + `AbortSignal`. Respects overall AbortController timeout. Max 2 retries, cap 60s. | Both retry up to 2× with 60s cap. Add-on uses blocking sleep; web app uses abort-aware async wait. |
| **product_source** | `"anki_addon"` | `"web_app"` | As specified by PRD. |
| **Settings persistence** | Anki config system (`mw.addonManager.getConfig`). Thread-locked access. Includes generation defaults, enhancement defaults, API URL, auth tokens. | Zustand `persist` middleware → localStorage. Stores view mode, theme, recent deck names. API URL from env vars, auth from Supabase. | Different persistence layers appropriate to each platform. |
| **Keyboard shortcuts** | `Ctrl+Shift+E` for enhance (browser context). No generation shortcut. | `Ctrl+Enter` for generate, `Ctrl+E` for export. Platform-aware (⌘ on Mac). | Different shortcut sets reflecting different workflows. |

---

## 4. Backend endpoints the add-on calls that the web app does not, and vice versa

**Reference**: PRD 1 § Cross-Product Considerations → Shared Backend Endpoints table.

| Endpoint | PRD: Web | PRD: Anki | Web Actually Calls | Anki Actually Calls | Discrepancy vs PRD |
|----------|----------|-----------|-------------------|--------------------|--------------------|
| `/auth/signup` | ✓ | — | Via Supabase client (not backend endpoint) | — | Web uses Supabase directly, not the backend `/auth/signup` endpoint |
| `/auth/login` | ✓ | ✓ | Via Supabase client (not backend endpoint) | ✓ `POST /auth/login` | Web uses Supabase directly; add-on calls backend |
| `/auth/refresh` | ✓ | ✓ | Via Supabase client (automatic) | ✓ `POST /auth/refresh` | Same split |
| `/auth/me` | ✓ | ✓ | Not called | Not called | Neither client calls `/auth/me` in normal operation |
| `/cards/generate` | ✓ | ✓ | ✓ | ✓ | Both call it |
| `/cards/enhance` | ✓ (future) | ✓ | **Not called** | ✓ | Web marked "future" in PRD — consistent |
| `/cards` GET (library) | ✓ | — | ✓ | **Not called** | As expected by PRD |
| `/cards/:id` PATCH | ✓ | — | ✓ | **Not called** | As expected |
| `/cards/:id` DELETE | ✓ | — | ✓ | **Not called** | As expected |
| `/cards` DELETE (bulk) | ✓ | — | ✓ | **Not called** | As expected |
| `/assets/tts` POST | ✓ (future) | ✓ | **Not called** | ✓ (via enhance flow) | Web marked "future" — consistent |
| `/assets/tts/:cacheKey` GET | ✓ (future) | ✓ | **Not called** | ✓ | Same |
| `/assets/image` POST | ✓ (future) | ✓ | **Not called** | ✓ (via enhance flow) | Same |
| `/usage/current` GET | ✓ | ✓ | ✓ | **Not called** | **Gap**: PRD 2 API table lists `/usage/current` for the add-on, but add-on never calls it — usage only read from generate/enhance response payloads |
| `/billing/checkout` POST | ✓ | — | ✓ | **Not called** | As expected |
| `/billing/portal` GET | ✓ | — | ✓ | **Not called** | As expected |
| `/billing/webhook` POST | Stripe sig | — | N/A (Stripe calls it) | N/A | Not a client endpoint |
| `/account` DELETE | ✓ | — | ✓ | **Not called** | Web-only GDPR feature |
| `/account/export` GET | ✓ | — | ✓ | **Not called** | Web-only GDPR feature |
| `/account/language` PATCH | — | — | ✓ | **Not called** | Not in PRD endpoint table (added post-PRD) |

### Endpoint gap summary

- **Add-on vs PRD**: `/usage/current` — PRD 2 lists it as a consumed endpoint, but the add-on never calls it.
- **Web app intentionally absent**: `/cards/enhance`, `/assets/tts`, `/assets/image` — all marked "✓ (future)" in PRD Shared Endpoints table.
- **Auth mechanism divergence**: Web app uses Supabase client SDK directly instead of backend `/auth/*` endpoints. Both approaches authenticate against the same Supabase project, but through different paths.
- **Post-PRD endpoint**: `/account/language` PATCH is called by the web app but does not appear in the PRD endpoint table.
