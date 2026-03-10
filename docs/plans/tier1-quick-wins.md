# Plan: Fix reviewer script model names + Tier 1 Backlog Quick Wins

## Pre-requisite: Fix reviewer script model names

Testing the reviewer script revealed two model name errors in `tools/plan-review/run-reviewers.ps1`:

1. **Codex**: `codex-5.3` → `gpt-5.3-codex` (per `~/.codex/config.toml`; ChatGPT accounts reject non-`gpt-*` model names)
2. **Gemini**: `gemini-3.1-pro` → `gemini-2.5-pro` (`gemini-3.1-pro` doesn't exist; `gemini-2.5-pro` verified working)

**File**: `tools/plan-review/run-reviewers.ps1`
- Line with `-m","codex-5.3"` → `-m","gpt-5.3-codex"`
- Line with `-m","gemini-3.1-pro"` → `-m","gemini-2.5-pro"`

After fixing, re-run the reviewer script on this plan file to verify end-to-end.

---

## Context

The consolidated backlog (`docs/backlog.md`) lists three Tier 1 quick wins. Exploration reveals two are already implemented and one is partially done:

| Item | Status | Remaining work |
|------|--------|---------------|
| Rejection visibility | Done | None — `QualityFilter` component in `CardReview.tsx:128-175` already shows rejected + unsuitable cards |
| Card count expectations | Partial | "Generated X" shown but no "of Y requested (Z filtered)" messaging |
| CardEditor notes field | Done | Editable textarea exists (`CardEditor.tsx:62-72`), shown when notes are non-empty. Adding notes to blank cards requires `showNotes` prop — currently not passed from `CardReview` |

**Remaining work**: Two small changes.

## Changes

### 1. Card count messaging — "Generated X of Y (Z filtered)"

**File**: `flashcard-web/src/components/cards/CardReview.tsx` (~line 240)

Currently shows: `{response.usage.cards_generated} cards generated`

Change to: `Generated {cards_generated} of {max_cards} cards ({cards_rejected} filtered by quality checks)`

- `cards_generated` and `cards_rejected` are already in `response.usage` (types at `types/cards.ts:118-124`)
- `max_cards` needs to be passed through. Options:
  - **Option A**: Read from the cards store (the generate request's `max_cards` is known at request time)
  - **Option B**: Have backend return `max_cards` in the response — but this is a schema change (`.strict()` means it's not breaking to *add* a response field, only request fields break)

**Recommended: Option A** — read `max_cards` from the cards store. No backend changes needed.

- In `cards.ts` store: add `lastMaxCards: number | null` state, set it when `generateCards` is called
- In `CardReview.tsx`: pull `lastMaxCards` from store, display conditional messaging:
  - If `cards_rejected > 0`: "Generated {cards_generated} of {lastMaxCards} ({cards_rejected} filtered by quality checks)"
  - If `cards_rejected === 0`: "Generated {cards_generated} cards"

### 2. CardEditor notes — always show field in review

**File**: `flashcard-web/src/components/cards/CardReview.tsx` (~line 48)

Currently: `<CardEditor card={card} ... />` (no `showNotes` prop → notes field hidden for cards without notes)

Change to: `<CardEditor card={card} showNotes ... />` — always show the notes textarea so users can add notes to any card during review.

This is a one-line change. `CardEditor` already supports the `showNotes` prop (`CardEditor.tsx:30`).

## Files to Modify

1. `flashcard-web/src/stores/cards.ts` — add `lastMaxCards` state field
2. `flashcard-web/src/components/cards/CardReview.tsx` — card count messaging + `showNotes` prop
3. `docs/backlog.md` — mark completed items

## Verification

1. `cd flashcard-web && npm run typecheck && npm run lint:fix && npm run test`
2. Manual: generate cards → verify "Generated X of Y (Z filtered)" appears in summary bar
3. Manual: generate cards → verify notes textarea appears on all cards in review (even those without notes)
4. Manual: generate with content that triggers rejections → verify count messaging shows filtered count
