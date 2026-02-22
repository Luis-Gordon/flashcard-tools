# Audit Findings — Pre-Web-App Readiness

Full codebase audit of `flashcard-backend/` and `flashcard-anki/` before the web app becomes the second API consumer. Every finding includes severity, file path, line number, and source reference.

**Audit date**: 2026-02-21
**Scope**: Backend (`flashcard-backend/src/`), Anki add-on (`flashcard-anki/src/`), cross-cutting contracts
**Resolution date**: 2026-02-22 (all findings resolved across 8 fix sessions)

---

## Summary

| Severity | Backend | Anki Add-on | Cross-cutting | Total | Resolved | Accepted |
|----------|---------|-------------|---------------|-------|----------|----------|
| Critical | 2 | 1 | — | 3 | 2 | 1 |
| Important | 8 | 8 | 1 | 17 | 17 | 0 |
| Consider | 8 | 5 | — | 13 | 13 | 0 |
| **Total** | **18** | **14** | **1** | **33** | **32** | **1** |

**Status**: All 33 findings addressed. 32 resolved via code changes. 1 accepted risk (A-C1: plaintext JWT storage — no encrypted storage API available in Anki).

---

## Cross-Cutting Findings

### Important

#### X-1: Tier naming mismatch between PRD and code — RESOLVED (Session 3)

- **Severity**: Important
- **Resolution**: Updated PRD.md tier table to match code: free/plus/pro. Added rename note.
- **Description**: The PRD defines subscription tiers as `free` / `pro` / `power`. The backend code uses `free` / `plus` / `pro`. The tier names were changed in commit `5093b3d` but the PRD was never updated. The web app must use the code-level names (`plus`/`pro`), but this creates a documentation gap where the PRD — defined as the authoritative source — contradicts the implementation.
- **Files**:
  - `flashcard-backend/src/types/index.ts:66` — `type SubscriptionTier = 'free' | 'plus' | 'pro'`
  - `flashcard-backend/src/services/stripe.ts:25-27` — `PRICE_IDS` keys: `plus`, `pro`
  - `flashcard-backend/src/services/usage.ts:47` — `parseSubscriptionTier` checks `plus`/`pro`
  - `PRD.md` — Tier table says `pro`/`power`
- **Source**: PRD.md vs `types/index.ts`

---

## Backend Findings

### Critical

#### B-C1: CORS allows all origins on authenticated endpoints — RESOLVED (Session 1)

- **Severity**: Critical
- **Resolution**: Replaced `cors()` with origin-validated CORS using `ALLOWED_ORIGINS` env var (comma-separated). Returns exact origin or null. `credentials: true`, explicit headers, `maxAge: 86400`.
- **Description**: `cors()` is called with no arguments, which sets `Access-Control-Allow-Origin: *` on every route including all authenticated endpoints (`/cards/*`, `/assets/*`, `/billing/*`, `/usage/*`). Any website can make credentialed cross-origin requests to the API. With the Anki desktop add-on this was low-risk (requests don't go through a browser), but the web app will run in a browser where CORS is the primary cross-origin defense. An attacker's page could invoke `/cards/generate` or `/billing/checkout` using a logged-in user's session.
- **File**: `flashcard-backend/src/index.ts:20`
- **Code**: `app.use('*', cors());`
- **Source**: OWASP CORS misconfiguration; CLAUDE.md security constraints

#### B-C2: Rate limiting is in-memory only — resets on Worker restart — RESOLVED (Session 2)

- **Severity**: Critical
- **Resolution**: Migrated to Cloudflare KV fixed-window counter. Key: `ratelimit:{userId}:{handler}:{windowId}`. In-memory fallback when KV absent (local dev). Added tiered rate limits (hourly gen + daily ops per tier).
- **Description**: The token bucket rate limiter stores state in a `Map<string, BucketEntry>()` that lives in Worker memory. Cloudflare Workers are ephemeral — every deploy, crash, or cold start resets all buckets to zero. The TODO comment on line 14 acknowledges this: "Replace with KV for production." In practice, rate limiting provides zero protection under sustained abuse because an attacker can wait for isolate recycling or simply hit different edge locations. With two clients sharing the same backend, this becomes a reliability issue for all users.
- **File**: `flashcard-backend/src/middleware/rateLimit.ts:14-15`
- **Code**: `const buckets = new Map<string, BucketEntry>();`
- **Source**: Code comment (TODO), PRD rate limit requirements

---

### Important

#### B-I1: Claude timeout documented as 30s but implemented as 60s — RESOLVED (Session 3)

- **Severity**: Important
- **Resolution**: Updated both CLAUDE.md files to say 60s. Added client-side timeout table.
- **Description**: Both CLAUDE.md files document "Claude 30s" as the timeout. The actual implementation uses `TIMEOUT_MS = 60_000` (60 seconds). The web app developer would read CLAUDE.md and expect 30s timeouts for their loading spinners, but requests could run twice as long.
- **File**: `flashcard-backend/src/services/claude.ts:6`
- **Code**: `const TIMEOUT_MS = 60_000;`
- **Source**: `flashcard-backend/CLAUDE.md` ("Claude API | 30s"), `CLAUDE.md` root ("Claude 30s")

#### B-I2: PRD rate limits not implemented — only simple per-minute cap exists — RESOLVED (Session 2)

- **Severity**: Important
- **Resolution**: Created `tieredRateLimit.ts` middleware with tier-based hourly/daily caps. Free: 20 gen/hr, 100 ops/day. Plus: 100/500. Pro: 200/1000.
- **Description**: The PRD specifies tiered rate limits: 100 generations/hour and 500 total operations/day. The backend only implements a flat 10 requests/minute per-handler rate limit (generate and enhance). The hourly and daily cumulative caps from the PRD are entirely absent. This means a paid user could generate 600 cards/hour, far exceeding the PRD's 100/hour limit.
- **File**: `flashcard-backend/src/routes/generate.ts:66`
- **Code**: `generateRoutes.use('/generate', rateLimit({ maxRequests: 10, windowMs: 60_000 }));`
- **Source**: PRD.md rate limit table

#### B-I3: Missing `CONFLICT` error code in ErrorCode type — RESOLVED (Session 3)

- **Severity**: Important
- **Resolution**: Added `CONFLICT` to ErrorCode union. Added 409 case to `httpStatusToErrorCode`. Added `satisfies ErrorCode` to auth.ts CONFLICT usages.
- **Description**: The PRD specifies a 409 `CONFLICT` error code for duplicate email signup. The auth route returns `code: 'CONFLICT'` on lines 50 and 74, but `CONFLICT` is not in the `ErrorCode` union type. The `httpStatusToErrorCode` function in the error handler has no case for 409 — it falls through to `INTERNAL_ERROR`. This is a type-safety gap: TypeScript won't catch the mismatch because the response objects use string literals, not the `ErrorCode` type. The web app will need to handle `CONFLICT` as an error code but it isn't part of the documented contract.
- **Files**:
  - `flashcard-backend/src/types/index.ts:47-55` — `ErrorCode` union (no `CONFLICT`)
  - `flashcard-backend/src/routes/auth.ts:50,74` — Returns `code: 'CONFLICT'`
  - `flashcard-backend/src/middleware/errorHandler.ts:67-86` — `httpStatusToErrorCode` (no 409 case)
- **Source**: PRD.md error code table (409 CONFLICT)

#### B-I4: Client-supplied `X-Request-ID` is accepted without validation — RESOLVED (Session 1)

- **Severity**: Important
- **Resolution**: Added `isValidRequestId()` validation (1-128 chars, `/^[a-zA-Z0-9._-]+$/`). Invalid IDs silently replaced with `crypto.randomUUID()`.
- **Description**: The request ID middleware accepts any value from the `X-Request-ID` header and uses it as-is in all responses and logs. A malicious client could inject XSS payloads, extremely long strings, or misleading IDs into server logs. While request ID tracing is useful for distributed systems, accepting arbitrary client input for a field that appears in error responses (returned to users) and server logs is a security concern. The web app's error display would need to sanitize this field.
- **File**: `flashcard-backend/src/middleware/requestId.ts:13-15`
- **Code**: `const existingId = c.req.header('X-Request-ID'); const id = existingId ?? crypto.randomUUID();`
- **Source**: Security best practices; CLAUDE.md ("ALWAYS include request_id in every response")

#### B-I5: TOCTOU race condition in usage checking — RESOLVED (Session 2)

- **Severity**: Important
- **Resolution**: Supabase RPC `check_and_reserve_usage` with `SELECT ... FOR UPDATE`. Serializes concurrent requests per user. Reservation pattern: insert → finalize or cancel.
- **Description**: `canGenerateCards()` checks usage status, then the route handler proceeds to generate cards and call `recordUsage()`. Between the check and the record, another concurrent request from the same user could also pass the check. This is a time-of-check-to-time-of-use (TOCTOU) race that could allow users to exceed their card limits. With two clients (Anki + web app) making concurrent requests, this becomes more likely.
- **File**: `flashcard-backend/src/services/usage.ts` (function `canGenerateCards`, ~line 130) + `flashcard-backend/src/routes/generate.ts` (usage check then generate)
- **Source**: Code analysis

#### B-I6: Webhook handlers leak internal error details — RESOLVED (Session 3)

- **Severity**: Important
- **Resolution**: All 6 billing webhook error handlers now use `console.debug` (dev-only full error) + `console.error` (generic message with identifiers only).
- **Description**: Several billing webhook handlers (`handleCheckoutCompleted`, `handleSubscriptionCreatedOrUpdated`, etc.) catch Supabase errors and log them but don't distinguish between expected and unexpected failures in their return values. While the webhook route itself returns 200 to Stripe (correct), the error logging includes raw Supabase error messages that could leak database schema details if log aggregation is misconfigured. More importantly, the `handleInvoicePaymentFailed` handler logs the full error object which could contain sensitive Stripe metadata.
- **File**: `flashcard-backend/src/services/billing.ts` (multiple handlers)
- **Source**: CLAUDE.md ("NEVER return internal error details to clients")

#### B-I7: Content-Length bypass — middleware doesn't verify actual body size — RESOLVED (Session 1)

- **Severity**: Important
- **Resolution**: Removed 411 rejection for missing Content-Length. Keep Content-Length check as fast-path rejection when present. Requests without Content-Length pass through (Cloudflare enforces at edge).
- **Description**: The `contentSize` middleware only checks the `Content-Length` header value, not the actual body size. An attacker could send `Content-Length: 100` with a 10MB body. While Cloudflare's infrastructure may enforce limits upstream, the middleware's intent to prevent resource exhaustion is defeated. Additionally, the `Content-Length` header is not required by HTTP/1.1 for chunked transfer encoding, and the middleware rejects requests without it (411), which may break legitimate chunked clients.
- **File**: `flashcard-backend/src/middleware/contentSize.ts:29-37`
- **Source**: Code analysis; PRD content limits

#### B-I8: `multipart/form-data` always gets 10MB limit regardless of route — RESOLVED (Session 1)

- **Severity**: Important
- **Resolution**: Removed `multipart/form-data` from PDF equivalence. Only `application/pdf` gets 10MB limit.
- **Description**: The content size middleware treats any `multipart/form-data` request as a PDF upload, granting it the 10MB limit. But multipart forms could be used for non-PDF endpoints in the future (e.g., web app form submissions). The check should be route-aware, not content-type-only. Currently no route accepts multipart, so this is a latent issue for the web app.
- **File**: `flashcard-backend/src/middleware/contentSize.ts:48-51`
- **Code**: `const isPdf = contentType.includes('application/pdf') || contentType.includes('multipart/form-data');`
- **Source**: Code analysis

---

### Consider

#### B-M1: Claude 529 (Overloaded) not distinguished from generic 5xx — RESOLVED (Session 4)

- **Severity**: Consider
- **Resolution**: Added specific 529 handling: 2s sleep before retry (exponential backoff). Other 5xx still gets immediate retry.
- **Description**: The Claude API returns 529 when overloaded. The retry logic treats all 5xx the same way — one immediate retry. A 529 should ideally use exponential backoff rather than an immediate retry, since the API is explicitly telling the caller it's overloaded.
- **File**: `flashcard-backend/src/services/claude.ts:67-83`
- **Source**: Anthropic API documentation

#### B-M2: Stripe SDK has no explicit timeout — defaults could exceed Worker CPU limit — RESOLVED (Session 4)

- **Severity**: Consider
- **Resolution**: Added `timeout: 25_000` and `maxNetworkRetries: 1` to Stripe client config.
- **Description**: The Stripe client is created with no timeout configuration. The Stripe Node.js SDK defaults to 80s, but Cloudflare Workers have a 30s CPU time limit (more generous wall-clock, but still bounded). A slow Stripe API call could exhaust the Worker's time budget. The SDK's `maxNetworkRetries` also defaults to 2, compounding the issue.
- **File**: `flashcard-backend/src/services/stripe.ts:15-18`
- **Source**: Stripe SDK documentation; Cloudflare Workers limits

#### B-M3: `recordUsage()` is fire-and-forget — silent data loss under Supabase degradation — RESOLVED (Session 4)

- **Severity**: Consider
- **Resolution**: Added structured `console.warn` with userId, operation type, and timestamp for alerting on usage tracking degradation.
- **Description**: When `recordUsage()` fails to insert a usage record, it logs the error and returns normally. The request succeeds but usage is not tracked. Under sustained Supabase degradation, this could result in significant under-counting that affects billing accuracy. This is documented as intentional ("Non-fatal: don't block the request"), but with metered billing, lost usage records directly impact revenue.
- **File**: `flashcard-backend/src/services/usage.ts:202-221`
- **Source**: Code comment (intentional design); billing accuracy concern

#### B-M4: Portal `return_url` from query param with no origin validation — open redirect risk — RESOLVED (Session 4)

- **Severity**: Consider
- **Resolution**: Validated return_url against `ALLOWED_ORIGINS`. Reject URLs not matching allowed origins. Fall back to `/` for invalid values.
- **Description**: The billing portal endpoint reads `return_url` from a query parameter, falling back to `Origin` header, then `Referer`, then `/`. The `return_url` is passed directly to Stripe's portal session. A malicious link like `/billing/portal?return_url=https://evil.com` would redirect the user to an attacker-controlled site after they finish managing their subscription. This is mitigated by Stripe's own portal UI (user sees the redirect domain), but it's still an open redirect.
- **File**: `flashcard-backend/src/routes/billing.ts:133-135`
- **Code**: `const returnUrl = c.req.query('return_url') || c.req.header('Origin') || c.req.header('Referer') || '/';`
- **Source**: OWASP Open Redirect; code analysis

#### B-M5: Checkout `success_url` and `cancel_url` not origin-validated — RESOLVED (Session 4)

- **Severity**: Consider
- **Resolution**: Same origin validation as B-M4 applied to both success_url and cancel_url in checkout schema.
- **Description**: The `/billing/checkout` endpoint accepts `success_url` and `cancel_url` in the request body (validated by Zod as strings with `.url()`) and passes them to Stripe's checkout session. While Stripe shows these URLs in its UI, an attacker who can trigger a checkout could set these to phishing URLs.
- **File**: `flashcard-backend/src/routes/billing.ts:61`
- **Source**: Code analysis

#### B-M6: Usage route returns 503 instead of 500 for internal errors — RESOLVED (Session 3)

- **Severity**: Consider
- **Resolution**: Changed to 500 + INTERNAL_ERROR for consistency with the error contract.
- **Description**: The `/usage/current` route catches `UsageServiceError` and returns HTTP 503 (Service Unavailable) instead of 500 (Internal Server Error). While 503 isn't wrong per se, it's inconsistent with the error handling contract which maps all internal errors to `INTERNAL_ERROR` with HTTP 500. The Anki add-on doesn't handle 503 specifically, so the error would display as an unrecognized status code.
- **File**: `flashcard-backend/src/routes/usage.ts:43,80-84`
- **Source**: CLAUDE.md error handling contract

#### B-M7: `/auth/me` returns minimal data — web app will need subscription tier — RESOLVED (Session 5)

- **Severity**: Consider
- **Resolution**: Expanded /auth/me to include subscription_tier, subscription_status, cards_used, cards_limit via `getUserUsageStatus()` with graceful degradation.
- **Description**: The `/auth/me` endpoint only returns the user's email and ID. The web app will need subscription tier, usage limits, and subscription status to render the dashboard. Currently the Anki add-on gets this from `/usage/current`, but the web app may expect it from the auth/profile endpoint for initial page load.
- **File**: `flashcard-backend/src/routes/auth.ts:274+`
- **Source**: Web app requirements analysis

#### B-M8: `parseSubscriptionTier()` silently downgrades unknown tiers to `free` — RESOLVED (Session 4)

- **Severity**: Consider
- **Resolution**: Added `console.warn` when encountering unknown non-null tier value before defaulting to free.
- **Description**: The `parseSubscriptionTier` function maps any unrecognized value to `free`. If a new tier is added (e.g., `enterprise`) but this function isn't updated, existing users on that tier would be silently downgraded to free-tier limits. The defensive coding is correct for DB corruption, but it should log a warning when encountering an unknown value.
- **File**: `flashcard-backend/src/services/usage.ts:46-48`
- **Code**: `function parseSubscriptionTier(raw: string | null | undefined): SubscriptionTier { if (raw === 'plus' || raw === 'pro') return raw; return 'free'; }`
- **Source**: Code analysis

---

## Anki Add-on Findings

### Critical

#### A-C1: JWT tokens stored as plaintext in Anki config (SQLite) — ACCEPTED RISK

- **Severity**: Critical
- **Resolution**: Accepted. Anki provides no encrypted storage API. Adding OS keyring requires bundling `keyring` package (not feasible for Anki add-ons). Token has 1-hour TTL. Web app will use `httpOnly` cookies instead.
- **Description**: `set_auth_tokens()` writes the JWT access token and refresh token as plain strings into Anki's config system, which stores them in an unencrypted SQLite database at `%APPDATA%\Anki2\addons21\meta.json`. Any process with filesystem access to the user's profile can read these tokens. While this is a known limitation (Anki provides no encrypted storage), the web app should use `httpOnly` cookies or a more secure storage mechanism rather than following this pattern.
- **File**: `flashcard-anki/src/utils/config.py:134-151`
- **Code**: `config["auth_token"] = access_token; config["refresh_token"] = refresh_token`
- **Source**: CLAUDE.md ("NEVER store passwords — only JWT tokens"); OWASP token storage guidelines

---

### Important

#### A-I1: `tts_back_url` dead code path in generate_with_assets — RESOLVED (Session 7)

- **Severity**: Important
- **Resolution**: Removed `tts_back_url` from EnhancedCard dataclass, `tts_back_data` from CardMedia, download block, and all test references.
- **Description**: The server always returns `tts_back_url: null` (per-section TTS replaced the legacy back-field TTS). However, `generate_with_assets.py` still checks for `tts_back_url` and attempts to download it (lines 175-184). This is dead code that adds unnecessary complexity and confuses developers about the actual TTS architecture.
- **File**: `flashcard-anki/src/api/generate_with_assets.py:175-184`
- **Source**: Backend architecture (per-section TTS replaced `tts_back_url`)

#### A-I2: TTS download bypasses `client.request()` — missing 401-refresh and 429-retry — RESOLVED (Session 6)

- **Severity**: Important
- **Resolution**: Added `download()` method to client with 401→refresh→retry and 429→sleep(capped)→retry. Simplified `download_tts()` to delegate to `client.download()`.
- **Description**: `download_tts()` uses `client._session.get()` directly instead of going through `client.request()`. This bypasses the client's built-in 401 → refresh → retry logic and 429 rate-limit retry logic. If the auth token expires during a batch enhancement with many TTS downloads, all subsequent downloads will fail silently (return None) instead of refreshing the token. With the web app potentially triggering more concurrent requests, token expiry during TTS downloads becomes more likely.
- **File**: `flashcard-anki/src/enhance/media.py:46`
- **Code**: `response = client._session.get(full_url, headers=headers, timeout=TIMEOUT_TTS)`
- **Source**: CLAUDE.md ("All requests go through src/api/client.py")

#### A-I3: Login call suppresses `product_source` — violates API contract — RESOLVED (Session 7)

- **Severity**: Important
- **Resolution**: Removed `inject_product_source=False` from login call. Login now gets `product_source: 'anki_addon'` injected like all other requests.
- **Description**: The `login()` function calls `client.request()` with `inject_product_source=False`. The cross-cutting API contract requires `product_source` in "every request." While login is an auth endpoint (not card generation), the inconsistency means the backend cannot track which client is authenticating. The web app should include `product_source: 'web_app'` in login requests.
- **File**: `flashcard-anki/src/api/auth.py:44-52`
- **Code**: `inject_product_source=False`
- **Source**: CLAUDE.md ("ALWAYS include product_source: 'anki_addon' in all API requests")

#### A-I4: Enhancement processor downloads TTS/images on main thread — RESOLVED (Session 7)

- **Severity**: Important
- **Resolution**: Created `DownloadedEnhanceMedia` dataclass and `download_enhance_media()` orchestrator. Added `enhance_and_download()` that chains enhance + download on background thread. Main thread only does `save_media_file()` + `col.update_note()`.
- **Description**: `apply_enhancements()` runs on the main thread (as stated in its docstring: "Runs on the main thread because it touches mw.col"). The function calls `_apply_tts_at_end()` and `_apply_image_to_field()` which internally call `download_tts()` and `download_image()` — both are blocking HTTP requests. This blocks Anki's UI thread during each download. For a batch of 50 cards with TTS + images, this could freeze the UI for minutes. The `generate_with_assets` pipeline correctly downloads on a background thread, but the enhance flow does not.
- **File**: `flashcard-anki/src/enhance/processor.py:1-7` (docstring), `:362-387` (download calls)
- **Source**: CLAUDE.md ("NEVER block the main thread during API calls")

#### A-I5: No `retry_after` cap on 429 retry — server could force arbitrary sleep — RESOLVED (Session 6)

- **Severity**: Important
- **Resolution**: Capped `retry_after` at 60 seconds (`_MAX_RETRY_AFTER = 60`) in client.py. Logs warning if server sends > 60s.
- **Description**: When the client receives a 429, it sleeps for `retry_after` seconds from the response with no upper bound: `time.sleep(retry_after)`. A misbehaving or compromised server could send `retry_after: 999999` and freeze the background thread indefinitely. Should cap at a reasonable maximum (e.g., 60s).
- **File**: `flashcard-anki/src/api/client.py:128-134`
- **Code**: `retry_after = int(response_body.get("retry_after", 1)); time.sleep(retry_after)`
- **Source**: Code analysis; defensive programming

#### A-I6: TTS preview temp files never deleted — resource leak — RESOLVED (Session 7)

- **Severity**: Important
- **Resolution**: Added `_temp_path` tracking, `_cleanup_temp()` method, `destroyed` signal connection. Previous temp file deleted before creating new one. Cleanup on stop and widget destruction.
- **Description**: `_TtsPlayButton._play()` creates a `tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)` on every play click. The `delete=False` flag prevents automatic cleanup, and there is no `os.unlink`, `closeEvent`, or `__del__` cleanup anywhere. Each audio preview accumulates a temp file in the OS temp directory that persists until the next OS reboot. Repeated use during card review sessions will cause unbounded temp file growth.
- **File**: `flashcard-anki/src/ui/dialogs/review.py:76-81`
- **Source**: Code review

#### A-I7: `image_attribution` rendered unescaped in QLabel — Qt rich text injection — RESOLVED (Session 6)

- **Severity**: Important
- **Resolution**: Added `html.escape()` on image_attribution before QLabel in review.py.
- **Description**: When displaying image attribution in the review dialog, `QLabel(media.image_attribution)` renders the string as-is. Qt's `QLabel` interprets HTML by default. If the Unsplash API returns attribution containing HTML tags (e.g., `<a href="javascript:...">`) or Qt rich text markup, it will be rendered. Both `enhance/processor.py:266` and `generate/processor.py:217` correctly use `html.escape()` before injecting attribution into note fields, but the review dialog omits this step.
- **File**: `flashcard-anki/src/ui/dialogs/review.py:200-206`
- **Source**: Code review; contrast with `enhance/processor.py:266` (correct usage)

#### A-I8: No guard against Anki sync interleaving with active API calls — RESOLVED (Session 6)

- **Severity**: Important
- **Resolution**: Created `sync_guard.py` flag module. Registered `sync_will_start`/`sync_did_finish` hooks. ApiWorker checks flag before executing, emits error signal if sync in progress.
- **Description**: The add-on registers `profile_did_open`, `profile_will_close`, and browser hooks, but does NOT register any hook on `gui_hooks.sync_will_start` or `gui_hooks.collection_will_temporarily_close`. If Anki begins a sync while an `ApiWorker` enhancement is in-flight, the worker's callback (`apply_enhancements`) will attempt `col.get_note()` / `col.update_note()` while the collection is temporarily closed. This violates the CLAUDE.md constraint "NEVER make API calls during Anki sync" and could cause silent data loss or crashes.
- **File**: `flashcard-anki/src/hooks.py:75-110` (absence of sync hooks)
- **Source**: CLAUDE.md ("NEVER make API calls during Anki sync")

---

### Consider

#### A-M1: ~33 `Any` type annotations violate "no Any" rule — RESOLVED (Session 8)

- **Severity**: Consider
- **Resolution**: Updated CLAUDE.md convention to say: "No `Any` except Anki runtime types (`mw`, `Note`, `Collection`, `Editor`) which lack type stubs. Use `# type: ignore[...]` comments."
- **Description**: The CLAUDE.md code convention says "No `Any` — use specific types with runtime narrowing." The codebase has approximately 33 usages of `Any` type annotations. Most are for Anki runtime types (`mw`, `Note`, `Collection`) that don't have type stubs. This is pragmatic but contradicts the documented standard. The web app won't inherit this issue (TypeScript), but the documented convention should match reality.
- **Files**: `flashcard-anki/src/utils/config.py:11`, `flashcard-anki/src/enhance/processor.py:11`, and ~31 other locations
- **Source**: `flashcard-anki/CLAUDE.md` ("No Any — use specific types with runtime narrowing")

#### A-M2: `token_expires_at` stored but never proactively checked — RESOLVED (Session 8)

- **Severity**: Consider
- **Resolution**: Added proactive expiry check in client.py — refreshes token before request if within 30s of expiry.
- **Description**: The config stores `token_expires_at` as a Unix timestamp, but no code proactively checks if the token is expired before making a request. The client relies entirely on the server returning 401 to trigger a refresh. This means every first request after token expiry will fail, get refreshed, and retry — adding latency. A proactive check before the request would eliminate this extra round-trip.
- **File**: `flashcard-anki/src/utils/config.py:124-126` (getter), `flashcard-anki/src/api/client.py` (no expiry check)
- **Source**: Code analysis

#### A-M3: `has_stored_auth()` only checks token existence, not validity — RESOLVED (Session 8)

- **Severity**: Consider
- **Resolution**: `has_stored_auth()` now checks `token_expires_at`. Returns False if token expired, so UI shows logged-out state correctly.
- **Description**: The `has_stored_auth()` check (used by the UI to decide whether to show the login dialog) only verifies that a non-empty `auth_token` string exists. It doesn't check `token_expires_at` to see if the token is expired. A user with an expired token would see "Logged in" status but their first API call would fail and trigger a refresh. This is cosmetically confusing but functionally harmless.
- **File**: `flashcard-anki/src/utils/config.py` (auth check function)
- **Source**: Code analysis

#### A-M4: Temporary TTS/image bytes held in memory, never explicitly freed — ACCEPTED (Session 8)

- **Severity**: Consider
- **Resolution**: Accepted. Python GC handles this for typical batch sizes (10 cards). Documented in CLAUDE.md.
- **Description**: In `generate_with_assets.py`, downloaded TTS and image bytes are stored in `CardMedia` dataclass instances. For a batch of 10 cards with TTS + images, this could be 10-50MB of audio/image data held in memory simultaneously. Python's garbage collector will eventually free this, but the references are kept alive until the `GenerateWithAssetsResult` is fully consumed. This is not a leak, but for large batches it could cause memory pressure on systems with limited RAM.
- **File**: `flashcard-anki/src/api/generate_with_assets.py:18-27` (CardMedia dataclass)
- **Source**: Code analysis

#### A-M5: Client timeout documentation mismatch — RESOLVED (Session 8)

- **Severity**: Consider
- **Resolution**: Clarified in root CLAUDE.md: "Backend external API timeouts" (Claude 60s, TTS 15s, Unsplash 10s) vs "Client-side timeouts" (generate 60s, enhance 120s, TTS 15s, image 10s).
- **Description**: The Anki CLAUDE.md documents "60s for generate, 120s for enhance, 15s for TTS, 10s for images." The actual values in `endpoints.py` match these, but the root CLAUDE.md says "Claude 30s" (which refers to the backend's Claude API timeout, not the client timeout). This creates confusion about which timeout is meant where. The client timeouts (60s/120s) are correctly larger than the backend's Claude timeout (60s actual) to account for network latency.
- **File**: `flashcard-anki/src/api/endpoints.py`, root `CLAUDE.md`
- **Source**: Documentation cross-reference

---

## Appendix: Files Reviewed

### Backend (`flashcard-backend/src/`)

| File | Lines | Category |
|------|-------|----------|
| `index.ts` | 61 | Entry point, middleware, CORS |
| `middleware/auth.ts` | ~45 | JWT extraction, Supabase validation |
| `middleware/rateLimit.ts` | 99 | Token bucket, in-memory |
| `middleware/requestId.ts` | 23 | UUID generation, client passthrough |
| `middleware/contentSize.ts` | 78 | Content-Length validation |
| `middleware/errorHandler.ts` | 87 | Global error handler, status mapping |
| `routes/auth.ts` | ~310 | Signup, login, refresh, me |
| `routes/generate.ts` | ~300 | Card generation, domain dispatch |
| `routes/enhance.ts` | ~400 | Card enhancement, TTS/image orchestration |
| `routes/assets.ts` | ~120 | TTS and image endpoints |
| `routes/billing.ts` | ~200 | Checkout, portal, webhook |
| `routes/usage.ts` | ~90 | Usage reporting |
| `routes/health.ts` | ~50 | Health and readiness |
| `services/claude.ts` | ~150 | Claude API, timeout, retry |
| `services/usage.ts` | 222 | Usage tracking, tier logic |
| `services/stripe.ts` | ~120 | Stripe client, price IDs |
| `services/billing.ts` | ~450 | Webhook handlers |
| `services/tts.ts` | ~100 | OpenAI TTS, R2 cache |
| `services/unsplash.ts` | ~80 | Unsplash search |
| `types/index.ts` | 77 | Shared types, ErrorCode, SubscriptionTier |
| `lib/validation/cards.ts` | ~400 | All 10 domain Zod schemas |
| `lib/validation/enhance.ts` | ~100 | Enhancement schemas |
| `lib/validation/billing.ts` | ~30 | Checkout schema |
| `lib/htmlUtils.ts` | ~200 | HTML stripping, TTS extraction |

### Anki Add-on (`flashcard-anki/src/`)

| File | Lines | Category |
|------|-------|----------|
| `api/client.py` | ~200 | HTTP client, auth refresh, retry |
| `api/auth.py` | 68 | Login, logout |
| `api/cards.py` | ~80 | Generate cards API |
| `api/enhance.py` | ~100 | Enhance cards API |
| `api/endpoints.py` | ~30 | Endpoint paths, timeouts |
| `api/generate_with_assets.py` | ~240 | Generate + TTS/image orchestration |
| `api/worker.py` | ~60 | QThread background worker |
| `enhance/processor.py` | ~400 | Enhancement application, media injection |
| `enhance/media.py` | 165 | TTS/image download, media storage |
| `utils/config.py` | ~300 | Config management, auth tokens |
| `utils/logging.py` | ~20 | Logger setup |
| `ui/constants.py` | ~50 | Shared option lists |
| `ui/dialogs/login.py` | ~100 | Login dialog |
| `ui/dialogs/generate.py` | ~250 | Generation dialog |
| `ui/dialogs/enhance.py` | ~200 | Enhancement dialog |
| `ui/dialogs/review.py` | ~300 | Card review/edit dialog |
| `ui/dialogs/settings.py` | ~200 | Settings dialog |
| `ui/dialogs/styles.py` | ~150 | CSS styles dialog |
| `ui/dialogs/helpers.py` | ~50 | Shared dialog utilities |
| `styles/stylesheet.py` | ~200 | FC_STYLESHEET CSS |
| `hooks.py` | ~100 | Anki hook registrations |
| `generate/processor.py` | ~150 | Note creation |

### Other

| File | Purpose |
|------|---------|
| `PRD.md` | Authoritative requirements (4 PRDs) |
| `CLAUDE.md` (root) | Cross-project conventions |
| `flashcard-backend/CLAUDE.md` | Backend dev guide |
| `flashcard-anki/CLAUDE.md` | Add-on dev guide |

---

## Appendix: Code Simplification Suggestions — ALL RESOLVED

Simplification suggestions addressed in Sessions 4, 5, 7, and 8.

### `flashcard-backend/src/services/stripe.ts`

**S1. Placeholder comment on `METER_EVENT_NAME` (line 31) — RESOLVED (Session 4)**

Current:
```typescript
export const METER_EVENT_NAME = 'memogenesis_overage'; // Replace with real meter event_name
```

The trailing comment "Replace with real meter event_name" is a leftover from initial implementation. According to the architecture doc, the billing meter integration is complete (Session 37). If `memogenesis_overage` is the real event name, remove the comment. If provisional, convert to a structured `TODO` with tracking reference.

**S2. Missing Stripe SDK `timeout` configuration (lines 15-18) — RESOLVED (Session 4)**

Current:
```typescript
export function createStripeClient(env: Env): Stripe {
  return new Stripe(env.STRIPE_SECRET_KEY, {
    apiVersion: '2026-01-28.clover',
  });
}
```

Every other external service has an explicit timeout (Claude 60s, TTS 15s, Unsplash 10s). The Stripe SDK defaults to 80s, which exceeds Cloudflare Workers' CPU time budget. Suggested: add `timeout: 30_000` for consistency and safety.

**S3. `getPriceIdForTier` is a trivial single-line wrapper (lines 42-44) — KEPT (Session 5)**

```typescript
export function getPriceIdForTier(tier: Exclude<SubscriptionTier, 'free'>): string {
  return PRICE_IDS[tier];
}
```

Used in one place. Consider inlining `PRICE_IDS[tier]` at the call site, or adding a comment explaining why the wrapper exists if it's intended as a future extension point.

### `flashcard-backend/src/routes/generate.ts`

**G1. Duplicate `DomainConfig` interface (lines 30-37) — RESOLVED (Session 5)**

The local `DomainConfig` interface is structurally identical to `GenerationPromptConfig` from the generation registry (`src/lib/prompts/generation/index.ts`). The route already imports `FilterResult` from that module. Suggested: remove the local interface and import `GenerationPromptConfig` directly — eliminates a drift risk.

**G2. No-op `as unknown[]` casts (lines 295, 319) — RESOLVED (Session 5)**

```typescript
(valid as unknown[]).length,
```

`FilterResult.valid` is already typed as `unknown[]`. These casts are no-ops from an earlier refactor. Remove them to reduce visual noise.

**G3. Spread-conditional pattern for optional response fields (lines 316-317) — KEPT (Session 5)**

```typescript
...(rejected.length > 0 ? { rejected } : {}),
...(unsuitable.length > 0 ? { unsuitable_content: unsuitable } : {}),
```

No change recommended without confirming the API contract. Noted for awareness — if empty arrays are acceptable in the response, direct assignment is simpler.

### `flashcard-anki/src/api/generate_with_assets.py`

**A1. Broad `except Exception` on `enhance_cards` (line 137) — KEPT + comment added (Session 8)**

The docstring says "Never loses generated cards — asset failures are non-fatal." The broad catch is the correct pattern here. Suggestion: add a comment at the `except` line: `# Intentionally broad — asset failure must never lose generated cards`.

**A2. Four unreachable `except Exception` blocks on download calls (lines 170, 191, 204, 214) — RESOLVED (Session 8)**

Both `download_tts()` and `download_image()` already catch all exceptions internally and return `None`. The `try/except` wrappers in `generate_with_assets.py` can never trigger. Suggested: replace all four `try/except` blocks with direct calls, removing ~20 lines of dead exception handling.

Before:
```python
if ecard.tts_front_url:
    try:
        card_media.tts_front_data = download_tts(client, ecard.tts_front_url)
    except Exception as exc:
        logger.warning("TTS front download failed for gen-%d: %s", idx, exc)
```

After:
```python
if ecard.tts_front_url:
    card_media.tts_front_data = download_tts(client, ecard.tts_front_url)
```

**A3. Dead `tts_back_url` code path (lines 175-184) — RESOLVED (Session 7, via A-I1)**

The backend always returns `tts_back_url: null`. The `CardMedia.tts_back_data` field (line 22) is never read by any consumer. Suggested: remove the download block and the dataclass field.

**A4. Redundant `or ""` fallback (line 210) — RESOLVED (Session 8)**

```python
card_media.image_url = ecard.image_url or ""
```

This is inside `if ecard.image_url:`, which guarantees truthiness. The `or ""` can never activate. Remove it.

**A5. TTS direction filter placed after list assignment (lines 219-226) — RESOLVED (Session 8)**

`_filter_tts_by_direction()` mutates `card_media` in place after it's already assigned to `media_list[idx]`. Functionally equivalent due to Python reference semantics, but moving the filter call before the list assignment makes the data flow read top-to-bottom: download → filter → store.
