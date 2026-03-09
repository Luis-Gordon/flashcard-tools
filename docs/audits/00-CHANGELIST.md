# Doc Cleanup Changelist — 2026-03-02

Cross-referenced all docs against session logs, file trees, and stated current state.
Files in this directory are cleaned versions ready to overwrite their originals.

## Summary of Changes

### PRD.md (root) — 18 changes
1. **Current Status**: Updated to reflect all web app phases complete, billing done
2. **Web App yaml header**: `updated` → 2026-03-02, `estimated_effort` → actual hours, removed Phase 5b dependency
3. **Phase 2 acceptance**: Checked "Usage counter refresh" (done Session 18)
4. **Phase 4b**: Rewritten as COMPLETE summary (was "not started" with unchecked criteria)
5. **Phase 5**: Checked data export, account deletion, dark mode, 404 page; left mobile/Lighthouse/cookie unchecked
6. **Gate 3**: Updated — billing complete, gate passed
7. **Development Dependencies**: Build order shows all web app phases complete
8. **Estimated Total Effort**: Web app row updated to "All phases complete"
9. **Billing dependency note** removed from web app yaml (no longer blocked)

### Backend CLAUDE.md — 3 changes
1. **Next Session Tasks**: Updated (Phase 4b done → production deploy prep, Stripe live keys)
2. **Stripe note**: Clarified test vs live key status
3. **Current Status**: Minor wording refresh

### Web App CLAUDE.md — 3 changes
1. **Backend prerequisite**: Removed (product_source fix deployed)
2. **Next Session Tasks**: Updated with production deployment details
3. **Phase tag**: Confirms all phases complete

### Web App backlog.md — 11 changes
1. Marked completed: error sanitization, og:image, Stripe Checkout, usage display, usage refresh, dark mode, GDPR export, fc-* note
2. Reorganized into Done / Remaining / Code Quality sections
3. Removed stale "Design Decisions Pending" items that are resolved (usage state → DOM events, already shipped)

### Web App architecture.md — 1 change
1. "Not Yet Implemented" section wording tightened

### Web App README.md — 3 changes
1. Status line: "All phases complete" with full feature list
2. Tech stack: Removed phase labels (everything shipped)
3. Backend Production: Still "Not yet deployed" (accurate for web app)

### Backend architecture.md — 2 changes
1. System diagram: Removed "export" route box (Phase 5a postponed, no route exists)
2. Minor: no other changes needed (doc is comprehensive and accurate)

### Backend README.md — 2 changes
1. Project structure: Added missing `library.ts` and `account.ts` in routes listing
2. Production URL: Kept as "Pending deployment" (user confirms test keys still active)

## Files NOT Changed (already accurate)
- Backend architecture.md database schema sections
- Backend architecture.md test infrastructure section
- All session-log.md files (append-only, never modified)
