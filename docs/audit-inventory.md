# Codebase Inventory — Pre-Web-App Readiness

Factual enumeration of the codebase as of 2026-02-21. No judgments — see `audit-findings.md` for issues.

---

## 1. Route Handlers

15 endpoints across 6 route files, mounted in `flashcard-backend/src/index.ts`.

| # | Method | Path | Auth | Rate Limit | Zod Schema | Route File | Line |
|---|--------|------|------|------------|------------|------------|------|
| 1 | GET | `/health` | None | None | None | `routes/health.ts` | 16 |
| 2 | GET | `/health/ready` | None | None | None | `routes/health.ts` | 30 |
| 3 | POST | `/auth/signup` | None | None | `SignupRequestSchema` | `routes/auth.ts` | 21 |
| 4 | POST | `/auth/login` | None | None | `LoginRequestSchema` | `routes/auth.ts` | 128 |
| 5 | POST | `/auth/refresh` | None | None | `RefreshRequestSchema` | `routes/auth.ts` | 208 |
| 6 | GET | `/auth/me` | JWT (inline) | None | None | `routes/auth.ts` | 274 |
| 7 | POST | `/cards/generate` | JWT (global) | 10/min | `GenerateRequestSchema` | `routes/generate.ts` | 74 |
| 8 | POST | `/cards/enhance` | JWT (global) | 10/min | `EnhanceRequestSchema` | `routes/enhance.ts` | 82 |
| 9 | POST | `/assets/tts` | JWT (global) | 30/min | `TTSRequestSchema` | `routes/assets.ts` | 27 |
| 10 | GET | `/assets/tts/:cacheKey` | JWT (global) | None | Regex (`/^[a-f0-9]{64}$/`) | `routes/assets.ts` | 121 |
| 11 | POST | `/assets/image` | JWT (global) | 30/min | `ImageSearchRequestSchema` | `routes/assets.ts` | 176 |
| 12 | GET | `/usage/current` | JWT (global) | None | None | `routes/usage.ts` | 15 |
| 13 | POST | `/billing/checkout` | JWT (selective) | None | `CheckoutRequestSchema` | `routes/billing.ts` | 25 |
| 14 | GET | `/billing/portal` | JWT (selective) | None | None | `routes/billing.ts` | 103 |
| 15 | POST | `/billing/webhook` | Stripe signature | None | None | `routes/billing.ts` | 158 |

**Route composition**: `routes/cards.ts` is a thin 13-line router composing `generate.ts` and `enhance.ts`.

**Auth application** (from `index.ts:34-40`):
- Global `app.use()` on: `/cards/*`, `/assets/*`, `/export/*`, `/usage/*`
- Selective `app.use()` on: `/billing/checkout`, `/billing/portal`
- Unprotected: `/auth/*`, `/health/*`, `/billing/webhook` (Stripe signature verification)

---

## 2. Auth Chain

### Token Flow

```
Client → Authorization: Bearer <JWT>
  → requestId middleware (requestId.ts:12) — sets c.requestId from X-Request-ID header or crypto.randomUUID()
  → auth middleware (middleware/auth.ts:18) — extracts Bearer token
    → createSupabaseAdminClient(env) → validateSupabaseToken(adminClient, token)
    → On success: sets c.userId, c.userEmail
    → On failure: throws HTTPException(401)
  → route handler — reads c.get('userId'), c.get('userEmail')
```

### Supabase Integration

- **Client factory**: `lib/supabase.ts` — `createSupabaseClient(env)` (anon key), `createSupabaseAdminClient(env)` (service role key)
- **Token validation**: `validateSupabaseToken()` calls `supabase.auth.getUser(token)` with the admin client
- **Auth routes** use anon client for `signUp()`, `signInWithPassword()`, `refreshSession()`
- **Protected routes** use admin client for database operations (bypass RLS)

### Protected Route Groups

| Group | Middleware Location | Routes |
|-------|-------------------|--------|
| `/cards/*` | `index.ts:34` | generate, enhance |
| `/assets/*` | `index.ts:35` | tts (POST + GET), image |
| `/export/*` | `index.ts:36` | (not yet implemented) |
| `/usage/*` | `index.ts:37` | current |
| `/billing/checkout` | `index.ts:38` | checkout only |
| `/billing/portal` | `index.ts:39` | portal only |

---

## 3. Stripe/Billing Surface

### Stripe SDK Configuration

- **Package**: `stripe` v20.3.1
- **API version**: `'2026-01-28.clover'` (`services/stripe.ts:17`)
- **Client factory**: `createStripeClient(env)` — no explicit timeout set
- **Workers compatibility**: Uses Stripe's auto-detected `workerd` export (fetch + SubtleCrypto)

### Tier Constants

| Tier Slug | Price ID | Overage Price ID | Cards/Month | Overage Rate |
|-----------|----------|-------------------|-------------|--------------|
| `plus` | `price_1T3GZhALd6l7U7J9o4vMgjvb` | `price_1T3GcHALd6l7U7J9p4uGC0Gx` | 500 | 2¢/card |
| `pro` | `price_1T3Ga7ALd6l7U7J9smHverwQ` | `price_1T3GdIALd6l7U7J9DtOmQciu` | 2,000 | 2¢/card |
| `free` | — | — | 50 | Blocked |

- **Source**: `services/stripe.ts:25-37`, `services/billing.ts:31-44`
- **Meter event name**: `memogenesis_overage` (`stripe.ts:31`)

### Webhook Event Types (6)

| Event | Handler | Behavior | Throws on Supabase Error |
|-------|---------|----------|--------------------------|
| `checkout.session.completed` | `handleCheckoutCompleted()` | Stores `stripe_customer_id` on user | Yes (Stripe retries) |
| `customer.subscription.created` | `handleSubscriptionCreatedOrUpdated()` | Sets tier, status, period dates, limits | Yes |
| `customer.subscription.updated` | `handleSubscriptionCreatedOrUpdated()` | Same handler as created | Yes |
| `customer.subscription.deleted` | `handleSubscriptionDeleted()` | Resets to free tier defaults | Yes |
| `invoice.paid` | `handleInvoicePaid()` | Sets status='active', updates period | No (non-critical) |
| `invoice.payment_failed` | `handleInvoicePaymentFailed()` | Sets status='past_due' | No (non-critical) |
| `invoice.created` | `handleInvoiceCreated()` | Reports overage via Billing Meters API | No (prevents duplicate meter events) |

### Idempotency Patterns

- **Webhook handlers**: Declaratively set state to match Stripe (idempotent by nature)
- **Meter events**: `identifier: overage_${subscriptionId}_${invoiceId}` — 24h Stripe-side dedup (`billing.ts:390`)
- **Checkout sessions**: No explicit idempotency key (Stripe handles session dedup)

---

## 4. Prompt Architecture

### Generation Prompts

**Assembly**: Master base (universal SRS rules, 14-step) + domain hook + optional sub-hook

| Component | File | Purpose |
|-----------|------|---------|
| Master base | `lib/prompts/hooks/master-base.ts` | Universal SRS rules, quality gates, 14-step assembly |
| Hook registry | `lib/prompts/hooks/hook-registry.ts` | `getHook()`, `getHookOptionsForUI()`, `detectHookMismatch()` |
| Generation registry | `lib/prompts/generation/index.ts` | `getGenerationConfig()` — dispatch by domain |

**10 Domain Hooks** (all at `promptVersion: '2.0.0'`):

| Domain | Hook File | Sub-hooks |
|--------|-----------|-----------|
| `lang` | `hooks/lang/lang-domain-hook.ts` | `ja.ts` (Japanese), `default.ts` (CEFR) |
| `general` | `hooks/general/general-domain-hook.ts` | None |
| `med` | `hooks/med/med-domain-hook.ts` | None |
| `stem-m` | `hooks/stem-m/stem-m-domain-hook.ts` | None |
| `stem-cs` | `hooks/stem-cs/stem-cs-domain-hook.ts` | None |
| `fin` | `hooks/fin/fin-domain-hook.ts` | None |
| `law` | `hooks/law/law-domain-hook.ts` | None |
| `arts` | `hooks/arts/arts-domain-hook.ts` | None |
| `skill` | `hooks/skill/skill-domain-hook.ts` | None |
| `mem` | `hooks/mem/mem-domain-hook.ts` | None |

### Enhancement Prompts

**Assembly**: Master enhance base (universal principles, 21-section) + domain hook

| Component | File | Purpose |
|-----------|------|---------|
| Master enhance base | `lib/prompts/hooks/master-enhance-base.ts` | Universal enhance principles, 21 injection points |
| Enhance hook registry | `lib/prompts/hooks/enhance-hook-registry.ts` | `getEnhanceHook()` |
| Enhancement registry | `lib/prompts/enhancement/index.ts` | `getEnhancementConfig()` — all 10 domains + generic fallback |

**10 Enhancement Hooks** (all at `promptVersion: '2.0.0'`):
- `hooks/{domain}/{domain}-enhance-hook.ts` for all 10 domains
- Generic fallback: `enhancement/enhance-v1.2.0.ts` for unknown domains

### Monolithic Reference Files

Still present in `generation/` and `enhancement/` directories (v1.2.0/v1.3.0). Constants, schemas, and helpers are still imported by hooks. Not used directly by route handlers.

---

## 5. Shared Contracts

### product_source Requirement

- **Backend Zod schema**: `ProductSourceSchema = z.enum(['anki_addon', 'browser_extension', 'android_app', 'api', 'web_app'])` (`lib/validation/cards.ts:32-38`)
- **Required in**: `GenerateRequestSchema`, `EnhanceRequestSchema`, `TTSRequestSchema`, `ImageSearchRequestSchema`
- **Anki add-on**: Injects `"anki_addon"` in `client.py:96`

### request_id in All Responses

- **Generation**: `requestId middleware` (`middleware/requestId.ts`) sets `X-Request-ID` header and `c.requestId` variable
- **Success responses**: Explicitly include `request_id: c.get('requestId')`
- **Error responses**: Include `request_id` via error handler (`middleware/errorHandler.ts:30`) and inline error returns
- **404 handler**: Includes `request_id` (`index.ts:52`)

### fc-* HTML Structure

- **Wrapper**: `fc-front` / `fc-back` on outermost divs
- **Section pattern**: `<div class="fc-section fc-{type}"><div class="fc-heading">...</div><div class="fc-content">...</div></div>`
- **Section types**: `fc-meaning`, `fc-example`, `fc-notes`, `fc-meta`, `fc-formula`, `fc-code`, `fc-source`
- **Meta elements**: `fc-tag` (badges), `fc-register` (formality)
- **LANG-specific**: `fc-word`, `fc-reading` (furigana), `fc-jp`/`fc-en` (bilingual)
- **Furigana**: `<ruby>kanji<rt>reading</rt></ruby>` — per-kanji annotation
- **Backend source**: All 10 generation + 10 enhancement prompts
- **Add-on consumer**: `src/styles/stylesheet.py` (FC_STYLESHEET), `src/enhance/processor.py` (section parsing)

### ErrorCode Union

Defined in `types/index.ts:47-55`:

```typescript
type ErrorCode =
  | 'VALIDATION_ERROR'   // 400
  | 'UNAUTHORIZED'       // 401
  | 'USAGE_EXCEEDED'     // 402
  | 'FORBIDDEN'          // 403
  | 'NOT_FOUND'          // 404
  | 'CONTENT_TOO_LARGE'  // 413
  | 'RATE_LIMITED'        // 429
  | 'INTERNAL_ERROR';     // 500
```

**Note**: `CONFLICT` (409) is NOT in the ErrorCode union but IS returned by `auth.ts:50,73` for duplicate signup.

### Zod Schemas by Domain

| File | Schemas |
|------|---------|
| `validation/cards.ts` | `GenerateRequestSchema`, 10 domain output schemas (LANG, GENERAL, MED, etc.), `GenerateUsageSchema` |
| `validation/enhance.ts` | `EnhanceRequestSchema`, `EnhancementsSchema`, `EnhanceClaudeOutputSchema`, `EnhancedCardResponseSchema` |
| `validation/assets.ts` | `TTSRequestSchema`, `ImageSearchRequestSchema`, `TTSVoiceSchema` |
| `validation/auth.ts` | `SignupRequestSchema`, `LoginRequestSchema`, `RefreshRequestSchema` |
| `validation/billing.ts` | `CheckoutRequestSchema` |

---

## 6. External API Integrations

| Service | Client | Timeout | Retry | Error Class | Notes |
|---------|--------|---------|-------|-------------|-------|
| Claude API | `fetch()` with AbortController | 60s (`services/claude.ts:6`) | 1 retry on 5xx; no retry on 4xx or timeout | `ClaudeError` | Model: `claude-sonnet-4-5-20250929` |
| OpenAI TTS | `fetch()` with AbortController | 15s (`services/tts.ts`) | None | `TTSError` | R2 cache (SHA256 key); 90-day expiry |
| Unsplash | `fetch()` with AbortController | 10s (`services/unsplash.ts`) | None | `UnsplashError` | ToS compliance: `triggerDownload()` after use |
| Stripe SDK | `stripe` npm package | No explicit timeout (SDK default ~80s) | SDK-internal | `StripeServiceError` | Workers-compatible; SubtleCrypto provider |
| Haiku translator | `fetch()` (via Claude API) | 5s (`services/imageQueryExtractor.ts`) | None | Falls back to input text | Model: `claude-haiku-4-5-20251001`; translates non-Latin → English for Unsplash |

### R2 TTS Cache Pattern

- **Key**: `SHA256(text + voice + language + speed)` (hex, 64 chars)
- **Path**: `tts-cache/{key}.mp3`
- **Flow**: Check R2 → hit: return `/assets/tts/{key}` proxy URL → miss: call OpenAI → store in R2 → return URL
- **Expiry**: 90-day lifecycle rule on R2 bucket
- **Client cache**: `Cache-Control: private, max-age=3600` on GET `/assets/tts/:cacheKey`

---

## 7. Anki Add-on Patterns

### API Call Sites (6)

| # | Function | File | Endpoint | Auth | Timeout |
|---|----------|------|----------|------|---------|
| 1 | `login()` | `api/auth.py` | `POST /auth/login` | None | 10s |
| 2 | `_try_refresh()` | `api/client.py:141` | `POST /auth/refresh` | None | 10s |
| 3 | `generate_cards()` | `api/cards.py` | `POST /cards/generate` | JWT | 60s |
| 4 | `enhance_cards()` | `api/enhance.py` | `POST /cards/enhance` | JWT | 120s |
| 5 | `download_tts()` | `enhance/media.py:22` | `GET /assets/tts/:cacheKey` | JWT (manual) | 15s |
| 6 | `download_image()` | `enhance/media.py:68` | Direct URL (Unsplash) | None | 10s |

### Thread Model

- **Main thread**: Anki UI, note creation, `mw.col` access, media saving
- **Background thread**: `ApiWorker(QThread)` in `api/worker.py` for all API calls
- **Signal bridge**: `worker.finished.connect(callback)` → callback runs on main thread
- **Blocking exception**: Media downloads (`download_tts`, `download_image`) run on main thread after API worker finishes (small files)

### Token Storage

- **Location**: Anki config system → `%APPDATA%\Anki2\addons21\flashcard-anki\meta.json`
- **Mechanism**: `AddonConfig.set_auth_tokens()` (`utils/config.py:134-151`)
- **Fields stored**: `auth_token` (JWT), `refresh_token`, `token_expires_at` (epoch), `user_email`, `user_id`
- **Format**: Plaintext JSON — no encryption
- **Refresh**: Transparent in `client.py:141-185` — 401 → `_try_refresh()` → retry once

### Undo Checkpoints

| Operation | Checkpoint Label | File | Line |
|-----------|-----------------|------|------|
| Generate cards | `"Generate Cards"` | `generate/processor.py` | via `create_notes_in_anki()` |
| Enhance cards | `"Enhance Cards"` | `enhance/processor.py:299` | `mw.checkpoint("Enhance Cards")` |

### Error Mapping

| HTTP Status | Backend Code | Add-on Exception | Add-on Behavior |
|-------------|-------------|------------------|-----------------|
| 401 | `UNAUTHORIZED` | `AuthenticationError` | `_try_refresh()` → retry once → clear token if still 401 |
| 429 | `RATE_LIMITED` | `ApiError` (retry) | `time.sleep(retry_after)` → retry up to 2 times |
| 402 | `USAGE_EXCEEDED` | `ApiError` | Show upgrade message |
| 500 | `INTERNAL_ERROR` | `ApiError` | Show "Something went wrong" + `request_id` |
| Timeout | — | `NetworkError` | Show retry dialog |
| Connection | — | `NetworkError` | Show retry dialog |

### Config Defaults

Defined in `utils/config.py:22-49` (`_DEFAULTS` dict):

| Key | Default | Purpose |
|-----|---------|---------|
| `api_base_url` | `https://flashcard-backend-staging.luiswgordon.workers.dev` | Backend URL |
| `default_domain` | `"general"` | Generation default |
| `default_card_style` | `"mixed"` | Generation default |
| `default_difficulty` | `"intermediate"` | Generation default |
| `default_lang_hook` | `"ja"` | Language sub-hook |
| `default_max_cards` | `10` | Generation default |
| `generate_add_tts` | `False` | TTS in generate flow |
| `generate_add_images` | `False` | Images in generate flow |
| `enhance_batch_size` | `10` | Cards per enhance batch |
| `styled_note_types` | `[]` | Note types with FC CSS |
| `auto_prompt_styles` | `True` | Prompt to add styles |

---

*Generated 2026-02-21 by full codebase audit.*
