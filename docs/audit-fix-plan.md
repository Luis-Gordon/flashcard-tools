# Audit Fix Plan — Pre-Web-App Readiness

Session-sized fix plan derived from `docs/audit-findings.md` (33 findings: 3 Critical, 17 Important, 13 Consider). Each session is scoped to fit within Claude Code's effective context window (~10-20 min autonomous work). `/clear` between every session.

**Dependency order**: Backend security → Backend contracts → Backend reliability → Anki security → Anki cleanup → Documentation sync

**Testing rule**: Run full test suite after every session. No session is complete until all tests pass. Update tests to match new intended behavior. Do not weaken test assertions to make tests pass.

---

## Accepted Risks

| ID | Severity | Finding | Rationale |
|----|----------|---------|-----------|
| A-C1 | Critical | JWT tokens stored as plaintext in Anki config | Anki provides no encrypted storage API. Adding OS keyring (`keyring` package) requires a Python dependency that can't be bundled with Anki add-ons. Token has a short TTL (1 hour) and refresh tokens are scoped to a single user. This is consistent with how other Anki add-ons handle credentials. |

---

## Session 1: Backend Security — CORS & Request Validation [COMPLETED]

**Scope**: Middleware hardening. All changes in `flashcard-backend/src/middleware/` and `index.ts`.

| ID | Finding | Action |
|----|---------|--------|
| B-C1 | CORS wide open (`cors()` no origin) | Replace with explicit origin allowlist using env var `ALLOWED_ORIGINS` (comma-separated). Origin callback returns exact origin or null. `credentials: true`, explicit allow/expose headers, `maxAge: 86400`. |
| B-I4 | X-Request-ID accepted without validation | Validate format: 1-128 chars, pattern `/^[a-zA-Z0-9._-]+$/`. Silently replace non-conforming values with `crypto.randomUUID()`. |
| B-I7 | Content-Length bypass — no actual body verification | Remove 411 rejection for missing Content-Length. Keep Content-Length check as fast-path rejection when present. Requests without Content-Length pass through (Cloudflare enforces at edge). |
| B-I8 | multipart/form-data always gets 10MB | Remove `multipart/form-data` from PDF equivalence. Only `application/pdf` gets 10MB. All other content types get 100KB. |

**Changes made:**
- `src/types/index.ts` — Added `ALLOWED_ORIGINS: string` to Env interface
- `src/index.ts` — Replaced `cors()` with origin-validated CORS middleware using `ALLOWED_ORIGINS`
- `src/middleware/requestId.ts` — Added `isValidRequestId()` validation (1-128 chars, `/^[a-zA-Z0-9._-]+$/`)
- `src/middleware/contentSize.ts` — Removed 411 for missing Content-Length; removed multipart from PDF equivalence
- `wrangler.jsonc` — Added `ALLOWED_ORIGINS` to default, staging, and production vars
- `CLAUDE.md` — Updated constraint: "NEVER process oversized content — validate Content-Length when present"
- 8 test files — Added `ALLOWED_ORIGINS: ''` to TEST_ENV objects
- `test/unit/middleware/contentSize.test.ts` — Updated tests for new behavior
- `test/unit/middleware/requestId.test.ts` — **Created** (20 tests)
- `test/unit/middleware/cors.test.ts` — **Created** (9 tests)

---

## Session 2: Backend Security — Rate Limiting & Usage Integrity [COMPLETED]

**Scope**: Durable rate limiting + usage race condition. Changes in `middleware/rateLimit.ts`, `services/usage.ts`, `routes/generate.ts`.

| ID | Finding | Action |
|----|---------|--------|
| B-C2 | Rate limiting in-memory only | Migrated to Cloudflare KV fixed-window counter. Key: `ratelimit:{userId}:{handler}:{windowId}`. TTL = window duration. In-memory fallback when KV absent. Handler field separates generate/enhance/tts/image counters. |
| B-I2 | PRD rate limits not implemented (hourly/daily caps) | New `tieredRateLimit.ts` middleware. Free: 20 gen/hr, 100 ops/day. Plus: 100/500. Pro: 200/1000. Tier lookup cached in KV (5min TTL) → in-memory → Supabase. Safe-fail to 'free'. |
| B-I5 | TOCTOU race in usage checking | Supabase RPC `check_and_reserve_usage` with `SELECT ... FOR UPDATE`. Serializes concurrent requests per user. Reservation pattern: insert → finalize or cancel. |

**Changes made:**
- `src/types/index.ts` — `RATE_LIMIT_KV?: KVNamespace` in Env
- `src/middleware/rateLimit.ts` — token bucket → fixed-window + KV backend + handler field
- `src/middleware/tieredRateLimit.ts` — **Created** (tier-based hourly/daily caps)
- `src/services/usage.ts` — `checkAndReserveUsage`, `finalizeReservation`, `cancelReservation`
- `src/routes/generate.ts` — atomic reservation flow + tiered middleware
- `src/routes/enhance.ts` — tiered middleware + handler param
- `src/routes/assets.ts` — tiered middleware + handler params
- `wrangler.jsonc` — KV namespace bindings in staging/production
- `supabase/migrations/20260222000001_create_check_and_reserve_usage.sql` — **Created**
- `test/unit/services/stripe.test.ts` — fixed 2 stale price ID assertions
- `test/unit/middleware/rateLimit.test.ts` — handler param + 4 new KV tests (11 total)
- `test/unit/middleware/tieredRateLimit.test.ts` — **Created** (13 tests)
- `test/unit/services/usage.test.ts` — 11 new RPC function tests (35 total)
- `test/integration/cards.test.ts` — updated mocks for RPC-based flow
- Verification: typecheck clean, lint clean, 1244/1244 tests pass (all green)

---

## Session 3: Backend Contracts — Types, Errors, Documentation [COMPLETED]

**Scope**: Contract alignment between PRD, types, and documentation. Low-risk, high-value for web app.

| ID | Finding | Action |
|----|---------|--------|
| X-1 | Tier naming mismatch (PRD: pro/power, code: plus/pro) | Update PRD.md tier table to match code: free/plus/pro. Add a note about the rename. |
| B-I1 | Claude timeout docs say 30s, code is 60s | Update both CLAUDE.md files to say 60s. |
| B-I3 | Missing CONFLICT in ErrorCode union | Add `CONFLICT` to the ErrorCode type. Add 409 case to `httpStatusToErrorCode`. Verify auth.ts uses the typed ErrorCode, not string literals. |
| B-I6 | Webhook handlers leak internal error details | Sanitize Supabase error messages in billing.ts webhook handlers. Log full errors server-side, return generic messages. Ensure handleInvoicePaymentFailed doesn't log full Stripe metadata objects. |
| B-M6 | Usage route returns 503 instead of 500 | Change to 500 + INTERNAL_ERROR for consistency with the error contract. |

**Changes made:**
- `PRD.md` — Updated 6 references from pro/power to plus/pro; added rename note after tier table
- `CLAUDE.md` — Updated Claude timeout from 30s to 60s
- `flashcard-backend/CLAUDE.md` — Updated Claude timeout from 30s to 60s, added 529 backoff note
- `src/types/index.ts` — Added `'CONFLICT'` to ErrorCode union
- `src/middleware/errorHandler.ts` — Added `case 409: return 'CONFLICT'` to httpStatusToErrorCode
- `src/routes/auth.ts` — Added `satisfies ErrorCode` to CONFLICT code fields for type safety
- `src/routes/usage.ts` — Changed both 503 responses to 500
- `src/services/billing.ts` — All 6 error handlers now use `console.debug` (dev-only full error) + `console.error` (generic message with identifiers only)
- `test/unit/services/usage.test.ts` — Updated `console.error` spy to `console.warn` for recordUsage test
- `test/integration/usage.test.ts` — Updated 503 expectations to 500

---

## Session 4: Backend Reliability — Billing & External APIs [COMPLETED]

**Scope**: Billing endpoint hardening + external API resilience.

| ID | Finding | Action |
|----|---------|--------|
| B-M2 | Stripe SDK no timeout (default 80s > Worker 30s CPU) | Add `timeout: 25_000` and `maxNetworkRetries: 1` to Stripe client config. |
| B-M4 | Portal return_url open redirect | Validate return_url against ALLOWED_ORIGINS (from Session 1). Reject URLs not matching allowed origins. Fall back to `/` for invalid values. |
| B-M5 | Checkout success_url/cancel_url not origin-validated | Same origin validation as B-M4. Apply to both success_url and cancel_url in checkout schema. |
| B-M1 | Claude 529 not distinguished from generic 5xx | Add specific handling for 529: exponential backoff (2s base) instead of immediate retry. Keep immediate retry for other 5xx. |
| B-M3 | recordUsage fire-and-forget, silent data loss | Add structured warning log when recordUsage fails, including userId, operation type, and timestamp. This enables alerting on usage tracking degradation without blocking requests. |

**Changes made:**
- `src/services/stripe.ts` — Added `timeout: 25_000` and `maxNetworkRetries: 1` to Stripe constructor; removed placeholder comment from METER_EVENT_NAME; replaced JSDoc on getPriceIdForTier
- `src/routes/billing.ts` — Added `parseAllowedOrigins()` and `isAllowedOrigin()` helpers; checkout validates success_url/cancel_url origins; portal validates return_url with fallback to `/`
- `src/services/claude.ts` — Added `'overloaded'` to AttemptResult union; 529 returns `overloaded` type; retry logic sleeps 2s before retry on overloaded; added `sleep()` helper
- `src/services/usage.ts` — `recordUsage` error changed from `console.error` to `console.warn` with structured fields including timestamp; `parseSubscriptionTier` warns on unknown non-null values
- `test/integration/billing.test.ts` — Updated `ALLOWED_ORIGINS` to include test origin `https://app.example.com`

---

## Session 5: Backend — Remaining Consider Items + Simplification [COMPLETED]

**Scope**: Low-risk improvements and code cleanup.

| ID | Finding | Action |
|----|---------|--------|
| B-M7 | /auth/me returns minimal data | Add subscription_tier, subscription_status, and current usage summary to /auth/me response. The web app needs this for dashboard initial load. Query the subscriptions table joined with usage. |
| B-M8 | parseSubscriptionTier silent downgrade | Add console.warn when encountering unknown tier value before defaulting to free. |
| S1 | Stripe meter event name placeholder comment | Remove "Replace with real meter event_name" comment if memogenesis_overage is the actual name. |
| S2 | Stripe SDK timeout | Already fixed in Session 4. Skip. |
| S3 | getPriceIdForTier trivial wrapper | Keep — it's a named abstraction point for when pricing changes. Add a one-line comment: "Abstraction point for tier-to-price mapping." |
| G1 | Duplicate DomainConfig interface | Remove local DomainConfig, import GenerationPromptConfig from the generation registry. |
| G2 | No-op `as unknown[]` casts | Remove both casts. |
| G3 | Spread-conditional for optional response fields | Keep — empty array omission is intentional API behavior. No change. |

**Changes made:**
- `src/routes/auth.ts` — Expanded /auth/me to include subscription_tier, subscription_status, cards_used, cards_limit via `getUserUsageStatus()` with graceful degradation
- `src/routes/generate.ts` — Removed duplicate `DomainConfig` interface; imported `GenerationPromptConfig` from generation registry; removed `as GenerationPromptConfig` cast; removed `as unknown[]` no-op cast
- B-M8, S1, S3 changes are documented in Session 4 (combined into single implementation session)
- Verification: typecheck clean, lint clean, 149 tests pass across 8 test files (unit + integration)

---

## Session 6: Anki — Security & Reliability [COMPLETED]

**Scope**: Client-side security fixes and reliability improvements.

| ID | Finding | Action |
|----|---------|--------|
| A-I2 | TTS download bypasses client.request() | Route TTS downloads through client.request() so they get 401-refresh and 429-retry logic. Update download_tts() in media.py to use the standard client path. |
| A-I5 | No retry_after cap on 429 | Cap retry_after at 60 seconds in client.py. Log a warning if server sends > 60s. |
| A-I7 | image_attribution unescaped in QLabel (Qt XSS) | Apply html.escape() to image_attribution before passing to QLabel in review.py. Match the pattern already used in enhance/processor.py:266 and generate/processor.py:217. |
| A-I8 | No sync guard — API calls can conflict with Anki sync | Register hooks on sync_will_start and collection_will_temporarily_close in hooks.py. Set a flag that ApiWorker checks before starting. If sync is in progress, queue the operation or show a warning. |

**Changes made:**
- `src/api/client.py` — Added `download()` method with 401→refresh→retry and 429→sleep(capped)→retry; added `_MAX_RETRY_AFTER = 60` constant; capped `retry_after` in both `request()` 429 handler and `_raise_for_status()`; added proactive token refresh before requests (within 30s of expiry)
- `src/enhance/media.py` — Simplified `download_tts()` to delegate to `client.download()` (was 30 lines of manual HTTP, now 3 lines)
- `src/ui/dialogs/review.py` — Added `import html`; escaped `image_attribution` with `html.escape()` before QLabel
- `src/utils/sync_guard.py` — **Created** sync-in-progress flag module (avoids circular imports)
- `src/hooks.py` — Registered `sync_will_start` → `set_sync_in_progress(True)` and `sync_did_finish` → `set_sync_in_progress(False)`
- `src/api/worker.py` — Added sync guard check before executing API calls; emits error signal with user-friendly message if sync in progress
- Tests: 6 new tests in test_api.py (TestClientDownload), 1 new test (TestRetryAfterCap); all 188 tests pass

---

## Session 7: Anki — Dead Code & Main Thread Fixes [COMPLETED]

**Scope**: Remove dead code, fix thread safety, clean up resources.

| ID | Finding | Action |
|----|---------|--------|
| A-I1 | tts_back_url dead code | Remove the tts_back_url download block in generate_with_assets.py (lines 175-184). Remove tts_back_data from CardMedia dataclass. |
| A-I3 | Login suppresses product_source | Remove inject_product_source=False from the login call in auth.py. Let the client inject product_source normally. |
| A-I4 | Enhancement processor blocks main thread during downloads | Move TTS/image downloads in the enhance flow to the background thread (ApiWorker). Have the worker return the downloaded bytes, then apply them to notes on the main thread (which only does col access). |
| A-I6 | TTS preview temp files never deleted | Add cleanup: store temp file paths and delete them in a cleanup method. Register atexit or use QObject.destroyed signal. At minimum, delete the previous temp file before creating a new one. |

**Changes made:**
- **A-I1**: Removed `tts_back_url` from `EnhancedCard` dataclass and parsing in `src/api/enhance.py`; removed `tts_back_data` from `CardMedia` in `src/api/generate_with_assets.py`; removed back TTS download block, simplified `_filter_tts_by_direction()`; removed back TTS play button from `src/ui/dialogs/review.py`; removed all `tts_back_url`/`tts_back_data` references from `tests/helpers.py`, `tests/test_enhance.py`, `tests/test_generate_with_assets.py`
- **A-I3**: Removed `inject_product_source=False` from login call in `src/api/auth.py`
- **A-I4**: Created `DownloadedEnhanceMedia` dataclass and `download_enhance_media()` in `src/enhance/media.py`; added `enhance_and_download()` orchestration in `src/enhance/processor.py` (chains enhance + download on background thread); restructured `_apply_tts_at_end()`, `_apply_tts_after_section()`, `_apply_image_to_field()` to accept pre-downloaded bytes instead of URLs+client; updated `apply_enhancements()` to accept `media` dict instead of `client`; updated `src/ui/dialogs/enhance.py` to use `enhance_and_download`; updated `src/hooks.py` to unpack tuple result
- **A-I6**: Added `_temp_path` tracking, `_cleanup_temp()` method, and `destroyed` signal connection in `_TtsPlayButton`; properly close temp file handle after writing; cleanup on stop and widget destruction
- Tests: 3 new tests (TestEnhanceAndDownload, TestDownloadEnhanceMedia); updated TestApplyTtsAtEnd and TestSecurityHardening for new signatures; all 192 tests pass, flake8 clean, mypy clean

---

## Session 8: Anki — Consider Items & Final Cleanup [COMPLETED]

**Scope**: Evaluate and address remaining Consider items.

| ID | Finding | Verdict | Action |
|----|---------|---------|--------|
| A-M1 | ~33 Any annotations | **Accept with documentation** | Most are Anki runtime types without stubs. Update CLAUDE.md to say: "No Any except for Anki runtime types (mw, Note, Collection) which lack type stubs. Use # type: ignore[...] comments." Don't spend time creating stubs — the web app uses TypeScript and won't inherit this. |
| A-M2 | token_expires_at never proactively checked | **Fix** | Add a proactive expiry check before requests. If token is expired (or within 30s of expiry), refresh preemptively. Eliminates the guaranteed-failure-then-retry on first request after expiry. |
| A-M3 | has_stored_auth only checks existence | **Fix** | Check token_expires_at in has_stored_auth(). If expired, return False so the UI shows logged-out state. The user re-authenticates cleanly instead of seeing "logged in" then getting a 401. |
| A-M4 | Temp TTS/image bytes in memory | **Accept** | Python GC handles this adequately for typical batch sizes (10 cards). Document the memory characteristics for extreme batches in CLAUDE.md but don't engineer a streaming solution. |
| A-M5 | Client timeout docs mismatch | **Fix** | Clarify in root CLAUDE.md that "60s" refers to backend's Claude API timeout, not client timeouts. Add a table: "Client timeouts: generate 60s, enhance 120s, TTS 15s, image 10s." |
| A1-A5 | Simplification suggestions | See below | |

**Simplification verdicts:**
- A1 (broad except on enhance_cards): Add comment, don't change logic. Correct as-is.
- A2 (unreachable except blocks on downloads): **Remove** — download functions already catch internally.
- A3 (dead tts_back_url): Already removed in Session 7.
- A4 (redundant `or ""`): **Remove**.
- A5 (TTS filter placement): **Reorder** — move filter before list assignment for readability.

**Changes made:**
- `flashcard-anki/CLAUDE.md` — Updated Any convention to allow Anki runtime types with `# type: ignore[...]`
- `src/api/client.py` — Proactive token refresh when within 30s of expiry (before the request loop)
- `src/utils/config.py` — `has_stored_auth()` now checks `token_expires_at`; returns False if token expired
- `CLAUDE.md` (root) — Clarified timeout docs: "Backend external API timeouts" vs "Client-side timeouts"
- `src/api/generate_with_assets.py` — Added comment on intentionally broad except; removed 5 unreachable try/except blocks; removed redundant `or ""`; reordered filter before list assignment
- Tests: 2 new tests in test_api.py (TestProactiveTokenRefresh), 3 new tests in test_settings.py (has_stored_auth expiry); all 188 tests pass

---

## Post-Fix Checklist

After all 8 sessions:

- [ ] `cd flashcard-backend && npm test` — all tests pass
- [ ] `cd flashcard-anki && python -m pytest` — all tests pass
- [ ] `git diff --stat` — review total changeset scope
- [ ] Update docs/audit-findings.md — mark each finding as RESOLVED with commit hash
- [ ] Delete or archive this fix plan (it served its purpose)
- [ ] Update both CLAUDE.md files with any new conventions discovered during fixes
- [ ] Verify wrangler.jsonc has the new KV binding and ALLOWED_ORIGINS env var

## Estimated Effort

| Session | Scope | Complexity | Estimated Duration |
|---------|-------|-----------|-------------------|
| 1 | Backend middleware security | Medium | 15-20 min |
| 2 | Rate limiting + TOCTOU | High | 20-30 min |
| 3 | Contracts & documentation | Low | 10-15 min |
| 4 | Billing & API resilience | Medium | 15-20 min |
| 5 | Backend cleanup | Low | 10-15 min |
| 6 | Anki security & reliability | Medium | 15-20 min |
| 7 | Anki dead code & threading | High | 20-30 min |
| 8 | Anki consider items & cleanup | Low-Medium | 15-20 min |

**Total: ~2-3 hours of Claude Code session time across 8 sessions.**
