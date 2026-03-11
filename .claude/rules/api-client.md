---
globs: "**/api/**,**/lib/api.ts"
---
- Every request body must include `product_source` (`'anki_addon'` or `'web_app'`)
- Every response must include `request_id` (success and error)
- Error codes: see api-contract skill (`/api-contract`)
- Timeouts: auth 10s, generate 60s (client 90s), enhance 60s (client 120s), TTS 15s, images 10s
- 401 -> clear auth + redirect/dialog. 429 -> auto-retry (max 2, cap 60s). 402 -> upgrade message.
