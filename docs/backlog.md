# Memogenesis — Consolidated Backlog

Unified backlog across all sub-projects, ordered by implementation priority. Sub-project backlogs (`flashcard-backend/docs/backlog.md`, `flashcard-web/docs/backlog.md`) remain the canonical source for project-specific detail and context; this document is the prioritized roadmap.

*Last updated: 2026-03-09*

---

## Tier 1 — Quick Wins (1–2 sessions each)

High-impact, low-cost items that improve the core generation experience.

- [x] **Rejection visibility** (web) — `QualityFilter` component in `CardReview.tsx` shows rejected + unsuitable cards in collapsible section. *(Done — Session 59)*

- [x] **Card count expectations** (web) — "Generated X of Y (Z filtered by quality checks)" messaging in `CardReview` summary bar. `lastMaxCards` tracked in cards store. *(Done — Session 62)*

- [x] **CardEditor notes field** (web) — Notes textarea editable in `CardEditor.tsx`; `showNotes` prop passed from `CardReview` so notes field always appears during review. *(Done — Session 62)*

---

## Tier 2 — High-Leverage Features (2–3 sessions each)

Major capability additions that unlock significant user value.

- [ ] **Enhancement flow in web** — Web app can generate cards but cannot enhance them. Backend fully supports `/cards/enhance` with all 10 domain hooks. This is the biggest missing feature in the web app.
  - Backend: no changes needed
  - Web: new `Enhance.tsx` route page, enhancement options form, before/after card diff display, Zustand store integration
  - Prerequisite: none (backend API complete)

- [ ] **Language selectors** — Output language picker for non-LANG domains + source language selector for LANG domain. Backend supports `source_language`/`output_language` since Session 55. Needs `user_language` account settings endpoint.
  - Backend: new `PATCH /account/settings` endpoint (or extend existing) for `user_language`
  - Web: `GenerateForm.tsx` language dropdowns, Settings page language preference, wire `output_language`/`source_language` into API calls

- [ ] **LANGUAGE_OPTIONS decoupling + expose zh/ko hooks** — `GenerateForm.tsx` hardcodes `[{ja}, {default}]` but backend already has `zh`, `ko`, `ru`, `ar` sub-hooks. Decouple by creating `LANG_HOOK_OPTIONS` constant mirroring backend hook registry. Must ship atomically with any new hook exposure.
  - Backend: no changes needed (hooks exist)
  - Web: `src/lib/constants/hooks.ts` + `GenerateForm.tsx` selector update

---

## Tier 3 — Bigger Bets (3+ sessions each)

Higher complexity features with substantial payoff.

- [ ] **fc-\* stylesheet extraction** (web) — Card HTML uses backend-generated `fc-*` CSS classes, currently styled via Tailwind arbitrary selectors (`[&_.fc-word]:font-semibold`). Extract to a proper stylesheet consistent with `flashcard-anki/src/styles/stylesheet.py`. Improves visual quality and maintainability of the core product.
  - Web: new `fc-styles.css` or equivalent, update `SanitizedHTML.tsx`, remove arbitrary selectors from `CardReview.tsx`

- [ ] **Duplicate detection** — Before generation, client sends existing card fronts/hashes. Backend passes to prompt as skip-list. Highest complexity but prevents the most trust-destroying outcome: paying for cards you already have.
  - Backend: add optional `existing_cards` field to `GenerateRequestSchema`, inject into prompt context, consider token budget
  - Web: query library cards, send hashes in generate request, display "N duplicates skipped" in results

- [ ] **Extension handoff** (web) — Parse `?content=...&source_url=...&source_title=...&domain=...` URL params on the Generate page. Enables future browser extension to open the web app with pre-filled content.
  - Web: `Generate.tsx` URL param parsing + form pre-fill

---

## Tier 4 — Deferred

Items that are either blocked, low-priority, or awaiting user feedback.

### Polish (no user demand signal yet)
- [ ] **Mobile responsive pass** (web) — Full responsive audit across all pages
- [ ] **Lighthouse audit** (web) — Performance, accessibility, SEO audit
- [ ] **og:image meta tags** (web) — 1200×630 branded image for social sharing

### i18n (large effort, evaluate demand first)
- [ ] **Paraglide i18n extraction** (web) — Extract hardcoded UI strings to `en.json`, install Paraglide
- [ ] **Japanese locale** (web) — First translated locale (`ja.json`) after Paraglide extraction

### Infra
- [ ] **Production deployment** (web + backend) — Production env vars, CSP production URL, deploy both
- [ ] **Vitest 3→4 upgrade** (backend) — Blocked by `@cloudflare/vitest-pool-workers` lacking vitest 4 support. Do nothing until Cloudflare ships compatible release.

### Evaluate Later
- [ ] **Structured steering fields** (backend) — `target_keywords`, `learning_goals`, `exclude_topics`. Evaluate after free-text `user_guidance` has real usage data.
- [ ] **Difficulty dropdown audit** — Does beginner/intermediate/advanced actually produce different output? Test before deciding to keep or remove.
- [ ] **Granularity philosophy** — Encode per-domain granularity explicitly in prompts. Research task.
- [ ] **Card count / max_cards contract** (backend) — Decide and document expected behavior

---

## Code Quality (low priority, no user-facing impact)

- [ ] **M10 — Extract Library.tsx concerns** (web) — 439 lines → ~285 lines via `useUndoDelete()` hook, `LibraryEmptyState`, `LibraryPagination` extraction
- [ ] **M11 — Cancel stale debounce on filter clear** (web) — `LibraryToolbar.tsx` 300ms debounce can fire stale `onFilterChange` after "Clear filters"
- [ ] **M12 — Memo FormatCard** (web) — 4 format cards re-render unnecessarily in Export page

---

## Design Decisions Pending

- [ ] Difficulty dropdown — keep or remove (see audit item above)
- [ ] Granularity controls — should web app expose per-domain granularity preferences?
- [ ] `Generate.tsx` form/review toggle pattern — `useRef` edge-case guard vs simpler derived boolean

---

## Indefinitely Deferred (Sub-Hooks)

Sub-hooks that don't justify separate implementation. See `flashcard-backend/docs/backlog.md` for rationale.

- `lang:fr`, `lang:de`, `lang:es` — default CEFR hook sufficient
- `skill:chess` — requires FEN board rendering
- `mem`, `general`, `skill` sub-hooks — metadata-level differences only
- `arts:visual`, `arts:literature` — `image_recommended` flag sufficient
