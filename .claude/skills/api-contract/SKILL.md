---
name: api-contract
description: Cross-project API contract — error codes, required fields, content limits, timeouts, HTML contract, endpoints, and subscription tiers for the Memogenesis ecosystem
---

# Memogenesis API Contract

Cross-project contract between backend (Cloudflare Workers), Anki add-on (Python), and web app (React). This document consolidates contract details scattered across the three sub-project CLAUDE.md files.

## Error Codes

| Code | HTTP | Backend Behavior | Client Behavior |
|------|------|-----------------|-----------------|
| `UNAUTHORIZED` | 401 | Return error | Anki: clear token → login dialog. Web: redirect to login. |
| `USAGE_EXCEEDED` | 402 | Return error + limits + `reason` | Show upgrade message with usage details |
| `FORBIDDEN` | 403 | Return error | Show permission error |
| `NOT_FOUND` | 404 | Return error | Show not found message |
| `RATE_LIMITED` | 429 | Return `retry_after` | Auto-retry (max 2, cap 60s), then show toast/message |
| `CONFLICT` | 409 | Duplicate email signup | Show "account already exists" message |
| `VALIDATION_ERROR` | 400 | Return field errors | Show user-friendly validation message |
| `CONTENT_TOO_LARGE` | 413 | Reject before processing | Show size limit message |
| `INTERNAL_ERROR` | 500 | Log full trace, return `request_id` only | Show "Something went wrong" + `request_id` |

**Backend location**: `flashcard-backend/src/middleware/errorHandler.ts`
**Anki handler**: `flashcard-anki/src/api/client.py`
**Web handler**: `flashcard-web/src/lib/api.ts`

## Required Fields

### Every request (client → backend)
- `product_source`: `'anki_addon'` or `'web_app'` — in request body

### Every response (backend → client)
- `request_id`: UUID string — in both success and error responses

## Content Limits

| Type | Max Size | HTTP on reject |
|------|----------|----------------|
| Text (raw) | 100KB | 413 |
| URL (fetched content) | 100KB after extraction | Truncate + warn |
| PDF file | 10MB | 413 |
| PDF extracted | 100KB | Truncate + warn |

**Note**: `/cards/generate` has a 15MB body size override to accommodate base64-encoded PDFs (~13.8MB inside JSON). The 10MB PDF limit applies to all other routes. See `flashcard-backend/src/index.ts:41-44`.

**Backend enforcement**: `flashcard-backend/src/middleware/contentSize.ts`

## Timeouts

| Operation | Backend timeout | Client timeout |
|-----------|----------------|----------------|
| Claude API (generate) | 60s | 90s |
| Claude API (enhance) | 60s | 120s (multi-card) |
| OpenAI TTS | 15s | 15s |
| Unsplash image | 10s | 10s |
| Stripe | 25s | — |

## Structured HTML Contract

All card content uses `fc-` prefixed CSS classes. Backend prompts generate the HTML; clients render and style it.

### Class hierarchy
```
fc-front / fc-back
  └── fc-section fc-{type}
        ├── fc-heading
        └── fc-content
```

### Section types
`fc-meaning`, `fc-example`, `fc-notes`, `fc-meta`, `fc-formula`, `fc-code`, `fc-source`

### Meta elements
- `fc-tag` — badges inside `fc-meta` (format: `namespace::value`)
- `fc-register` — formality level indicator

### Language-specific (LANG domain)
- `fc-word` — primary word/phrase
- `fc-reading` — pronunciation/furigana section
- `fc-jp` / `fc-en` — bilingual text containers
- `fc-target` — target language content (used for RTL: `dir="rtl" lang="ar"`)
- `fc-cloze` — cloze deletion markers

### Furigana format
```html
<ruby>kanji<rt>reading</rt></ruby>
```
- Per-kanji annotation (never wrap entire compound)
- Only on kanji — never hiragana, katakana, romaji, or English

### Source locations
- **HTML generator**: `flashcard-backend/src/lib/prompts/hooks/` (all domain hooks)
- **Anki CSS**: `flashcard-anki/src/styles/stylesheet.py` (`FC_STYLESHEET`)
- **Web rendering**: `flashcard-web/src/components/` (card display components)

## API Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/health` | GET | No | Health check |
| `/health/ready` | GET | No | Readiness (Supabase connectivity) |
| `/auth/signup` | POST | No | Create account |
| `/auth/login` | POST | No | Login |
| `/auth/refresh` | POST | No | Refresh JWT |
| `/auth/me` | GET | Yes | Current user info |
| `/cards/generate` | POST | Yes | Generate flashcards from content |
| `/cards/enhance` | POST | Yes | Enhance existing flashcards |
| `/cards` | GET | Yes | List user's cards |
| `/cards/:id` | PATCH | Yes | Update a card |
| `/cards/:id` | DELETE | Yes | Soft-delete a card |
| `/cards` | DELETE | Yes | Bulk soft-delete |
| `/assets/tts` | POST | Yes | Generate TTS audio |
| `/assets/tts/:cacheKey` | GET | Yes | Get cached TTS audio |
| `/assets/image` | POST | Yes | Search for card image |
| `/usage/current` | GET | Yes | Current usage stats |
| `/billing/checkout` | POST | Yes | Create Stripe checkout session |
| `/billing/portal` | GET | Yes | Stripe customer portal URL |
| `/billing/webhook` | POST | Stripe sig | Stripe webhook handler |
| `/account` | DELETE | Yes | Delete account (GDPR) |
| `/account/export` | GET | Yes | Export all user data (GDPR) |

## Subscription Tiers

| Tier | Monthly cards | Overage rate | Rate limit (hourly gen) |
|------|--------------|--------------|------------------------|
| Free | 50 | N/A | Low |
| Plus | 500 | 2c/card | Medium |
| Pro | 2000 | 2c/card | High |
