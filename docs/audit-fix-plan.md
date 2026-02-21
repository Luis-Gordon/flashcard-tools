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

## Session 2: Backend Security — Rate Limiting & Usage Integrity

**Scope**: Durable rate limiting + usage race condition. Changes in `middleware/rateLimit.ts`, `services/usage.ts`, `routes/generate.ts`.

| ID | Finding | Action |
|----|---------|--------|
| B-C2 | Rate limiting in-memory only | Migrate to Cloudflare KV. Store bucket state keyed by `{userId}:{routePrefix}`. Set KV TTL to match window duration. Add KV binding to wrangler.jsonc. Keep in-memory fallback for dev (KV not available locally without `--remote`). |
| B-I2 | PRD rate limits not implemented (hourly/daily caps) | Implement tiered rate limits per PRD: generation 100/hour, all operations 500/day. Store counters in KV with hourly/daily TTLs. Tier-aware: free tier gets lower caps. |
| B-I5 | TOCTOU race in usage checking | Use Supabase RPC or atomic increment. Check-and-increment in a single database operation. If Supabase doesn't support this natively, use a transaction or advisory lock. Document the chosen approach. |

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections B-C2, B-I2, B-I5. Fix all three findings.

B-C2: Migrate rate limiting from in-memory Map to Cloudflare KV. Add a RATE_LIMIT_KV binding in wrangler.jsonc. Key pattern: ratelimit:{userId}:{handler}:{window}. Set KV TTL to match the rate limit window. Keep in-memory fallback when KV binding is unavailable (local dev).

B-I2: Add tiered hourly and daily rate limits per the PRD. Free: 20 gen/hour, 100 ops/day. Plus: 100 gen/hour, 500 ops/day. Pro: 200 gen/hour, 1000 ops/day. Store cumulative counters in KV with appropriate TTLs.

B-I5: Fix the TOCTOU race in usage checking. The check in canGenerateCards() and the record in recordUsage() must be atomic. Use a Supabase RPC function or transaction to check-and-increment in one operation. If that's not feasible, use optimistic locking with a version column.

Run all tests after.
```

---

## Session 3: Backend Contracts — Types, Errors, Documentation

**Scope**: Contract alignment between PRD, types, and documentation. Low-risk, high-value for web app.

| ID | Finding | Action |
|----|---------|--------|
| X-1 | Tier naming mismatch (PRD: pro/power, code: plus/pro) | Update PRD.md tier table to match code: free/plus/pro. Add a note about the rename. |
| B-I1 | Claude timeout docs say 30s, code is 60s | Update both CLAUDE.md files to say 60s. |
| B-I3 | Missing CONFLICT in ErrorCode union | Add `CONFLICT` to the ErrorCode type. Add 409 case to `httpStatusToErrorCode`. Verify auth.ts uses the typed ErrorCode, not string literals. |
| B-I6 | Webhook handlers leak internal error details | Sanitize Supabase error messages in billing.ts webhook handlers. Log full errors server-side, return generic messages. Ensure handleInvoicePaymentFailed doesn't log full Stripe metadata objects. |
| B-M6 | Usage route returns 503 instead of 500 | Change to 500 + INTERNAL_ERROR for consistency with the error contract. |

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections X-1, B-I1, B-I3, B-I6, B-M6. Fix all five findings.

X-1: Update PRD.md subscription tier table from pro/power to plus/pro to match the code. Add a note: "Tiers renamed from pro/power to plus/pro in commit 5093b3d."

B-I1: Update BOTH CLAUDE.md files (root and flashcard-backend/) to document Claude API timeout as 60s, not 30s.

B-I3: Add 'CONFLICT' to the ErrorCode union in types/index.ts. Add a 409 case in errorHandler.ts httpStatusToErrorCode mapping. Update auth.ts signup/login to use the typed ErrorCode instead of string literals.

B-I6: In services/billing.ts, sanitize all error logging in webhook handlers. Log the full error object at debug level. At error level, log only the event type, handler name, and a generic message. Never include raw Supabase or Stripe error messages in logs that could be exposed via log aggregation.

B-M6: In routes/usage.ts, change the catch block from 503 to 500 with INTERNAL_ERROR code for consistency.

Run all tests after.
```

---

## Session 4: Backend Reliability — Billing & External APIs

**Scope**: Billing endpoint hardening + external API resilience.

| ID | Finding | Action |
|----|---------|--------|
| B-M2 | Stripe SDK no timeout (default 80s > Worker 30s CPU) | Add `timeout: 25_000` and `maxNetworkRetries: 1` to Stripe client config. |
| B-M4 | Portal return_url open redirect | Validate return_url against ALLOWED_ORIGINS (from Session 1). Reject URLs not matching allowed origins. Fall back to `/` for invalid values. |
| B-M5 | Checkout success_url/cancel_url not origin-validated | Same origin validation as B-M4. Apply to both success_url and cancel_url in checkout schema. |
| B-M1 | Claude 529 not distinguished from generic 5xx | Add specific handling for 529: exponential backoff (2s base) instead of immediate retry. Keep immediate retry for other 5xx. |
| B-M3 | recordUsage fire-and-forget, silent data loss | Add structured warning log when recordUsage fails, including userId, operation type, and timestamp. This enables alerting on usage tracking degradation without blocking requests. |

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections B-M2, B-M4, B-M5, B-M1, B-M3. Fix all five findings.

B-M2: In services/stripe.ts createStripeClient(), add timeout: 25000 and maxNetworkRetries: 1 to the Stripe constructor options.

B-M4: In routes/billing.ts portal endpoint, validate return_url against the ALLOWED_ORIGINS env var (added in Session 1). Reject any URL whose origin doesn't match the allowlist. Fall back to '/' for invalid values.

B-M5: In routes/billing.ts checkout endpoint, validate success_url and cancel_url against ALLOWED_ORIGINS. Update the Zod schema to use .refine() or add validation after parsing. Reject non-matching origins with a clear error.

B-M1: In services/claude.ts retry logic, detect status 529 specifically. For 529: use exponential backoff (wait 2s before retry). For other 5xx: keep the existing immediate retry.

B-M3: In services/usage.ts recordUsage(), upgrade the error logging from console.error to a structured warning that includes: userId, operation type (generate/enhance), and ISO timestamp. This enables monitoring alerts without blocking the request.

Run all tests after.
```

---

## Session 5: Backend — Remaining Consider Items + Simplification

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

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections B-M7, B-M8, and the Simplification Appendix (S1, S3, G1, G2).

B-M7: Expand the /auth/me endpoint response to include subscription_tier, subscription_status, and a usage summary (cards_used, cards_limit for current period). Query the user's subscription and current usage from Supabase. Keep the existing email and id fields.

B-M8: In services/usage.ts parseSubscriptionTier(), add a console.warn() when the raw value doesn't match any known tier before defaulting to 'free'. Include the raw value in the warning.

S1: In services/stripe.ts, remove the "Replace with real meter event_name" comment from METER_EVENT_NAME if memogenesis_overage is the production value.

S3: In services/stripe.ts, add a comment above getPriceIdForTier: "Abstraction point for tier-to-price mapping — keep as named function."

G1: In routes/generate.ts, remove the local DomainConfig interface and import GenerationPromptConfig from lib/prompts/generation/index.ts instead.

G2: In routes/generate.ts, remove the two no-op `as unknown[]` casts (lines ~295 and ~319).

Run all tests after.
```

---

## Session 6: Anki — Security & Reliability

**Scope**: Client-side security fixes and reliability improvements.

| ID | Finding | Action |
|----|---------|--------|
| A-I2 | TTS download bypasses client.request() | Route TTS downloads through client.request() so they get 401-refresh and 429-retry logic. Update download_tts() in media.py to use the standard client path. |
| A-I5 | No retry_after cap on 429 | Cap retry_after at 60 seconds in client.py. Log a warning if server sends > 60s. |
| A-I7 | image_attribution unescaped in QLabel (Qt XSS) | Apply html.escape() to image_attribution before passing to QLabel in review.py. Match the pattern already used in enhance/processor.py:266 and generate/processor.py:217. |
| A-I8 | No sync guard — API calls can conflict with Anki sync | Register hooks on sync_will_start and collection_will_temporarily_close in hooks.py. Set a flag that ApiWorker checks before starting. If sync is in progress, queue the operation or show a warning. |

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections A-I2, A-I5, A-I7, A-I8. Fix all four findings in the Anki add-on.

A-I2: In enhance/media.py download_tts(), replace the direct client._session.get() call with client.request(). This ensures TTS downloads get automatic 401 token refresh and 429 retry handling. Match the function signature to work with the client's request method.

A-I5: In api/client.py, cap the retry_after value from 429 responses at 60 seconds maximum. If the server sends a higher value, use 60s and log a warning.

A-I7: In ui/dialogs/review.py, apply html.escape() to image_attribution before passing it to QLabel. Import html at the top of the file. Match the existing pattern in enhance/processor.py:266.

A-I8: In hooks.py, register hooks on gui_hooks.sync_will_start and gui_hooks.sync_did_finish (or collection_will_temporarily_close / collection_did_load). Set a module-level flag _sync_in_progress. Have ApiWorker check this flag before starting work. If sync is active, show an info message to the user: "Please wait until sync completes."

Run all tests after.
```

---

## Session 7: Anki — Dead Code & Main Thread Fixes

**Scope**: Remove dead code, fix thread safety, clean up resources.

| ID | Finding | Action |
|----|---------|--------|
| A-I1 | tts_back_url dead code | Remove the tts_back_url download block in generate_with_assets.py (lines 175-184). Remove tts_back_data from CardMedia dataclass. |
| A-I3 | Login suppresses product_source | Remove inject_product_source=False from the login call in auth.py. Let the client inject product_source normally. |
| A-I4 | Enhancement processor blocks main thread during downloads | Move TTS/image downloads in the enhance flow to the background thread (ApiWorker). Have the worker return the downloaded bytes, then apply them to notes on the main thread (which only does col access). |
| A-I6 | TTS preview temp files never deleted | Add cleanup: store temp file paths and delete them in a cleanup method. Register atexit or use QObject.destroyed signal. At minimum, delete the previous temp file before creating a new one. |

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections A-I1, A-I3, A-I4, A-I6. Fix all four findings in the Anki add-on.

A-I1: Remove the dead tts_back_url code path in api/generate_with_assets.py (lines 175-184). Remove tts_back_data field from the CardMedia dataclass. Remove any references to tts_back_data elsewhere.

A-I3: In api/auth.py login(), remove inject_product_source=False. Let the standard client injection add product_source: 'anki_addon' to login requests.

A-I4: In enhance/processor.py, move TTS and image downloads off the main thread. The download_tts() and download_image() calls should happen in the ApiWorker background thread. The main thread callback should only handle mw.col operations (which require main thread access). This may require restructuring the enhance flow to download in the worker and pass results to the main thread callback.

A-I6: In ui/dialogs/review.py _TtsPlayButton._play(), track the current temp file path as an instance variable. Delete the previous temp file before creating a new one. Also register a cleanup in the button's destroyed signal or parent dialog's closeEvent to delete the last temp file.

Run all tests after.
```

---

## Session 8: Anki — Consider Items & Final Cleanup

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

**Prompt for Claude Code:**
```
Read docs/audit-findings.md sections A-M1 through A-M5 and the Anki Simplification Appendix (A1-A5). Apply the following changes:

A-M1: Update flashcard-anki/CLAUDE.md code conventions to say: "No Any except for Anki runtime types (mw, Note, Collection, Editor) which lack type stubs. Add '# type: ignore[no-any]' comments on these lines."

A-M2: In api/client.py, before making any request, check if the token is expired or within 30 seconds of expiry (using token_expires_at from config). If so, call _try_refresh() preemptively before the request.

A-M3: In utils/config.py has_stored_auth(), also check token_expires_at. If the token is expired, return False. Import time for the comparison.

A-M5: Update root CLAUDE.md to clarify timeout documentation. Add: "Backend Claude API timeout: 60s. Client timeouts: generate 60s, enhance 120s, TTS 15s, image 10s."

A1: In api/generate_with_assets.py, add a comment at the broad except on enhance_cards: "# Intentionally broad — asset failure must never lose generated cards"

A2: Remove the four unreachable try/except blocks around download_tts() and download_image() calls in generate_with_assets.py. Replace with direct calls.

A4: Remove the redundant `or ""` in generate_with_assets.py line ~210 (inside an already-truthy if block).

A5: In generate_with_assets.py, move the _filter_tts_by_direction() call before the media_list[idx] assignment.

Run all tests after.
```

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
