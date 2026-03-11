---
globs: "**/*.ts,**/*.tsx"
---
- TypeScript strict, no `any` (use `unknown` + narrowing)
- Type-only imports: `import type { Foo }`
- Zod schemas use `.strict()` — new request fields are breaking changes
- Named exports (no default except route pages)
- Switch on union types must have exhaustive `default: never` check
- Prefer interfaces for objects, types for unions
