# Audit Fix Plan Review

Review of `docs/audit-fix-plan.md` before execution. 6 issues found, all corrected in the fix plan.

---

## Issue 1: Missing Finding — A-C1 (Critical)

**Problem**: A-C1 (JWT tokens stored as plaintext in Anki config) is the only finding not addressed in the fix plan. A Critical-severity finding silently omitted is a documentation gap.

**Resolution**: Accepted risk. Anki provides no encrypted storage API, and adding OS keyring requires a Python dependency (`keyring`) that can't be bundled with Anki add-ons. Added to "Accepted Risks" section in fix plan.

---

## Issue 2: B-I4 Inconsistency

**Problem**: Plan table says "UUID v4 regex, max 64 chars" but session prompt says "1-128 chars, alphanumeric + hyphens only." UUID v4 regex is too strict — it would reject legitimate tracing IDs from load balancers and CDNs (e.g., `trace.span_123`).

**Resolution**: Harmonized to: 1-128 chars, pattern `/^[a-zA-Z0-9._-]+$/`. Non-conforming values silently replaced with `crypto.randomUUID()`.

---

## Issue 3: B-I7 Over-Engineering

**Problem**: Plan says to read the body and compare actual length to Content-Length. This:
- Consumes the stream (downstream handlers can't read it)
- Adds memory pressure for every request
- Duplicates Cloudflare edge enforcement

**Resolution**: Simplified. Removed 411 rejection for missing Content-Length. Keep Content-Length check as fast-path rejection when present. Requests without Content-Length pass through (Cloudflare enforces at edge).

---

## Issue 4: B-I8 Simpler Approach

**Problem**: Plan says to make multipart limits "route-aware." Since no routes currently accept multipart uploads, this is over-engineering.

**Resolution**: Simply removed `multipart/form-data` from the PDF equivalence. Only `application/pdf` gets 10MB. All other content types get 100KB.

---

## Issue 5: "Do not modify test files" Rule

**Problem**: Plan says "Do not modify test files — if tests fail, fix the source code." But Session 1 intentionally changes behavior (removing 411, changing multipart from 10MB to 100KB), so tests must change.

**Resolution**: Replaced with: "Update tests to match new intended behavior. Do not weaken test assertions to make tests pass."

---

## Issue 6: No Test Additions Listed

**Problem**: New behavior (CORS validation, request ID validation) needs new test coverage, but no new tests were listed.

**Resolution**: Added explicit new test files:
- `test/unit/middleware/cors.test.ts` — CORS origin allowlist tests
- `test/unit/middleware/requestId.test.ts` — Request ID validation tests

---

## Session 5 & 8 Verdict Review

All verdicts **correct**. No changes needed:
- S1, S3, G1, G2, G3 — agree with all
- A-M1 through A-M5 — agree with all
- A1 through A5 — agree with all

## Dependency Ordering Review

Dependency chain **correct**:
- Session 1 creates `ALLOWED_ORIGINS` -> Session 4 uses it for return_url/success_url validation
- Session 7 removes `tts_back_url` -> Session 8 references it as already done
- Sessions 1 and 2 both modify `wrangler.jsonc` but sequentially

## Test Implications

| Session | Finding | Tests Needed |
|---------|---------|-------------|
| 1 | B-C1 | CORS origin allowlist tests |
| 1 | B-I4 | Request ID validation tests |
| 1 | B-I7 | Missing Content-Length pass-through test |
| 1 | B-I8 | Multipart 100KB limit test |
| 2 | B-C2 | KV-based rate limiting tests (mock KV) |
| 5 | B-M7 | Updated /auth/me response shape tests |
| 6 | A-I8 | Sync guard flag tests |
