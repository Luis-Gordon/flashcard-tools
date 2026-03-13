# Flashcard Tools Ecosystem — Product Requirements Document

This document contains four PRDs for a suite of AI-powered flashcard tools sharing a common backend. Build in sequence: Backend → Anki Add-on → Browser Extension → Android App.

> **Scope**: Product specification — feature inventory, API contracts, data models, error codes, billing tiers, domain rules, and acceptance criteria for incomplete phases.
>
> **Not here**: Config files, directory trees, commands, code samples, implementation notes ("used X instead of Y"). These live in each sub-project's `CLAUDE.md`, `README`, or `docs/architecture.md`.
>
> **Style**: Completed phases get a brief summary of what was built. Incomplete phases keep full requirements and acceptance criteria.

---

# PRD 1: Flashcard Tools Backend

```yaml
title: "Flashcard Tools Backend"
status: active
priority: critical
created: 2025-01-26
updated: 2026-03-02
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

Each domain has generation and enhancement hooks at `promptVersion: '2.0.0'`. See **Prompt Architecture** below. A generic fallback enhancement prompt (`enhance-v1.2.0.ts`) handles unknown domains. All generation prompts share common quality gates: confidence scoring (atomicity, self-containment), unsuitable content filtering, and source quote attribution. All enhancement prompts share smart triage logic (skip enhancements when cards are already well-formed, with specific reasons).

### Prompt Architecture

The backend uses a composable **hook-based prompt architecture** (`promptVersion: '2.0.0'`). Each generation request is assembled from:

1. **Master base** (`hooks/master-base.ts`) — universal SRS rules, quality gates, output format
2. **Domain hook** (`hooks/{domain}/{domain}-domain-hook.ts`) — domain-specific rules, card types, metadata schema, few-shot examples
3. **Optional sub-hook** — specialization within a domain, selected via `hook_key` request parameter

Sub-hooks exist for 5 domains (13 sub-hooks total):

| Domain | Sub-hooks | `hook_key` values |
|--------|-----------|-------------------|
| LANG | Japanese, Chinese, Korean, Russian, Arabic, Default CEFR | `ja`, `zh`, `ko`, `ru`, `ar`, `default` |
| MED | Pharmacology, Pathology, Anatomy | `pharmacology`, `pathology`, `anatomy` |
| ARTS | Music Theory | `music-theory` |
| FIN | Exam Prep | `exam-prep` |
| STEM-M | Statistics, Proofs | `statistics`, `proofs` |

Enhancement prompts use a parallel hook system (`hooks/master-enhance-base.ts` + per-domain `{domain}-enhance-hook.ts`) with ~25 injection points. No sub-hooks for enhancement.

Monolithic prompt files (`generation/{domain}-v1.2.0.ts`, `enhancement/enhance-{domain}-v1.2.0.ts`) are preserved as reference — constants and few-shot examples are still imported by hooks.

### Directive Mode

When `content_type: 'prompt'`, the backend generates cards from expert knowledge based on a topic directive rather than extracting facts from source content. The content field contains the directive (e.g., "Common JLPT N2 grammar patterns" or "Key pharmacology drug interactions"). Behavioral differences from text/url/pdf mode:

- No source document — `source_quote` is set to empty string for all cards
- Uses `DIRECTIVE_FIDELITY_RULE` instead of `SOURCE_FIDELITY_RULE` (cards draw from established knowledge, not a specific source)
- `user_guidance` is ignored (the directive content IS the guidance)
- Minimum content length: 10 characters (same as text mode)
- Supported across all 10 domains with per-domain user message formatting

Client support: web app (toggle in GenerateForm), Anki add-on (not yet — see PRD 2 Planned Features).

### Multi-Language Support

The backend supports per-request language configuration via BCP-47 codes. Resolution chain for language context:

1. **Per-request** `source_language` / `output_language` fields (highest priority)
2. **Per-user** `user_language` preference stored in the `users` table (fallback)
3. **Default** `'en'` (final fallback)

For LANG domain: `source_language` determines the source/explanation language for bidirectional cards. For non-LANG domains: `detectContentLanguage()` identifies the content language and a language instruction is injected into the prompt when content or output language differs from English.

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
  subscription_tier: string;            // 'free' | 'plus' | 'pro'
  subscription_status: string;          // 'active' | 'past_due' | 'canceled' | 'unpaid'
  stripe_subscription_id: string | null;
  stripe_price_id: string | null;
  subscription_period_start: string | null; // ISO8601 — billing period start
  subscription_period_end: string | null;   // ISO8601 — billing period end
  cards_limit_monthly: number;          // 50 (free), 500 (plus), 2000 (pro)
  overage_rate_cents: number;           // 0 (free), 2 (plus), 2 (pro)
  free_cards_used: number;              // Legacy — deprecated by subscription-aware usage counting
  free_cards_reset_at: string;          // Legacy — deprecated by subscription_period_start
  user_language: string;                // BCP-47, default 'en' — fallback for source/output language
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
  content_type: 'text' | 'url' | 'pdf' | 'prompt';
  domain: string;                // Domain slug (e.g., 'lang', 'med')
  content_size_bytes: number;
  source_content_hash: string;   // SHA256 hash, not raw content
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
| `/health` | GET | Health check | None |
| `/health/ready` | GET | Supabase connectivity check | None |
| `/auth/signup` | POST | Create account | None |
| `/auth/login` | POST | Get session token | None |
| `/auth/refresh` | POST | Refresh token | None |
| `/auth/me` | GET | Get authenticated user profile | Required |
| `/cards/generate` | POST | Generate flashcards from content | Required |
| `/cards/enhance` | POST | Enhance existing cards | Required |
| `/cards` | GET | Paginated card library with filters | Required |
| `/cards/:id` | PATCH | Update card fields | Required |
| `/cards/:id` | DELETE | Soft delete single card | Required |
| `/cards` | DELETE | Bulk soft delete (up to 100) | Required |
| `/assets/tts` | POST | Generate audio for text | Required |
| `/assets/tts/:cacheKey` | GET | Retrieve cached TTS audio | Required |
| `/assets/image` | POST | Search and return image | Required |
| `/account` | DELETE | GDPR account deletion (cascade all data) | Required |
| `/account/export` | GET | GDPR data export (full JSON) | Required |
| `/usage/current` | GET | Current billing period usage and subscription status | Required |
| `/billing/portal` | GET | Stripe Customer Portal URL | Required |
| `/billing/checkout` | POST | Create Stripe Checkout session for new subscription | Required |
| `/billing/webhook` | POST | Stripe webhook handler | Stripe signature |

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
  content_type: 'text' | 'url' | 'pdf' | 'prompt';
  domain: 'lang' | 'general' | 'med' | 'stem-m' | 'stem-cs' | 'fin' | 'law' | 'arts' | 'skill' | 'mem';
  product_source: 'anki_addon' | 'web_app' | 'browser_extension' | 'android_app' | 'api';
  options: {
    max_cards: number;          // Default 10, max 50
    card_style: 'basic' | 'cloze' | 'mixed';
    difficulty: 'beginner' | 'intermediate' | 'advanced';
    include_context: boolean;
  };
  hook_key?: string;             // Sub-hook selector (e.g., 'ja', 'pharmacology')
  user_guidance?: string;        // Free-text steering (max 500 chars, appended to prompt). Ignored in directive mode.
  source_language?: string;      // BCP-47 source content language (e.g., 'ja', 'en'). Falls back to user_language, then 'en'.
  output_language?: string;      // BCP-47 output/explanation language. Falls back to user_language.
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

**POST /export/cards** — Superseded. Client-side .apkg generation makes this endpoint unnecessary. See Web App § .apkg Export.

**GET /usage/current** *(Phase 5b)*
```typescript
// Response (200)
{
  request_id: string;
  tier: 'free' | 'plus' | 'pro';
  status: 'active' | 'past_due' | 'canceled' | 'unpaid';
  period: {
    start: string;               // ISO8601
    end: string | null;          // null for free tier
  };
  usage: {
    cards_generated: number;
    cards_limit: number;
    cards_remaining: number;     // max(0, limit - generated)
    overage_cards: number;       // cards beyond limit (plus/pro only)
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
  tier: 'plus' | 'pro';
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

| Limit Type | Free | Plus | Pro | Scope |
|------------|------|------|-----|-------|
| Per-user requests | 10/min | 10/min | 10/min | All authenticated endpoints |
| Per-user generation | 20/hour | 100/hour | 200/hour | `/cards/generate` only |
| Per-user daily ops | 100/day | 500/day | 1,000/day | All card operations |

Global DDoS protection is handled at the Cloudflare edge layer, not in application code.

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

OpenAI TTS service with R2 caching (SHA256 key), `/assets/tts` + `/assets/tts/:cacheKey` endpoints, Unsplash image search with attribution, TTS/images integrated into `/cards/enhance` flow (parallel processing), `image_search_query` in all enhancement prompts.

### Phase 5a: Card Export Endpoint — POSTPONED

Postponed until browser extension/Android app need it. Anki add-on uses direct note insertion. Returns structured JSON for client-side .apkg generation (server-side not viable in Workers).

### Phase 5b: Billing Integration — ✅ COMPLETE

Subscription billing with Stripe: free/plus/pro tiers, overage reporting, webhook-driven state sync. All migrations applied to production.

| Tier | Slug | Price | Cards/month | Overage |
|------|------|-------|-------------|---------|
| Free | `free` | €0 | 50 | Blocked (upgrade required) |
| Plus | `plus` | €9/month | 500 | €0.02/card |
| Pro | `pro` | €29/month | 2,000 | €0.015/card |

Card count = generation actions only. All tiers include generation, enhancement, TTS, and image features. See `docs/billing-spec.md` for full implementation spec.

### Phase 6: Card Library & Account Management — ✅ COMPLETE

Card persistence and CRUD endpoints for the web app, plus GDPR account lifecycle. All deployed to production.

- [x] `cards` table migration with RLS, indexes, updated_at trigger
- [x] `waitUntil()` card persistence in POST /cards/generate
- [x] GET /cards — paginated library with domain/search/sort filters
- [x] PATCH /cards/:id — update card fields
- [x] DELETE /cards/:id — soft delete single card
- [x] DELETE /cards (bulk) — soft delete up to 100 cards
- [x] DELETE /account — GDPR account deletion, cascades all data
- [x] GET /account/export — GDPR data export (full JSON)

### Phase 7: CSS Styling & Furigana — 7a+7b COMPLETE, 7c+7d see PRD 2

Structured HTML output with `fc-*` CSS classes across all 10 domains. Furigana in LANG domain. Backend work complete (7a+7b). See PRD 2 Phase 7 for add-on status.

---

# PRD 2: Anki Flashcard Add-on

```yaml
title: "Anki Flashcard Add-on"
status: active
priority: high
created: 2025-01-26
updated: 2026-02-28
owner: Luis
dependencies: ["Flashcard Tools Backend"]
estimated_effort: 15-19 hours (Phases 1-6 + 7c done, audit hardened)
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

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/auth/login` | POST | Initial authentication |
| `/auth/refresh` | POST | Token renewal (transparent 401→refresh→retry + proactive 30s expiry check) |
| `/auth/me` | GET | Verify auth status |
| `/cards/generate` | POST | Generate cards from content (domain, hook_key, user_guidance, source_language, output_language, content_type: prompt supported) |
| `/cards/enhance` | POST | Enhance existing cards (with `domain` parameter) |
| `/assets/tts` | POST | Individual TTS generation |
| `/assets/tts/:cacheKey` | GET | Stream cached TTS audio (authenticated) |
| `/assets/image` | POST | Image search |
| `/usage/current` | GET | Display usage in UI |

All API calls include `product_source: 'anki_addon'`.

## Boundaries

### ✅ Always
- Preserve original card content (enhancements are additive)
- Handle network failures gracefully with retry option
- Show progress for batch operations
- Cache auth tokens in Anki's config (plain-text JSON)
- Support undo for all operations via `mw.checkpoint()`
- Include `product_source: 'anki_addon'` in all API requests
- Sanitize user-provided text with `html.escape()` before injecting into card HTML

### ⚠️ Ask First
- Modifying note types (templates)
- Batch operations on > 50 cards (hard limit enforced)

### 🚫 Never
- Store passwords (only tokens)
- Modify cards without user confirmation
- Block the main thread during API calls (downloads run on background thread; only `save_media_file()` + `col.update_note()` on main thread)

## Implementation Phases

### Phase 1: Project Setup & Auth — ✅ COMPLETE

- [x] Add-on structure, configuration management, .ankiaddon packaging
- [x] Login dialog with email/password, token storage and refresh
- [x] Menu items for login/logout

### Phase 2: Card Generation UI — ✅ COMPLETE

- [x] Generation dialog with text input, domain selector (10 domains), card style, difficulty, max cards
- [x] Review dialog: editable card list with front, back, tags, notes; delete individual cards
- [x] Language hook selector (visible when domain="lang")
- [x] Usage counter display, API error handling

### Phase 3: Card Creation in Anki — ✅ COMPLETE

- [x] Deck selector, note type mapping (Basic/Cloze), tag application
- [x] Batch creation with undo support (`mw.checkpoint`)
- [x] Mixed card type handling (basic + cloze)

### Phase 4: Browser Integration & Enhancement — ✅ COMPLETE

- [x] "Enhance with AI" in browser context menu (Ctrl+Shift+E)
- [x] Enhancement options dialog (context, tags, formatting, TTS, images)
- [x] Domain selector, apply enhancements with undo, partial failure handling

### Phase 5: TTS & Image Handling — ✅ COMPLETE

- [x] Download TTS audio and images, save via `col.media.write_data()`
- [x] Per-section TTS placement (front, answer, example), direction filtering
- [x] Two-layer media dedup, background thread downloads, generate-with-assets pipeline

### Phase 6: Settings & Polish — ✅ COMPLETE

- [x] Settings dialog (generation defaults, enhancement defaults, API URL)
- [x] Security hardening (`html.escape`), batch size guard (50 cards max)
- [x] Package builder (`tools/package.py`)

**Deferred**: Standalone usage widget, "Enhance on Review" feature.

### Post-Phase 6: Audit Hardening — ✅ COMPLETE

14 audit findings resolved across Sessions 13–24: sync guard, proactive token refresh, retry_after cap, failed cards handling, generate-with-assets pipeline, card_type in enhance payloads, dead code removal, HTML escaping.

### Phase 7: CSS Styling & Furigana — 7a+7b+7c COMPLETE, 7d NOT STARTED

Structured `fc-*` CSS output and Japanese furigana support. See root `CLAUDE.md` "Structured HTML Output Contract".

- **7a. Structured HTML output** — ✅ COMPLETE. All 10 domains output `fc-*` HTML.
- **7b. Furigana in LANG domain** — ✅ COMPLETE. Per-kanji `<ruby>` annotations.
- **7c. CSS stylesheet injection** — ✅ COMPLETE. Idempotent injection/removal, styles dialog, auto-prompt.
- **7d. Note type template support** — NOT STARTED. Optional: "Flashcard Tools" note type with pre-configured templates.

**Remaining acceptance criteria:**
- [ ] Cards render correctly on AnkiDroid and AnkiMobile (untested on mobile)

## Planned Features

1. **Generation feature parity with web app** — Add `user_guidance` field, `source_language`/`output_language` fields, and directive mode (`content_type: 'prompt'`) to the Anki generation dialog. Feature parity between add-on and web app is a project goal.

---

# PRD 3: Flashcard Tools Web App

```yaml
title: "Flashcard Tools Web App"
status: active
priority: high
created: 2026-02-21
updated: 2026-03-03
owner: Luis
dependencies: ["Flashcard Tools Backend (Phase 5b Billing deployed)"]
estimated_effort: 25-35 hours (all phases complete)
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

- **Build Tool**: Vite 6 + @vitejs/plugin-react + @tailwindcss/vite *(no @cloudflare/vite-plugin in dev — pure SPA dev server is simpler; CF plugin installed but unused)*
- **UI Library**: React 19
- **Routing**: React Router 7 (library mode — explicit route definitions)
- **Styling**: Tailwind CSS v4 + shadcn/ui *(CSS-first config via `@theme` in index.css — no tailwind.config.ts)*
- **State**: Zustand (client-side working state) with `persist` middleware for user preferences
- **Auth**: Supabase Auth (shared with backend — same Supabase project)
- **Validation**: Zod 4 + react-hook-form + @hookform/resolvers
- **HTML Sanitization**: DOMPurify (strict allowlist for `fc-*` card HTML)
- **Payments**: Stripe Checkout (redirect) + Stripe Customer Portal
- **Export**: sql.js (WASM) + JSZip — client-side .apkg generation *(+ CSV, Markdown, JSON via format registry)*
- **Hosting**: Cloudflare Workers (static assets — SPA requests are free, no compute)
- **Testing**: Vitest (unit) + Playwright (e2e, not yet configured)

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

**`cards` table** — persisted in Supabase with RLS (users access own cards only):

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | Auto-generated |
| `user_id` | uuid FK | References auth.users, CASCADE delete |
| `generation_request_id` | text | Stores request_id string |
| `front`, `back` | text | Card content (HTML with `fc-*` classes) |
| `card_type` | text | `'basic'` or `'cloze'` |
| `tags` | text[] | Array of tag strings |
| `notes`, `source_quote` | text | Context and attribution |
| `domain` | text | Domain slug |
| `metadata` | jsonb | Domain-specific metadata |
| `confidence_scores` | jsonb | `{ atomicity, self_contained }` |
| `is_deleted` | boolean | Soft delete for undo |
| `created_at`, `updated_at` | timestamptz | Auto-managed |

Indexes: `(user_id, created_at DESC)`, `(user_id, domain) WHERE NOT is_deleted`, `(generation_request_id)`.

**Client-side state**: 3 Zustand stores — `cards` (generation + library + export transfer), `auth` (Supabase session), `settings` (persisted preferences via `persist` middleware). See `src/stores/` for implementations.

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

No server-side export endpoint needed. Client builds .apkg locally:

1. User selects cards + enters deck name
2. Client loads sql.js WASM (~1MB, cached), creates SQLite DB with Anki schema
3. JSZip packages as `.apkg` (renamed `.zip`), browser triggers download

Media URLs left as references for MVP — Anki fetches on first review. Media embedding deferred to Phase 5.

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

### Phase 1: Project Setup, Auth & Legal Pages — ✅ COMPLETE

- [x] Vite + React 19 + TypeScript project with React Router 7, Tailwind CSS v4, shadcn/ui
- [x] Cloudflare Workers deployment with SPA fallback routing
- [x] Landing page, pricing page, privacy policy, terms of service
- [x] Pre-render script for marketing pages (static HTML with OG meta + JSON-LD)
- [x] Login/signup via Supabase Auth, auth guard on `/app/*` routes
- [x] Authenticated app layout with sidebar navigation
- [ ] Custom domain configuration (deferred — staging only)
- [ ] Production deploy (env vars + smoke test)

### Phase 2: Card Generation & Review — ✅ COMPLETE

- [x] Generation form: content textarea, domain selector (10 domains), card style, difficulty, max cards
- [x] LANG domain language selector (JA + Other `hook_key` values)
- [x] Review panel: inline editing of front, back, tags; delete individual cards
- [x] Domain-specific metadata display, usage counter, extension handoff via URL params
- [x] Error handling: USAGE_EXCEEDED → upgrade modal, RATE_LIMITED → toast, VALIDATION_ERROR → inline errors
- [x] Usage counter refresh after generation (USAGE_CHANGED_EVENT custom DOM event)
- [x] Directive mode (`content_type: 'prompt'`) with toggle in GenerateForm, user_guidance field, source/output language support

Content types supported in web app: `text` and `prompt`. URL and PDF content types are backend-supported but not exposed in the web UI.

### Phase 3: Card Library & Management — ✅ COMPLETE

- [x] Paginated card list from `GET /cards` with filters (domain, search, tag, date range, sort)
- [x] Card detail expand, bulk selection, bulk delete with undo (5s timeout)
- [x] Responsive grid/list toggle, 3 empty states, loading skeletons

### Phase 4a: Export — ✅ COMPLETE

- [x] 4 export formats: APKG, CSV, Markdown (Obsidian SR), JSON via format registry
- [x] APKG: sql.js WASM + JSZip, code-split (~143 KB), 2000 card limit, batched inserts, cancel support
- [x] Deck name input with recent names, card type preview, collapsible format preview
- [x] CSV options (separator, headers, BOM), JSON options (field inclusion)

### Phase 4b: Billing — ✅ COMPLETE

Stripe Checkout redirect for upgrades, Customer Portal for subscription management, usage progress bar with overage display, UpgradeModal on USAGE_EXCEEDED (402), post-checkout polling for tier updates, tier badge display.

### Phase 5: Settings, Account Management & Polish — ✅ COMPLETE

Settings page (5 sections: account info, appearance, change password, data export, danger zone), dark mode (system/light/dark with OKLCH variables, no FOWT), GDPR data export (JSON download), account deletion with email confirmation cascade, 404 catch-all page, auth-aware marketing header, keyboard shortcuts (Ctrl+Enter generate, Ctrl+E export), loading skeletons, OG meta tags, usage refresh after generation via USAGE_CHANGED_EVENT.

**Remaining polish (not blocking production):**
- [ ] Mobile responsive pass (320px, 375px, 768px)
- [ ] Lighthouse audit: 90+ on performance, accessibility, SEO
- [ ] Cookie consent banner (functional cookies only for MVP)

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

---

# Product Backlog

## Open Design Questions

- **Card count vs max_cards**: Generation often returns fewer cards than max_cards. This is likely quality gates (confidence scoring, unsuitable content filtering) correctly rejecting weak cards. Need to: (a) verify by inspecting rejected/unsuitable arrays across diverse inputs, (b) decide whether to surface rejection reasons to users ("8 of 10 cards passed quality checks" vs silently returning fewer), (c) set user expectations ("up to N cards" not "N cards").

- **Difficulty dropdown effectiveness**: Does the beginner/intermediate/advanced parameter produce meaningfully different output? Test: generate cards from identical input at all three levels. If differences aren't clearly articulable, either make the behavioral contract explicit in domain prompts or remove the parameter. Currently affects all clients.

- **Granularity philosophy per domain**: Should every keyword in a paragraph become a card, or should only the core concept being described become a card (using the text as source for the definition)? Answer varies by domain — LANG should be high granularity (one card per vocab item), GENERAL/MED should be concept-level (one card per idea, text becomes back content). This needs to be explicitly encoded in each domain's generation prompt rather than left implicit.

## Planned Features (priority order)

1. **Rejection visibility** — Surface rejected cards and unsuitable content reasons in client UIs so users understand why card count < max_cards. No API change needed (data already in response), clients need to display it. Affects: Anki add-on, web app (Phase 2).

2. **Duplicate detection against existing cards** — Before generation, client sends existing card fronts (or hashes) from the target deck as context. Prompt skips concepts already covered. Increases token usage but prevents the highest-trust-destroying outcome: paying for cards you already have. Two implementation paths: (a) client sends existing cards in request body (new field), (b) server-side if cards table exists (web app can query, Anki add-on sends from local DB). Affects: API contract, Anki add-on, web app.

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
Backend API (Phases 1-4 ✅, 5b ✅, cards+GDPR ✅)
    → Anki Add-on (Phases 1-6 ✅, Phase 7 optional)
    → Web App (Phases 1-5 ✅, production deploy next)
        → Browser Extension (thin capture shim)
        → Mobile Apps (gated on demand data)
```

## Phase Gates

**Gate 1 (After Backend Phase 2)** ✅ Passed.

**Gate 2 (After Anki Add-on Phase 6)** ✅ Passed. Enhance 50+ cards from actual decks. AI suggestions confirmed useful.

**Gate 3 (After Web App Phase 4)**: Export complete (4 formats: APKG, CSV, Markdown, JSON). Billing complete (Stripe Checkout, Customer Portal, usage display, UpgradeModal). Gate evaluation: pending production deployment and real-user testing.

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
| Backend (Phase 5b Billing) | 6-8 | ✅ Complete |
| Backend (Phase 7 CSS/Furigana) | 3-5 | ✅ 7a+7b complete |
| Backend (cards table + endpoints) | 2-3 | ✅ Complete |
| Anki Add-on (Phases 1-6) | 15-19 | ✅ Complete |
| Anki Add-on (Phase 7 CSS/Furigana) | 3-5 | 7c complete, 7d not started |
| **Web App (Phases 1-5)** | **25-35** | ✅ All phases complete; production deploy next |
| Browser Extension | 8-12 | After web app |
| Android App | 18-22 | Gated on Gate 4 |
| **Total (through web app)** | **~75-100** | |

## Future Considerations

### Mobile Apps (Android + iOS)

Native apps using Expo (React Native) providing share sheet capture from mobile browsers and other apps. Cards generated via backend API, exported as .apkg for AnkiDroid/AnkiMobile. Gated on Gate 4 demand data. Estimated 25-35 hours for both platforms (shared codebase).

### iOS App

An iOS companion using the same Expo codebase. Would provide share sheet capture from Safari and other iOS apps. Gated on Gate 4 demand data and Android app validation. Estimated 10-15 hours incremental effort over Android (shared codebase, platform-specific share sheet and AnkiMobile integration, App Store submission).

---
*Last updated: 2026-03-02*
*Changes: Documentation audit — updated status timestamps. Previous: PRD restructuring.*

