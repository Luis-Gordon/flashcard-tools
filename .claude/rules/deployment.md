---
globs: "**/wrangler.*,**/.env*,**/validation/*.ts"
---
- **Backend-first deployment**: `.strict()` Zod rejects unknown fields. Deploy backend -> verify health -> deploy client.
- Use `npm run deploy:staging` (not manual build + deploy) — script handles `--mode staging`
- CORS: add new client URLs to `ALLOWED_ORIGINS` in `wrangler.jsonc` before deploying client
- Content limits: Text 100KB, URL 100KB extracted, PDF 10MB
- Staging first, always. Never deploy to production without staging smoke test.
