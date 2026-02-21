# Flashcard Tools Ecosystem — Product Requirements Document

This document contains four PRDs for a suite of AI-powered flashcard tools sharing a common backend. Build in sequence: Backend → Anki Add-on → Browser Extension → Android App.

> **Current Status (2026-02-21)**: Backend Phases 1–4 complete. Phase 5b (Billing) code complete, migration pending production deploy. Phase 7a–7b (Structured HTML + Furigana) complete across all 10 domains. Anki Add-on Phases 1–6 complete. Phase 7c (CSS stylesheet injection) complete, 7d (note type templates) not started. Next: Phase 5b production deploy → Web App. Both Web App PRD and Browser Extension PRD drafted.

---

# PRD 1: Flashcard Tools Backend

```yaml
title: "Flashcard Tools Backend"
status: active
priority: critical
created: 2025-01-26
updated: 2026-02-21
owner: Luis
dependencies: []
estimated_effort: 20-27 hours (Phases 1-4 done)
```

## Executive Summary

A serverless backend providing AI flashcard generation, content enhancement, asset creation (TTS/images), and usage-based billing. Powers multiple client applications: an Anki add-on, web app, browser extension, and Android app. Features a domain-aware prompt system with 10 specialized domains, each with dedicated generation and enhancement prompts. Product name: **Memogenesis**.

## Problem Statement

Creating flashcards from content is manual and tedious. Enhancing existing cards with audio, images, and context is even more so. Users need an AI-powered service that handles these transformations while tracking usage for billing.

**Who has this problem?** Learners who use spaced repetition but find card creation/enhancement to be the bottleneck in their workflow.

**Current alternatives:** Manual card creation, scattered browser extensions with no mobile support, no unified enhancement tools for existing decks.

## Goals & Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| API response time | < 3s for card generation | P95 latency in Cloudflare analytics |
| Uptime | 99.5% | Cloudflare Workers metrics |
| Cost per card | < €0.02 average | Stripe usage records / card count |

## Domain System

The backend uses a domain-aware prompt architecture: every generation and enhancement request specifies a `domain` that routes to specialized prompts with domain-specific metadata, tagging conventions, card subtypes, and quality criteria.

| Domain | Slug | Purpose | Key Features |
|--------|------|---------|--------------|
| Language | `lang` | Japanese-English language learning | Bidirectional vocab pairs, pitch accent notation, furigana/reading in metadata, register marking (formal/neutral/casual/vulgar), JLPT level tagging, grammar cloze cards, expression cards, polysemy handling |
| General | `general` | General knowledge, trivia, interdisciplinary | Etymology, common misconceptions, source/origin notes, related concept linking, hierarchical `general::` namespaced tags |
| Medical | `med` | Medical education (pharmacology, pathology, anatomy) | Drug cards, mechanism cards, clinical vignettes, clinical pearls, red flags, distinguishing features, source citations |
| Mathematics | `stem-m` | STEM mathematics (formulas, theorems, proofs) | LaTeX formula rendering, variable definitions, domain restrictions, application contexts, prerequisite chains |
| Computer Science | `stem-cs` | Programming and CS concepts | Output prediction cards, syntax recall, gotcha cards, complexity analysis, runnable code snippets, language-versioned content |
| Finance | `fin` | Finance & business (CFA, CPA, accounting) | Formula cards, ratio cards, GAAP/IFRS distinctions, ethics scenarios, certification-level tagging (CFA L1-3, CPA, Series 7) |
| Legal | `law` | Legal education (bar exam, case law, statutes) | Rule element decomposition, case holdings, statute cards, majority/minority rules, jurisdiction tagging, bar-tested flagging |
| Arts | `arts` | Arts & humanities (art history, music, literature) | Identification cards, movement/period classification, artist/work metadata, cultural context, medium and location tracking |
| Skills | `skill` | Hobbies & practical skills (chess, cooking, sports) | Situation-response cards, technique cards, equipment lists, safety notes, common mistakes, practice tips |
| Memory | `mem` | Memory techniques (mnemonics, memory palaces, PAO) | Technique definitions, step sequences, encoding cards, competition relevance, personal imagery flagging |

Each domain has both a generation prompt (`{domain}-v1.0.0.ts`) and an enhancement prompt (`enhance-{domain}-v1.0.0.ts`), plus a generic fallback enhancement prompt (`enhance-v1.0.0.ts`). All generation prompts share common quality gates: confidence scoring (atomicity, self-containment), unsuitable content filtering, and source quote attribution. All enhancement prompts share smart triage logic (skip enhancements when cards are already well-formed, with specific reasons).

## Technical Specifications

### Tech Stack
- **Runtime**: Cloudflare Workers
- **Framework**: Hono v4.x
- **Database**: Supabase (PostgreSQL)
- **Auth**: Supabase Auth (email + OAuth)
- **Payments**: Stripe (subscription + metered overage billing)
- **AI**: Claude API (claude-sonnet-4-5-20250929 primary, claude-haiku-4-5-20251001 for cost-sensitive)
- **TTS**: OpenAI TTS API (tts-1 model)
- **Images**: Unsplash API
- **Object Storage**: Cloudflare R2

### Data Models

```typescript
// Supabase tables

interface User {
  id: string;                           // UUID, from Supabase Auth
  email: string;
  stripe_customer_id: string | null;    // Created on first checkout
  subscription_tier: string;            // 'free' | 'pro' | 'power'
  subscription_status: string;          // 'active' | 'past_due' | 'canceled' | 'unpaid'
  stripe_subscription_id: string | null;
  stripe_price_id: string | null;
  subscription_period_start: string | null; // ISO8601 — billing period start
  subscription_period_end: string | null;   // ISO8601 — billing period end
  cards_limit_monthly: number;          // 50 (free), 500 (pro), 2000 (power)
  overage_rate_cents: number;           // 0 (free), 2 (pro), 2 (power)
  free_cards_used: number;              // Legacy — deprecated by subscription-aware usage counting
  free_cards_reset_at: string;          // Legacy — deprecated by subscription_period_start
  created_at: string;
  updated_at: string;
}

interface UsageRecord {
  id: string;                    // UUID
  user_id: string;               // FK to User
  action_type: 'generate' | 'enhance' | 'tts' | 'image';
  product_source: 'anki_addon' | 'web_app' | 'browser_extension' | 'android_app' | 'api';
  card_count: number;
  tokens_used: number;           // Claude API tokens
  cost_cents: number;
  stripe_usage_record_id: string;
  created_at: string;
  updated_at: string;
}

interface GenerationRequest {
  id: string;                    // UUID
  user_id: string;               // FK to User
  content_type: 'text' | 'url' | 'pdf';
  content_size_bytes: number;
  source_content: string;        // Raw input (truncated for storage)
  cards_generated: number;
  prompt_version: string;        // Semver for A/B testing
  status: 'pending' | 'processing' | 'completed' | 'failed';
  error_message: string | null;
  created_at: string;
  updated_at: string;
}

// R2 object metadata (not a Supabase table)
interface TTSCacheEntry {
  cache_key: string;             // SHA256(text + voice + language)
  r2_path: string;               // e.g., "tts-cache/abc123.mp3"
  text_hash: string;
  voice: string;                 // OpenAI voice ID
  language: string;              // ISO 639-1
  file_size_bytes: number;
  hit_count: number;
  created_at: string;
  expires_at: string;            // 90 days from creation
}
```

### API Endpoints

| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/auth/signup` | POST | Create account | None |
| `/auth/login` | POST | Get session token | None |
| `/auth/refresh` | POST | Refresh token | None |
| `/auth/me` | GET | Get authenticated user profile | Required |
| `/cards/generate` | POST | Generate flashcards from content | Required |
| `/cards/enhance` | POST | Enhance existing cards | Required |
| `/assets/tts` | POST | Generate audio for text | Required |
| `/assets/tts/:cacheKey` | GET | Retrieve cached TTS audio | Required |
| `/assets/image` | POST | Search and return image | Required |
| `/export/cards` | POST | Return card data as JSON for client-side .apkg generation | Required |
| `/usage/current` | GET | Current billing period usage and subscription status | Required |
| `/billing/portal` | GET | Stripe Customer Portal URL | Required |
| `/billing/checkout` | POST | Create Stripe Checkout session for new subscription | Required |
| `/billing/webhook` | POST | Stripe webhook handler | Stripe signature |
| `/health` | GET | Health check | None |

### Content Size Limits

| Content Type | Max Size | Enforcement |
|--------------|----------|-------------|
| Text (raw) | 100KB | 413 if exceeded |
| URL (fetched) | 100KB after extraction | Truncate with warning in response |
| PDF | 10MB file, 100KB extracted text | 413 if file too large; truncate text |

### Key Endpoint Contracts

**POST /cards/generate**
```typescript
// Request
{
  content: string;
  content_type: 'text' | 'url' | 'pdf';
  domain: 'lang' | 'general' | 'med' | 'stem-m' | 'stem-cs' | 'fin' | 'law' | 'arts' | 'skill' | 'mem';
  product_source: 'anki_addon' | 'web_app' | 'browser_extension' | 'android_app' | 'api';
  options: {
    max_cards: number;          // Default 10, max 50
    card_style: 'basic' | 'cloze' | 'mixed';
    difficulty: 'beginner' | 'intermediate' | 'advanced';
    include_context: boolean;
  }
}

// Response (200)
{
  request_id: string;
  cards: Array<{
    front: string;
    back: string;
    card_type: 'basic' | 'cloze';
    tags: string[];
    notes: string;
    source_quote: string;
    confidence_scores: { atomicity: number; self_contained: number };
    // Domain-specific metadata (varies by domain):
    lang_metadata?: { reading, example_sentence, example_translation, register, jlpt_level, word_type, audio_recommended, image_recommended };
    general_metadata?: { category, difficulty_level, related_concepts, image_recommended };
    med_metadata?: { sub_domain, card_subtype, source_citation, clinical_pearl, red_flag, ... };
    // ... similar for other domains
  }>;
  rejected?: Array<{ card: object; errors: string[] }>;     // Cards failing quality gates
  unsuitable_content?: Array<{ content: string; reason: string; explanation: string }>;
  usage: {
    cards_generated: number;
    cards_rejected: number;
    cards_remaining: number | null;   // Remaining in current billing period (all tiers)
    tokens_used: number;
  };
  warnings: string[];
}
```

**POST /cards/enhance**
```typescript
// Request
{
  cards: Array<{
    id: string;                 // Client-side ID for matching
    front: string;
    back: string;
    existing_tags: string[];
    existing_notes: string;
  }>;
  product_source: 'anki_addon' | 'web_app' | 'browser_extension' | 'android_app' | 'api';
  domain: 'lang' | 'general' | 'med' | ... ;   // Default: 'general'
  enhancements: {
    add_tts: boolean;
    tts_voice: string;          // OpenAI voice ID, default 'alloy'
    tts_language: string;       // BCP-47, default 'en'
    add_images: boolean;
    add_context: boolean;
    add_tags: boolean;
    fix_formatting: boolean;
  }
}

// Response (200)
{
  request_id: string;
  enhanced_cards: Array<{
    id: string;                  // Matches request
    front: string;               // Possibly reformatted
    back: string;
    tags: string[];              // Merged: existing + suggested
    notes: string;               // Appended: existing + context
    skipped_enhancements: Array<{ type: string; reason: string }>;
    tts_front_url: string | null;
    tts_back_url: string | null;
    image_url: string | null;
    image_attribution: string | null;
    image_search_query: string | null;  // LLM-generated, English, 3-8 words
  }>;
  failed_cards: Array<{ id: string; error: string }>;
  usage: {
    cards_enhanced: number;
    tts_characters: number;
    cost_cents: number;
  }
}
```

**POST /export/cards** *(Not yet implemented — Phase 5a)*
```typescript
// Request
{
  deck_name: string;
  card_ids?: string[];
  include_media_urls: boolean;
}

// Response (200)
{
  request_id: string;
  deck_name: string;
  cards: Array<{
    front: string;
    back: string;
    card_type: 'basic' | 'cloze';
    tags: string[];
    notes: string;
    media: Array<{ filename: string; url: string; type: 'audio' | 'image' }>;
  }>;
  card_count: number;
}
```

**GET /usage/current** *(Phase 5b)*
```typescript
// Response (200)
{
  request_id: string;
  tier: 'free' | 'pro' | 'power';
  status: 'active' | 'past_due' | 'canceled' | 'unpaid';
  period: {
    start: string;               // ISO8601
    end: string | null;          // null for free tier
  };
  usage: {
    cards_generated: number;
    cards_limit: number;
    cards_remaining: number;     // max(0, limit - generated)
    overage_cards: number;       // cards beyond limit (pro/power only)
    overage_cost_cents: number;
  };
  actions: {
    generate: number;
    enhance: number;
    tts: number;
    image: number;
  };
}
```

**POST /billing/checkout** *(Phase 5b)*
```typescript
// Request
{
  tier: 'pro' | 'power';
  success_url: string;           // Web app URL for redirect after success
  cancel_url: string;            // Web app URL for redirect on cancel
}

// Response (200)
{ request_id: string; url: string; }
```

**GET /billing/portal** *(Phase 5b)*
```typescript
// Response (200)
{ request_id: string; url: string; }

// Response (400) — free tier user with no Stripe customer
{ request_id: string; error: "No billing account. Subscribe to a plan first."; code: "VALIDATION_ERROR"; }
```

**POST /billing/webhook** *(Phase 5b)*

Stripe webhook handler. **Not JWT-authenticated** — uses Stripe signature verification. See Phase 5b section for event handling details.

### Error Response Format

```typescript
{
  request_id: string;
  error: string;           // Human-readable
  code: string;            // Machine-readable
  retry_after?: number;    // Seconds (only for RATE_LIMITED)
  reason?: string;         // Discriminant for 402 responses (only for USAGE_EXCEEDED)
  details?: object;        // Additional context (only for VALIDATION_ERROR)
}
```

| Code | HTTP Status | When Used |
|------|-------------|-----------|
| `VALIDATION_ERROR` | 400 | Request body fails Zod schema validation |
| `UNAUTHORIZED` | 401 | Missing, invalid, or expired JWT |
| `USAGE_EXCEEDED` | 402 | Free tier exhausted or subscription inactive. `reason`: `'limit_reached'` or `'subscription_inactive'` |
| `FORBIDDEN` | 403 | Valid auth but insufficient permissions |
| `NOT_FOUND` | 404 | Resource doesn't exist |
| `CONFLICT` | 409 | Duplicate resource (e.g., email already registered) |
| `CONTENT_TOO_LARGE` | 413 | Request body exceeds size limit |
| `RATE_LIMITED` | 429 | Per-user rate limit exceeded |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

### Rate Limiting

| Limit Type | Value | Scope |
|------------|-------|-------|
| Per-user requests | 10/minute | All authenticated endpoints |
| Per-user generation | 100/hour | `/cards/generate` only |
| Per-user daily | 500/day | All card operations |
| Global DDoS | 1000/minute | All endpoints |

## Client Error Handling Contract

| Code | HTTP | Client Behavior |
|------|------|-----------------|
| `VALIDATION_ERROR` | 400 | Highlight invalid fields, show inline error messages |
| `UNAUTHORIZED` | 401 | Clear stored token, redirect to login screen |
| `USAGE_EXCEEDED` | 402 | If `reason: 'limit_reached'`: **free tier** → display upgrade modal, block action; **paid tier** → show overage confirmation, allow action. If `reason: 'subscription_inactive'`: show "subscription inactive" banner with link to billing portal |
| `CONFLICT` | 409 | Show "already exists" message, suggest login instead |
| `CONTENT_TOO_LARGE` | 413 | Show "Content too large" with size limit |
| `RATE_LIMITED` | 429 | Show toast, auto-retry after `retry_after` (max 2 retries) |
| `INTERNAL_ERROR` | 500 | Show "Something went wrong" toast, log `request_id` |

## Project Structure

```
flashcard-backend/
├── docs/
│   ├── session-log.md
│   ├── architecture.md
│   ├── billing-spec.md         # Full billing implementation spec
│   └── spikes/
│       └── apkg-workers.md
├── src/
│   ├── index.ts
│   ├── routes/
│   │   ├── auth.ts
│   │   ├── cards.ts            # Generate + enhance endpoints
│   │   ├── assets.ts           # TTS + image endpoints
│   │   ├── billing.ts          # Checkout, portal, webhook endpoints
│   │   ├── usage.ts            # /usage/current endpoint
│   │   └── health.ts
│   ├── middleware/
│   │   ├── auth.ts
│   │   ├── rateLimit.ts
│   │   ├── contentSize.ts
│   │   ├── requestId.ts
│   │   └── usage.ts
│   ├── services/
│   │   ├── claude.ts
│   │   ├── tts.ts
│   │   ├── unsplash.ts
│   │   ├── stripe.ts               # Stripe client, checkout/portal session creation
│   │   ├── billing.ts              # Webhook event handlers, tier mapping
│   │   ├── imageQueryExtractor.ts   # Fallback image query from card.front
│   │   ├── enhancementProcessor.ts  # Claude output → API response mapping
│   │   ├── cardValidator.ts         # Per-domain post-processing validation
│   │   └── usage.ts
│   ├── lib/
│   │   ├── supabase.ts
│   │   ├── validation/
│   │   │   ├── cards.ts        # Generate schemas + domain taxonomy
│   │   │   ├── enhance.ts      # Enhance schemas
│   │   │   ├── auth.ts
│   │   │   ├── assets.ts
│   │   │   └── billing.ts      # Checkout + webhook Zod schemas
│   │   └── prompts/
│   │       ├── lang-v1.0.0.ts          # LANG generation prompt
│   │       ├── enhance-lang-v1.0.0.ts  # LANG enhancement prompt
│   │       ├── general-v1.0.0.ts       # ... and so on for all 10 domains
│   │       ├── enhance-general-v1.0.0.ts
│   │       ├── ... (20 prompt files total: 10 generate + 10 enhance)
│   │       └── enhance-v1.0.0.ts       # Generic fallback enhance prompt
│   └── types/
│       ├── index.ts
│       └── database.ts
├── test/
│   ├── fixtures/
│   ├── unit/
│   └── integration/
├── wrangler.toml
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

## Boundaries

### ✅ Always
- Validate all input with Zod schemas before processing
- Enforce content size limits before reading request body
- Return consistent error response format with `request_id`
- Check usage limits before processing paid operations
- Track `product_source` in all UsageRecords
- Use domain-specific prompts for generation and enhancement
- Update `docs/session-log.md` at the end of each session

### ⚠️ Ask First
- Adding new environment variables or changing database schema
- Modifying rate limits or pricing
- Adding new external API integrations

### 🚫 Never
- Commit API keys or secrets
- Store raw user content longer than 30 days
- Make Claude API calls without timeout handling
- Return internal error details to clients

## Implementation Phases

### Phase 1: Project Setup, Auth & Observability — ✅ COMPLETE

Setup: Hono project, Supabase, auth endpoints (`/auth/signup`, `/auth/login`, `/auth/refresh`, `/auth/me`), middleware (auth, requestId, contentSize), `/health`, vitest, deploy to Cloudflare Workers, error alerting.

### Phase 2: Card Generation Endpoint — ✅ COMPLETE

Claude API service with retry/timeout, prompt templates for all 10 domains with domain-specific metadata schemas, URL content extraction, `/cards/generate` endpoint, Zod validation, UsageRecord tracking with `product_source`, free tier logic (50 cards/month unified), rate limiting, confidence scoring and post-processing validation per domain.

### Phase 3: Card Enhancement Endpoint — ✅ COMPLETE

`/cards/enhance` endpoint with domain-aware prompt routing, smart triage (AI skips unnecessary enhancements with reasons), `skipped_enhancements` and `failed_cards` in response, selective enhancement logic, batch processing with partial failure handling.

### Phase 4: Asset Generation — ✅ COMPLETE

OpenAI TTS service with R2 caching (SHA256 key), `/assets/tts` + `/assets/tts/:cacheKey` endpoints, Unsplash image search with attribution, TTS/images integrated into `/cards/enhance` flow (parallel processing), `image_search_query` field added to all 11 enhancement prompts (LLM generates 3-8 word English stock photo queries instead of literal translations from card.front).

**Test coverage**: 240/240 tests passing across 13 test files.

### Phase 5a: Card Export Endpoint — POSTPONED

> Postponed until before browser extension/Android app. Anki add-on uses direct note insertion, so it doesn't need this endpoint.

Returns structured JSON for client-side .apkg generation. Server-side .apkg generation is not viable in Cloudflare Workers (sql.js WASM incompatibility).

### Phase 5b: Billing Integration — CODE COMPLETE

Subscription billing with Stripe: free/pro/power tiers, overage reporting, webhook-driven state sync. Prerequisite for web app launch. Code is complete and tested on staging; SQL migration pending production deploy.

**Subscription tiers:**

| Tier | Slug | Price | Cards/month | Overage |
|------|------|-------|-------------|---------|
| Free | `free` | €0 | 50 | Blocked (upgrade required) |
| Pro | `pro` | €9/month | 500 | €0.02/card |
| Power | `power` | €29/month | 2,000 | €0.015/card |

Card count = generation actions only. All tiers include generation, enhancement, TTS, and image features.

**New files:** `src/routes/billing.ts`, `src/routes/usage.ts`, `src/services/stripe.ts`, `src/services/billing.ts`, `src/lib/validation/billing.ts`

**Modified files:** `src/types/index.ts` (Stripe env vars, SubscriptionTier), `src/types/database.ts` (subscription columns), `src/services/usage.ts` (subscription-aware), `src/index.ts` (mount routes)

**Full implementation spec:** `@docs/billing-spec.md`. Endpoint contracts at `/usage/current`, `/billing/checkout`, `/billing/portal`, `/billing/webhook` — see "Key Endpoint Contracts" above.

### Phase 7: CSS Styling & Furigana — 7a+7b COMPLETE, 7c+7d see PRD 2

Structured HTML output with `fc-*` CSS classes across all 10 domains. Furigana in LANG domain. Backend work complete (7a+7b). Anki add-on CSS injection complete (7c), note type templates not started (7d). See PRD 2 Phase 7 for full status.

## Commands

```bash
npm install                        # Install dependencies
npm run dev                        # wrangler dev --local
npm run test                       # vitest
npm run test:coverage              # vitest --coverage
npm run typecheck                  # tsc --noEmit
npm run lint                       # eslint src/
npm run lint:fix                   # eslint src/ --fix
npm run deploy:staging             # wrangler deploy --env staging
npm run deploy:production          # wrangler deploy --env production
```

## Environment Configuration

| Setting | Staging | Production |
|---------|---------|------------|
| Rate limits | Disabled | Enforced (10 req/min) |
| Free tier | Bypassed for test accounts | Enforced (50 cards/month) |
| Log level | `debug` | `info` |
| Stripe mode | Test | Live |
| Stripe webhook secret | Test secret | Production secret |
| Error alerting | Disabled | Enabled (1% threshold) |

**Environment variables (secrets in `wrangler.jsonc`):**

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anonymous key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role (webhook handler) |
| `ANTHROPIC_API_KEY` | Claude API |
| `OPENAI_API_KEY` | TTS API |
| `UNSPLASH_ACCESS_KEY` | Image search |
| `STRIPE_SECRET_KEY` | Stripe API calls |
| `STRIPE_WEBHOOK_SECRET` | Webhook signature verification |

---

# PRD 2: Anki Flashcard Add-on

```yaml
title: "Anki Flashcard Add-on"
status: active
priority: high
created: 2025-01-26
updated: 2026-02-21
owner: Luis
dependencies: ["Flashcard Tools Backend"]
estimated_effort: 15-19 hours (Phases 1-6 done)
```

## Executive Summary

A Python-based Anki add-on enabling users to generate AI-powered flashcards from pasted content and enhance existing cards with contextual notes, smart tagging, TTS audio, and images — directly within Anki's native interface. Supports all 10 backend domains for specialized card generation and enhancement.

## Problem Statement

Anki users who want to create cards from content they're studying and enrich existing decks without manual effort. No existing tool provides AI-powered generation or batch enhancement inside Anki.

## Goals & Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Generation latency | < 10s for 10 cards | Timed API calls |
| Enhancement latency | < 5s per card | Timed API calls |
| User adoption | 100 downloads in first month | Anki add-on stats |
| User satisfaction | 4+ star rating | AnkiWeb reviews |

## Technical Specifications

### Tech Stack
- **Language**: Python 3.9+ (Anki's bundled version)
- **Anki Version**: 2.1.50+ (required for PyQt6)
- **UI Framework**: PyQt6 (Anki's native)
- **HTTP Client**: `requests` (bundled with Anki)
- **Storage**: Anki's built-in SQLite database and config system

### API Integration

The add-on consumes these backend endpoints:
- `POST /auth/login` — Authentication
- `POST /auth/refresh` — Token renewal
- `POST /cards/generate` — Generate cards from content (with `domain` parameter)
- `POST /cards/enhance` — Enhance existing cards (with `domain` parameter)
- `GET /assets/tts/:cacheKey` — Download TTS audio (authenticated)

All API calls include `product_source: 'anki_addon'`.

## Project Structure

```
flashcard-anki/
├── __init__.py
├── manifest.json
├── config.json
├── src/
│   ├── api/
│   │   ├── client.py           # HTTP client with auth header injection
│   │   ├── auth.py             # Login, token refresh
│   │   ├── generate.py         # /cards/generate call + response parsing
│   │   └── enhance.py          # /cards/enhance call + response parsing
│   ├── ui/
│   │   ├── dialogs/
│   │   │   ├── login.py        # Login dialog
│   │   │   ├── generate.py     # Card generation dialog
│   │   │   ├── review.py       # Review generated cards before creation
│   │   │   ├── enhance.py      # Enhancement options dialog
│   │   │   └── settings.py     # Settings dialog
│   │   ├── widgets/
│   │   │   ├── domain_selector.py  # 10-domain dropdown
│   │   │   └── card_list.py        # Editable card list for review
│   │   └── browser.py          # Browser context menu integration
│   ├── generate/
│   │   ├── processor.py        # Generation orchestration
│   │   └── creator.py          # Anki note creation
│   ├── enhance/
│   │   ├── processor.py        # Enhancement application + media integration
│   │   └── media.py            # TTS/image download and storage
│   ├── hooks.py                # Anki hook registrations (menu items, shortcuts)
│   └── utils/
│       ├── config.py           # Configuration management with validated setters
│       └── logging.py          # Logging utilities
├── tests/
│   ├── test_api.py
│   ├── test_generate.py
│   ├── test_enhance.py
│   ├── test_media.py
│   ├── test_settings.py
│   └── conftest.py
└── tools/
    └── package.py              # Builds dist/flashcard-tools.ankiaddon
```

## Boundaries

### ✅ Always
- Preserve original card content (enhancements are additive)
- Handle network failures gracefully with retry option
- Show progress for batch operations
- Cache auth tokens securely in Anki's config
- Support undo for all operations via `mw.checkpoint()`
- Include `product_source: 'anki_addon'` in all API requests
- Sanitize user-provided text with `html.escape()` before injecting into card HTML

### ⚠️ Ask First
- Modifying note types (templates)
- Batch operations on > 50 cards (hard limit enforced)

### 🚫 Never
- Store passwords (only tokens)
- Modify cards without user confirmation
- Block the main thread during API calls (except media downloads for small files)

## Implementation Phases

### Phase 1: Project Setup & Auth — ✅ COMPLETE

- [x] Add-on structure following Anki conventions
- [x] Configuration management (`src/utils/config.py`)
- [x] Login dialog with email/password
- [x] Token storage (encrypted in config)
- [x] Token refresh logic
- [x] Menu items for login/logout
- [x] Installation via .ankiaddon file

### Phase 2: Card Generation UI — ✅ COMPLETE

- [x] "Generate Cards" in Tools menu
- [x] Generation dialog with text input, domain selector (10 domains), card style, difficulty, max cards
- [x] Call `POST /cards/generate` with `product_source: 'anki_addon'` and `domain`
- [x] Review dialog: editable card list with front, back, tags, notes per card
- [x] Delete individual cards from review list
- [x] Domain selector widget with all 10 domains
- [x] Usage counter display
- [x] API error handling (timeout, rate limit, usage exceeded)

### Phase 3: Card Creation in Anki — ✅ COMPLETE

- [x] Deck selector (existing decks + create new)
- [x] Note type mapping (Basic → front/back, Cloze → text/extra)
- [x] Apply tags from generated cards
- [x] Batch creation with progress indicator
- [x] Undo support via `mw.checkpoint("Generate Cards")`
- [x] Results summary ("Created 8 cards in deck 'Biology'")
- [x] Mixed card type handling (basic + cloze)

### Phase 4: Browser Integration & Enhancement — ✅ COMPLETE

- [x] "Enhance with AI" in browser context menu
- [x] Enhancement options dialog (context, tags, formatting, TTS, images)
- [x] Domain selector for enhancement requests
- [x] Card selection handling from browser
- [x] Keyboard shortcut (Ctrl+Shift+E)
- [x] Call `POST /cards/enhance` with selected cards and domain
- [x] Apply enhancements: merge tags, append notes, handle `skipped_enhancements`
- [x] Undo support via `mw.checkpoint("Enhance Cards")`
- [x] Handle partial failure (`failed_cards` in response)

### Phase 5: TTS & Image Handling — ✅ COMPLETE

- [x] Download TTS audio from `/assets/tts/:cacheKey` (authenticated)
- [x] Download images from Unsplash URLs (direct, no auth)
- [x] Save media via `col.media.write_data()` with deterministic filenames
- [x] Add `[sound:filename]` to front/back fields for TTS
- [x] Add `<img>` + attribution to back field for images
- [x] Two-layer dedup: field HTML check + `col.media.have()` check
- [x] All download failures return None silently (cards still get text enhancements)

**Test coverage**: 79/79 tests passing (at Phase 5 completion).

### Phase 6: Settings & Polish — ✅ COMPLETE

- [x] Settings dialog with 3 sections (generation defaults, enhancement defaults, API URL)
- [x] 7 validated config setters with `get_defaults()`
- [x] "Settings..." menu item in Tools menu (works without login)
- [x] Security hardening: `html.escape()` for `context_notes` and `image_attribution`
- [x] Batch size guard: truncate to 50 cards if >50 passed
- [x] Package builder (`tools/package.py` → `dist/flashcard-tools.ankiaddon`)

**Not implemented (deferred)**:
- Usage display widget (no `/usage/current` call)
- "Enhance on Review" feature (config flag exists, not wired up)

**Test coverage**: 98/98 tests passing, flake8 clean, mypy clean. Package builds (27 files, 33KB).

### Phase 7: CSS Styling & Furigana — 7a+7b+7c COMPLETE, 7d NOT STARTED

Structured, visually polished card output with `fc-*` CSS classes and Japanese furigana support. Touches both the backend (prompt output formatting) and the Anki add-on (CSS injection and note type handling). See root `CLAUDE.md` "Structured HTML Output Contract" for the class reference.

- **7a. Structured HTML output in prompts** — ✅ COMPLETE. All 10 domain generation and enhancement prompts output `fc-*` HTML (v1.3.0 generation, v2.0.0 hooks).
- **7b. Furigana in LANG domain** — ✅ COMPLETE. Per-kanji `<ruby>` annotations in generation and enhancement prompts.
- **7c. CSS stylesheet injection** — ✅ COMPLETE. `src/styles/stylesheet.py` with `FC_STYLESHEET`, idempotent injection/removal, styles dialog, auto-prompt after generate/enhance.
- **7d. Note type template support** — NOT STARTED. Optional: create a "Flashcard Tools" note type with pre-configured front/back templates.

#### Acceptance Criteria

- [x] Generated LANG cards display furigana above kanji in Anki reviewer
- [x] Enhanced cards have structured sections with semantic CSS classes
- [x] Default CSS stylesheet injected into Anki collection
- [x] Cards are visually structured with clear section headings
- [x] Example sentences visually distinct from definitions
- [x] Tags displayed as styled badges
- [ ] Cards render correctly on desktop Anki, AnkiDroid, and AnkiMobile (untested on mobile)
- [x] Existing (pre-Phase 7) cards continue to display correctly
- [x] Users can customize styles via Anki's template editor

## Commands

```bash
# Testing
pytest tests/ -v
pytest tests/ --cov=src --cov-report=html

# Linting
flake8 src/
mypy src/

# Packaging
python tools/package.py  # Outputs: dist/flashcard-tools.ankiaddon

# Install for development (symlink to Anki addons folder)
# Windows: mklink /J "%APPDATA%\Anki2\addons21\flashcard-tools" flashcard-anki
# macOS:   ln -s $(pwd)/flashcard-anki ~/Library/Application\ Support/Anki2/addons21/flashcard-tools
```

---

# PRD 3: Flashcard Tools Web App

```yaml
title: "Flashcard Tools Web App"
status: draft
priority: high
created: 2026-02-21
updated: 2026-02-21
owner: Luis
dependencies: ["Flashcard Tools Backend (Phase 5b Billing deployed)"]
estimated_effort: 25-35 hours
```

## Executive Summary

A React single-page application serving as the central hub for the Memogenesis ecosystem. Handles user signup, subscription billing (via Stripe), card generation and management, and client-side .apkg export. Also serves as the landing destination for the browser capture extension. Built with Vite and deployed as static assets on Cloudflare Workers — marketing pages are pre-rendered at build time for SEO; the authenticated app renders client-side.

## Problem Statement

Billing requires a URL. Users need somewhere to sign up, subscribe, and manage their account. Rather than building a disconnected billing portal, the web app becomes the full card generation and management experience outside of Anki — generate cards from pasted content, review and edit, organize into decks, and export as .apkg for Anki import. It also provides the card library: a persistent record of all generated cards, accessible across devices.

**Who needs this?** All Memogenesis users for billing and account management. Users who prefer a web-based workflow over the Anki add-on. Browser extension users who need a generation and export destination.

## Goals & Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Landing → signup conversion | > 5% | Cloudflare analytics |
| Generation → export completion | > 70% | Client-side event tracking |
| LCP (landing page) | < 2s | Lighthouse |
| Time to first card generated | < 30s from signup | Client-side timing |

## Technical Specifications

### Tech Stack

- **Build Tool**: Vite 6 + @cloudflare/vite-plugin
- **UI Library**: React 19
- **Routing**: React Router 7 (library mode — explicit route definitions)
- **Styling**: Tailwind CSS v4 + shadcn/ui
- **State**: Zustand (client-side working state)
- **Auth**: Supabase Auth (shared with backend — same Supabase project)
- **Payments**: Stripe Checkout (redirect) + Stripe Customer Portal
- **Export**: sql.js (WASM) + JSZip — client-side .apkg generation
- **Hosting**: Cloudflare Workers (static assets — SPA requests are free, no compute)
- **Testing**: Vitest (unit) + Playwright (e2e)

### Architecture

```
┌─────────────────────────────────────────────────┐
│          Cloudflare Workers (static assets)      │
│  ┌───────────────┐  ┌────────────────────────┐  │
│  │  Landing/Auth  │  │     App (SPA)          │  │
│  │  (pre-rendered │  │  Generate → Review →   │  │
│  │   at build)    │  │  Library → Export       │  │
│  └───────────────┘  └──────────┬─────────────┘  │
│  Served as static files from CDN — zero compute  │
└─────────────────────────────────┼────────────────┘
                                  │ API calls
                    ┌─────────────▼──────────────┐
                    │   Cloudflare Workers API    │
                    │  (existing flashcard-backend)│
                    │                             │
                    │  POST /cards/generate       │
                    │    → returns cards to client │
                    │    → writes to Supabase     │
                    │      via waitUntil()        │
                    │                             │
                    │  GET /cards                  │
                    │    → paginated card library  │
                    │                             │
                    │  Stripe billing routes       │
                    └─────────────┬──────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │        Supabase             │
                    │  users, usage_records,      │
                    │  generation_requests,       │
                    │  cards (new)                │
                    └────────────────────────────┘
```

**Data flow for card generation:**

1. Client sends content to `POST /cards/generate`
2. Backend calls Claude, receives cards (3-8s)
3. Backend sends HTTP response to client immediately
4. Backend writes cards to `cards` table via `ctx.executionContext.waitUntil()` (async, ~50ms, invisible to user)
5. Client displays cards from response in Zustand store
6. User edits/reviews locally (Zustand mutations — no server round-trips)
7. User exports: client packages Zustand state into .apkg via sql.js

**Data flow for card library (returning user):**

1. Client calls `GET /cards?page=1&limit=50`
2. Backend returns paginated cards from Supabase
3. Client displays in library view
4. User selects cards → local Zustand state → export

### Data Models

**New `cards` table in Supabase:**

```sql
CREATE TABLE cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  generation_request_id uuid REFERENCES generation_requests(id) ON DELETE SET NULL,
  front text NOT NULL,
  back text NOT NULL,
  card_type text NOT NULL CHECK (card_type IN ('basic', 'cloze')),
  tags text[] NOT NULL DEFAULT '{}',
  notes text NOT NULL DEFAULT '',
  source_quote text NOT NULL DEFAULT '',
  domain text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}',     -- Domain-specific metadata (lang_metadata, etc.)
  confidence_scores jsonb,                   -- { atomicity, self_contained }
  is_deleted boolean NOT NULL DEFAULT false, -- Soft delete for undo support
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS: users can only access their own cards
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cards_select_own" ON cards FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "cards_update_own" ON cards FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "cards_delete_own" ON cards FOR DELETE USING (auth.uid() = user_id);
-- Insert only via service role (backend writes via waitUntil)

-- Indexes
CREATE INDEX idx_cards_user_created ON cards (user_id, created_at DESC);
CREATE INDEX idx_cards_user_domain ON cards (user_id, domain);
CREATE INDEX idx_cards_generation_request ON cards (generation_request_id);
```

**Client-side state (Zustand):**

```typescript
interface CardStore {
  // Working state — cards currently being generated/reviewed/exported
  pendingCards: Card[];          // Cards from latest generation, pre-export
  selectedCardIds: Set<string>;  // Multi-select for bulk operations

  // Library state — fetched from server
  libraryCards: Card[];
  libraryPagination: { page: number; totalPages: number; totalCards: number };

  // Actions
  generateCards: (request: GenerateRequest) => Promise<void>;
  editCard: (id: string, updates: Partial<Card>) => void;
  deleteCard: (id: string) => void;
  selectCards: (ids: string[]) => void;
  exportSelectedAsApkg: (deckName: string) => Promise<Blob>;
  fetchLibrary: (page: number, filters?: CardFilters) => Promise<void>;
}

interface Card {
  id: string;
  front: string;
  back: string;
  card_type: 'basic' | 'cloze';
  tags: string[];
  notes: string;
  source_quote: string;
  domain: CardDomain;
  metadata: Record<string, unknown>;
  confidence_scores?: { atomicity: number; self_contained: number };
  created_at: string;
}

interface CardFilters {
  domain?: CardDomain;
  search?: string;              // Full-text search on front/back
  dateRange?: { from: string; to: string };
}
```

### New Backend Endpoints

These endpoints are added to the existing `flashcard-backend`:

**GET /cards** — Paginated card library

```typescript
// Query parameters
{
  page: number;                  // Default 1
  limit: number;                 // Default 50, max 100
  domain?: CardDomain;           // Filter by domain
  search?: string;               // Full-text search on front/back
  sort?: 'created_at' | 'domain'; // Default 'created_at'
  order?: 'asc' | 'desc';       // Default 'desc'
}

// Response (200)
{
  request_id: string;
  cards: Card[];
  pagination: {
    page: number;
    limit: number;
    total_cards: number;
    total_pages: number;
  };
}
```

**DELETE /cards/:id** — Soft delete a card

```typescript
// Response (200)
{ request_id: string; deleted: true; }

// Response (404) — card doesn't exist or belongs to another user
{ request_id: string; error: "Card not found"; code: "NOT_FOUND"; }
```

**DELETE /cards** — Bulk soft delete

```typescript
// Request
{ card_ids: string[]; }  // Max 100

// Response (200)
{ request_id: string; deleted_count: number; }
```

**Modification to existing POST /cards/generate:**

After returning the response, the handler writes generated cards to the `cards` table via `waitUntil()`:

```typescript
// In cards.ts route handler, after constructing the response:
const response = c.json(responseBody, 200);

ctx.executionContext.waitUntil(
  persistGeneratedCards(env, userId, generationRequestId, responseBody.cards)
);

return response;
```

This is the only code change to the existing generate flow. The response shape is unchanged — clients are unaffected.

### Billing Integration

The web app is the **only place** users interact with billing. All other clients (Anki add-on, extension, Android) show usage and link to the web app for subscription management.

**Flows:**

- **Signup (free):** Supabase Auth signup → user lands in app with 50 cards/month
- **Upgrade:** Click "Upgrade" → `POST /billing/checkout` → redirect to Stripe Checkout → success redirect back to app → webhook updates user tier
- **Manage subscription:** Click "Manage Billing" → `GET /billing/portal` → redirect to Stripe Customer Portal → return to app
- **Usage display:** `GET /usage/current` on app load → show cards remaining, tier, period end

No card details or payment information ever touches the web app. Stripe Checkout and Customer Portal handle all sensitive payment flows.

### Privacy & Legal Compliance

**Required before launch (Phase 1):**

- **Privacy Policy** page at `/privacy` — GDPR-compliant, disclosing: what data is collected (account info, generated card content, usage metrics), lawful basis (contract performance for card generation, legitimate interest for analytics), retention periods, third-party processors (Supabase, Stripe, Cloudflare, Anthropic, OpenAI, Unsplash), right to erasure, right to data export, DPO contact (Luis)
- **Terms of Service** page at `/terms`
- **Cookie banner** — minimal (Supabase auth cookies only, no tracking cookies for MVP)
- **Data Processing Agreement** with Supabase (they offer a standard DPA)
- **Right to erasure implementation:** `DELETE /account` endpoint that cascades: deletes all cards, usage records, generation requests, and Supabase Auth user. Stripe customer data retained per Stripe's requirements but subscription canceled.
- **Data export:** `GET /account/export` returns all user data as JSON (cards, usage records, account info)

**Content in the `cards` table:**

Users may generate cards from sensitive content (medical notes, personal journals, legal documents). The cards table stores AI-generated output, not raw source content (that's in `generation_requests.source_content`, which already exists and has the same GDPR exposure). The privacy policy must disclose that generated card content is stored server-side and used for service improvement. Users who want no server-side storage should use the Anki add-on (which stores cards only in local Anki database).

### .apkg Export (Client-Side)

No `POST /export/cards` endpoint needed. The client already has card data (from generation response or library fetch). Export flow:

1. User selects cards + enters deck name
2. Client loads sql.js WASM (~1MB, cached after first load)
3. Client creates SQLite database in memory with Anki schema (notes, cards, col tables)
4. Client packages as .zip with JSZip (Anki .apkg = renamed .zip containing SQLite DB + media)
5. Browser triggers download of `{deckName}.apkg`

Reference implementation: `flashcard-backend/docs/spikes/apkg-code/`

Media handling: TTS audio and images referenced in cards are URLs. The .apkg can either embed them (download → include in zip) or leave as URL references. For MVP, leave as URLs — Anki will fetch them on first review. Phase 5 can add media embedding if users request it.

## Project Structure

```
flashcard-web/
├── index.html                      # SPA entry point (minimal shell)
├── public/
│   ├── sql-wasm.wasm              # sql.js WASM binary
│   ├── landing.html               # Pre-rendered landing page (built at deploy)
│   ├── pricing.html               # Pre-rendered pricing page
│   ├── privacy.html               # Pre-rendered privacy policy
│   └── terms.html                 # Pre-rendered terms of service
├── src/
│   ├── main.tsx                    # React entry point, router setup
│   ├── App.tsx                     # Root component, route definitions
│   ├── routes/
│   │   ├── Landing.tsx             # Landing page (also pre-rendered as static HTML)
│   │   ├── Pricing.tsx             # Pricing display
│   │   ├── Privacy.tsx             # Privacy policy
│   │   ├── Terms.tsx               # Terms of service
│   │   ├── Login.tsx
│   │   ├── Signup.tsx
│   │   └── app/                    # Authenticated routes (auth guard wrapper)
│   │       ├── AppLayout.tsx       # App shell: sidebar nav, auth guard
│   │       ├── Generate.tsx        # Card generation form + review
│   │       ├── Library.tsx         # Card library (paginated, filterable)
│   │       ├── Export.tsx          # Deck builder + .apkg export
│   │       ├── Billing.tsx         # Usage, plan, upgrade/manage
│   │       └── Settings.tsx        # Account settings, data export, delete account
│   ├── components/
│   │   ├── ui/                     # shadcn/ui components
│   │   ├── marketing/              # Landing page sections
│   │   ├── cards/
│   │   │   ├── GenerateForm.tsx    # Domain selector, language selector (LANG), options
│   │   │   ├── CardReview.tsx      # Review/edit generated cards
│   │   │   ├── CardList.tsx        # Card library list with filters
│   │   │   └── CardEditor.tsx      # Single card inline editor
│   │   ├── export/
│   │   │   ├── DeckBuilder.tsx     # Select cards, name deck
│   │   │   └── ApkgExporter.tsx    # sql.js WASM packaging + download trigger
│   │   └── billing/
│   │       ├── UsageDisplay.tsx    # Cards remaining, period, tier badge
│   │       ├── PlanCard.tsx        # Plan comparison
│   │       └── UpgradeModal.tsx    # Shown when usage exceeded (free tier)
│   ├── lib/
│   │   ├── api.ts                  # Backend API client (fetch wrapper with auth)
│   │   ├── supabase.ts            # Supabase browser client
│   │   ├── apkg/
│   │   │   ├── builder.ts          # sql.js + JSZip .apkg generator
│   │   │   └── schema.ts           # Anki SQLite schema constants
│   │   └── hooks/
│   │       ├── useAuth.ts          # Auth state + token refresh
│   │       ├── useCards.ts         # Card store hook
│   │       └── useUsage.ts        # Usage/billing state
│   └── stores/
│       ├── cards.ts                # Zustand card store
│       └── settings.ts             # User preferences
├── scripts/
│   └── prerender.ts               # Build script: renders marketing pages to static HTML
├── vite.config.ts
├── wrangler.jsonc                  # Cloudflare Workers config (6 lines)
├── tailwind.config.ts
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── playwright.config.ts
└── tests/
    ├── unit/
    └── e2e/
```

## Boundaries

### ✅ Always
- Pre-render marketing pages (landing, pricing, privacy, terms) as static HTML at build time — SEO
- Client-side rendering for `/app/*` routes — interactivity
- All API calls include `product_source: 'web_app'`
- Client-side .apkg generation (no server-side SQLite)
- Responsive design: works on mobile browsers (minimum 320px)
- Stripe Checkout for payments (never handle card details)
- Sanitize all user-provided content before rendering (XSS prevention)
- Auth guard on all `/app/*` routes — redirect to login if unauthenticated
- Show usage remaining on every generation action

### ⚠️ Ask First
- Adding a backend Worker to the web app (prefer using existing backend)
- Adding third-party analytics or tracking scripts
- Changing Stripe plan structure or pricing

### 🚫 Never
- Handle credit card details (Stripe Checkout only)
- Store auth tokens in localStorage (use Supabase session management)
- Generate .apkg server-side
- Add server-side state that duplicates the backend
- Track users without consent (no analytics cookies without opt-in)

## Implementation Phases

### Phase 1: Project Setup, Auth & Legal Pages (4-5 hours)

**Objectives:** Deployed web app with auth flow, landing page, and legal compliance pages.

**Requirements:**
1. Initialize Vite + React 19 + TypeScript project with Cloudflare Vite plugin
2. Install and configure React Router 7 (library mode), Tailwind CSS v4, shadcn/ui
3. Configure Cloudflare Workers deployment (`wrangler.jsonc` with `not_found_handling: "single-page-application"`)
4. Configure Supabase Auth (shared project with backend)
5. Landing page: hero section with value proposition, feature highlights, CTA to signup
6. Pricing page: free tier details, Pro/Power tier cards with pricing, CTA to signup
7. Privacy policy page (GDPR-compliant, covering all data processing)
8. Terms of service page
9. Pre-render script: marketing pages built as static HTML files with OG meta tags for SEO + social sharing
10. Login/signup pages using Supabase Auth (email + password for MVP)
11. Authenticated app layout with sidebar navigation (Generate, Library, Export, Billing, Settings)
12. Auth guard component wrapping `/app/*` routes — redirect to login if unauthenticated
13. Custom domain configuration

**Backend prerequisite:** Phase 5b billing migration must be deployed to production (so pricing page reflects real tiers and signup flow works end-to-end).

**Acceptance criteria:**
- [ ] Landing page loads with < 2s LCP
- [ ] Signup → email verification → login flow works
- [ ] Authenticated users see app layout with sidebar
- [ ] Unauthenticated users redirected to login
- [ ] Privacy policy and terms accessible from footer on all pages
- [ ] Deployed to production URL on Cloudflare Workers

### Phase 2: Card Generation & Review (5-7 hours)

**Objectives:** Full generate → review → local editing workflow.

**Requirements:**
1. Generation form: content textarea (paste or type), domain selector dropdown (10 domains)
2. LANG domain: additional language selector (Japanese, Chinese, Korean, Hindi, Arabic, Other) mapping to `hook_key` parameter
3. Card style selector (basic/cloze/mixed), difficulty (beginner/intermediate/advanced), max cards slider (1-50)
4. Call `POST /cards/generate` with `product_source: 'web_app'` and loading state (streaming-friendly skeleton UI)
5. Review panel: card list with inline editing of front, back, tags, notes
6. Delete individual cards from review
7. Domain-specific metadata display (LANG: reading, JLPT level, register; MED: clinical pearl; etc.)
8. Usage counter in sidebar or header (cards remaining in period)
9. Error handling: USAGE_EXCEEDED → upgrade modal, RATE_LIMITED → toast with retry, VALIDATION_ERROR → inline field errors
10. Extension handoff: parse URL query params (`?content=...&source_url=...&source_title=...&domain=...`) into pre-filled generation form

**Backend prerequisite:** None beyond Phase 5b. Existing `POST /cards/generate` already returns everything needed. The `waitUntil()` card persistence is added as part of this phase (small backend change).

**Backend changes in this phase:**
- Add `cards` table migration to Supabase
- Add `waitUntil()` card persistence in `POST /cards/generate` handler
- Add `GET /cards` endpoint (paginated, filtered)
- Add `DELETE /cards/:id` and `DELETE /cards` (bulk) endpoints

**Acceptance criteria:**
- [ ] Can generate cards from pasted text for all 10 domains
- [ ] LANG domain shows language selector, correctly passes `hook_key`
- [ ] Cards are editable inline (front, back, tags)
- [ ] Usage counter updates after generation
- [ ] Free tier exhaustion shows upgrade modal
- [ ] URL with `?content=...` pre-fills the generation form
- [ ] Generated cards appear in the cards table (verify via Supabase dashboard)

### Phase 3: Card Library & Management (4-6 hours)

**Objectives:** Persistent card library with filtering, search, and organization.

**Requirements:**
1. Library page: paginated card list fetched from `GET /cards`
2. Filters: domain dropdown, date range picker, free-text search
3. Sort: by creation date (default, newest first) or by domain
4. Card detail view: click to expand, showing all fields including metadata
5. Bulk selection: checkbox per card, "Select all on page", bulk delete
6. Individual card deletion with undo (soft delete → hard delete after 30s)
7. Responsive card grid/list toggle
8. Empty state for new users ("Generate your first cards →" CTA)

**Acceptance criteria:**
- [ ] Library loads paginated cards from server
- [ ] Search finds cards by front/back content
- [ ] Domain filter works
- [ ] Bulk delete works with undo
- [ ] Pagination controls work (next/prev/jump to page)
- [ ] Empty state shown for users with no cards

### Phase 4: Export & Billing (5-7 hours)

**Objectives:** Client-side .apkg export and full billing integration.

**Requirements — Export:**
1. Export page: select cards from library or pending generation
2. Deck name input with validation
3. Card type preview (basic vs cloze count)
4. "Export as .apkg" button → sql.js WASM loads → builds SQLite DB → JSZip packages → browser download
5. Export progress indicator (for large decks)
6. Tag filtering for export (export only cards with specific tags)

**Requirements — Billing:**
1. Billing page: current plan badge, usage bar (cards used / limit), period end date
2. Overage display for paid tiers (cards beyond limit, estimated cost)
3. "Upgrade" button → `POST /billing/checkout` → redirect to Stripe Checkout
4. "Manage Billing" button → `GET /billing/portal` → redirect to Stripe Customer Portal
5. Usage data from `GET /usage/current` refreshed on page load and after each generation
6. Upgrade modal (triggered by USAGE_EXCEEDED on free tier): plan comparison, upgrade CTA
7. Subscription inactive banner (triggered by USAGE_EXCEEDED with `reason: 'subscription_inactive'`)

**Acceptance criteria:**
- [ ] Can export 10 cards as .apkg, file opens in Anki desktop
- [ ] Can export 50 cards as .apkg without browser hanging
- [ ] Billing page shows correct tier, usage, and period
- [ ] Upgrade flow: click upgrade → Stripe Checkout → success redirect → tier updated
- [ ] Manage billing: click → Customer Portal → return to app
- [ ] Free tier user hitting limit sees upgrade modal with plan options

### Phase 5: Settings, Account Management & Polish (3-5 hours)

**Objectives:** Account lifecycle management, GDPR compliance features, and UX polish.

**Requirements — Account:**
1. Settings page: email display, password change (via Supabase Auth)
2. Data export: "Download my data" → `GET /account/export` → JSON download
3. Account deletion: "Delete account" with confirmation dialog → `DELETE /account` → cascades all data → redirect to landing
4. Default generation preferences (domain, card style, difficulty) saved to Supabase user metadata or localStorage

**Requirements — Polish:**
1. Dark mode toggle (system/light/dark)
2. Loading skeletons for all async operations
3. Error boundaries with friendly fallback UI
4. Keyboard shortcuts: Ctrl+Enter to generate, Ctrl+E to export
5. Mobile responsive pass (test at 320px, 375px, 768px)
6. Lighthouse audit: aim for 90+ on performance, accessibility, SEO
7. Open Graph meta tags for social sharing
8. 404 page

**GDPR compliance features:**
1. Cookie consent banner (minimal — only functional cookies for MVP)
2. Privacy policy link in signup flow ("By signing up, you agree to our Privacy Policy and Terms")
3. Data export endpoint returns complete user data
4. Account deletion cascade fully purges user data

**Acceptance criteria:**
- [ ] Data export downloads JSON with all user cards and account info
- [ ] Account deletion removes all data and redirects to landing
- [ ] Dark mode works across all pages
- [ ] Lighthouse performance > 90 on landing page
- [ ] Mobile layout works at 320px width
- [ ] Cookie consent banner shown on first visit

## Commands

```bash
npm run dev                      # Vite dev server (runs in Workers runtime via CF plugin)
npm run build                    # Production build (Vite + pre-render marketing pages)
npm run preview                  # Preview production build locally in Workers runtime
npm run deploy                   # wrangler deploy
npm run test                     # Vitest
npm run test:e2e                 # Playwright
npm run lint                     # ESLint
npm run typecheck                # tsc --noEmit
```

## Cloudflare Workers Configuration

The app deploys as static assets on Cloudflare Workers using the Cloudflare Vite plugin. No adapter, no translation layer — Vite builds the React SPA and Cloudflare serves the output files from its CDN.

**`wrangler.jsonc`:**
```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "memogenesis-web",
  "compatibility_date": "2025-04-01",
  "assets": {
    "not_found_handling": "single-page-application"
  }
}
```

**`vite.config.ts`:**
```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  plugins: [react(), tailwindcss(), cloudflare()],
});
```

Key properties:
- **`not_found_handling: "single-page-application"`**: Non-asset requests return `index.html` so React Router handles client-side routing. This means `/app/generate` doesn't 404 — it loads the SPA shell and React Router renders the Generate page.
- **Static asset requests are free**: No Worker compute is invoked for serving the built JS/CSS/HTML files. Only API calls to the separate backend Worker incur compute costs.
- **Environment variables**: Baked into the build via Vite's `import.meta.env` (prefix with `VITE_`). Set `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL` in `.env.production`.
- **Pre-rendered marketing pages**: Built as static `.html` files in `public/` during the build step. Cloudflare serves these directly for `/landing.html`, `/pricing.html`, etc. The root `index.html` can redirect `/` to the landing page or serve it inline.

### SEO Strategy for Marketing Pages

Marketing pages (landing, pricing, privacy, terms) need complete HTML with meta tags for search engines and social sharing previews. Two approaches:

**Option A (simpler):** Write marketing pages as plain HTML files in `public/` with full `<head>` meta tags. These are static content that changes only on deploy. Link to the SPA (`/app/generate`) for authenticated flows.

**Option B (DRY):** Use a build-time pre-render script (`scripts/prerender.ts`) that renders the React marketing page components to static HTML using `react-dom/server.renderToString()`. This keeps marketing content in React components (shared with SPA navigation) while producing static HTML for crawlers.

Option A is recommended for launch. Option B is a refinement if maintaining marketing content in two places becomes painful.

---

# PRD 4: Browser Capture Extension

```yaml
title: "Browser Capture Extension"
status: draft
priority: medium
created: 2026-02-21
updated: 2026-02-21
owner: Luis
dependencies: ["Flashcard Tools Web App (Phase 2+)"]
estimated_effort: 8-12 hours
```

## Executive Summary

A lightweight cross-browser extension that captures selected text from any webpage and hands it off to the Memogenesis web app for card generation. The extension is purely a capture mechanism — all generation, management, and export happens in the web app.

## Problem Statement

When reading articles or study material online, users want to capture text for flashcard generation without manually copy-pasting. The extension provides a one-click flow: select text → click → land in the web app with content pre-filled.

## Technical Specifications

### Tech Stack
- **Framework**: WXT (WebExtension framework)
- **UI**: Preact + Tailwind (minimal popup)
- **Build**: Vite (via WXT)
- **Testing**: Vitest

### Architecture

```
Content Script (selection detection)
    → floating "Create Cards" button
    → opens web app URL with query params

Popup (optional)
    → quick domain selector
    → "Open Memogenesis" link
    → login status indicator
```

The extension makes **zero API calls**. It constructs a URL and opens it:

```
https://app.memogenesis.com/app/generate?content={encodedText}&source_url={pageUrl}&source_title={pageTitle}&domain={selectedDomain}
```

### Data Flow

1. User selects text on any webpage
2. Floating button appears near selection
3. User clicks button (or uses Ctrl+Shift+F)
4. Extension opens web app in new tab with URL params
5. Web app parses params, pre-fills generation form
6. User completes generation in web app

No auth, no tokens, no API calls in the extension. The web app handles everything.

### Content Size Handling

URL query params have practical limits (~2KB for safe cross-browser compatibility). For selections exceeding 2KB:

1. Extension stores content in `browser.storage.local` with a unique key
2. Opens web app with `?capture_key={key}` instead of inline content
3. Web app uses a small companion script (injected via content script messaging) to retrieve the content
4. Alternatively: extension copies to clipboard and web app offers "Paste from clipboard" button

For MVP, limit to 2KB URL params. Add storage-based handoff in Phase 2 if users frequently hit the limit.

## Project Structure

```
flashcard-extension/
├── src/
│   ├── entrypoints/
│   │   ├── content.ts          # Selection detection + floating button
│   │   └── popup/
│   │       ├── index.html
│   │       └── App.tsx         # Domain picker + web app link
│   ├── components/
│   │   └── FloatingButton.tsx
│   └── utils/
│       ├── selection.ts        # Text extraction from selection
│       └── url.ts              # Web app URL construction
├── wxt.config.ts
├── tailwind.config.ts
├── package.json
└── tests/
```

## Boundaries

### ✅ Always
- Open the web app for all processing (never call backend API directly)
- Preserve source URL and page title in handoff
- Work without login (web app handles auth)
- Respect content scripts restrictions (no injection on browser internal pages)

### 🚫 Never
- Store user credentials
- Make API calls to the backend
- Generate cards within the extension
- Track browsing behavior

## Implementation Phases

### Phase 1: Core Capture (4-5 hours)
WXT project setup, content script with selection detection, floating button near selection, keyboard shortcut (Ctrl+Shift+F), URL construction with params, open web app in new tab, basic popup with "Open Memogenesis" link.

### Phase 2: Enhanced Capture (3-4 hours)
Domain pre-selector in popup, smart content extraction (tables, code blocks, structured content preserved), large content handoff (>2KB), page context extraction (nearby headings as topic hints), cross-browser testing (Chrome, Firefox, Edge), store submission packaging.

### Phase 3: Polish (1-3 hours)
Extension icon and branding, onboarding page (shown on install, explains the flow), options page (web app URL override for self-hosted), dark mode support matching system preference.

## Commands

```bash
npm run dev              # Chrome dev mode with HMR
npm run dev:firefox      # Firefox dev mode
npm run build            # Production build (all browsers)
npm run zip              # Create .zip for store submission
npm run test             # Vitest
```

---

# Cross-Product Considerations

## Ecosystem Architecture

```
                    ┌──────────────────────┐
                    │    Memogenesis        │
                    │    Web App (hub)      │
                    │                       │
                    │  • Billing & account  │
                    │  • Card generation    │
                    │  • Card library       │
                    │  • .apkg export       │
                    └──────────┬───────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                 │
    ┌─────────▼──────┐ ┌──────▼───────┐ ┌──────▼───────┐
    │  Browser Ext   │ │  Anki Add-on │ │  Mobile Apps │
    │  (capture →    │ │  (standalone  │ │  (future,    │
    │   web app)     │ │   generate +  │ │   gated)     │
    │                │ │   enhance)    │ │              │
    └────────────────┘ └──────┬───────┘ └──────────────┘
                              │
                    ┌─────────▼──────────┐
                    │  Cloudflare Workers │
                    │  Backend API        │
                    │                     │
                    │  All clients call   │
                    │  the same API       │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  Supabase + Stripe  │
                    │  + R2 + Claude      │
                    └────────────────────┘
```

The web app is the central hub. The Anki add-on is the exception — it's a standalone client that generates, enhances, and inserts cards directly into Anki without touching the web app. The browser extension is a thin capture shim that opens the web app. Mobile apps (future) would follow the extension pattern: capture via share sheet → open web app or generate locally.

## Shared Backend Endpoints

| Endpoint | Web App | Anki | Extension | Android |
|----------|---------|------|-----------|---------|
| `/auth/*` | ✓ | ✓ | | ✓ |
| `/cards/generate` | ✓ | ✓ | | ✓ |
| `/cards/enhance` | ✓ (future) | ✓ | | |
| `/cards` (library) | ✓ | | | ✓ |
| `/assets/tts`, `/assets/image` | ✓ (future) | ✓ | | |
| `/usage/current` | ✓ | ✓ | | ✓ |
| `/billing/*` | ✓ | | | |

The browser extension makes **no API calls** — it opens the web app with URL params.

## Account & Billing Unity

Single account across all products. Free tier: 50 cards/month unified across ecosystem. `product_source` field enables per-product analytics. Billing UI lives exclusively in the web app; all other clients show usage and link to the web app for subscription management.

## .apkg Generation Strategy

| Client | Method | Notes |
|--------|--------|-------|
| Web App | sql.js (WASM) + JSZip in browser | Client-side, from Zustand state |
| Anki Add-on | Direct note insertion via Anki API | No .apkg needed |
| Browser Extension | N/A — delegates to web app | No card handling |
| Android App (future) | sql.js or native SQLite | From local state |

## Development Dependencies & Build Order

```
Backend API (Phases 1-4 ✅, 5b billing)
    → Anki Add-on (Phases 1-6 ✅, Phase 7 optional)
    → Web App (new — the hub)
        → Browser Extension (thin capture shim)
        → Mobile Apps (gated on demand data)
```

## Phase Gates

**Gate 1 (After Backend Phase 2)** ✅ Passed.

**Gate 2 (After Anki Add-on Phase 6)** ✅ Passed. Enhance 50+ cards from actual decks. AI suggestions confirmed useful.

**Gate 3 (After Web App Phase 4)**: Full generate → library → export flow working. Web app is self-sufficient. Go/no-go on browser extension.

**Gate 4 (After Browser Extension Phase 1 + 1 month usage)**: Are users trying to capture from mobile? Is the web app's responsive design sufficient, or do they need native share sheet? Go/no-go on mobile apps.

## Testing Strategy

| Layer | Backend | Anki | Web App | Extension |
|-------|---------|------|---------|-----------|
| Unit | Vitest | Pytest | Vitest | Vitest |
| Integration | Vitest + Supabase | Manual in Anki | Vitest + MSW | N/A |
| E2E | Smoke tests | Manual | Playwright | Manual |

## Estimated Total Effort

| Product | Hours | Status |
|---------|-------|--------|
| Backend (Phases 1-4) | 20-27 | ✅ Complete |
| Backend (Phase 5b Billing) | 6-8 | Code written, migration pending |
| Backend (Phase 7 CSS/Furigana) | 3-5 | ✅ 7a+7b complete |
| Backend (cards table + endpoints) | 2-3 | Web App Phase 2 prerequisite |
| Anki Add-on (Phases 1-6) | 15-19 | ✅ Complete |
| Anki Add-on (Phase 7 CSS/Furigana) | 3-5 | 7c complete, 7d not started |
| **Web App** | **25-35** | **Next priority** |
| Browser Extension | 8-12 | After web app |
| Android App | 18-22 | Gated on Gate 4 |
| **Total (through web app)** | **~75-100** | |

## Future Considerations

### Mobile Apps (Android + iOS)

Native apps using Expo (React Native) providing share sheet capture from mobile browsers and other apps. Cards generated via backend API, exported as .apkg for AnkiDroid/AnkiMobile. Gated on Gate 4 demand data. Estimated 25-35 hours for both platforms (shared codebase).

### iOS App

An iOS companion using the same Expo codebase. Would provide share sheet capture from Safari and other iOS apps. Gated on Gate 4 demand data and Android app validation. Estimated 10-15 hours incremental effort over Android (shared codebase, platform-specific share sheet and AnkiMobile integration, App Store submission).

---
*Last updated: 2026-02-21*
*Changes: Documentation audit — removed stale duplicate sections. Slimmed Phase 5b and Phase 7. Updated statuses throughout. Renamed "Updated Cross-Product Section".*

