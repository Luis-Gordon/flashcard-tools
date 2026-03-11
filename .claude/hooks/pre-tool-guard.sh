#!/bin/bash
# Safety guard: blocks destructive git commands
# Receives PreToolUse JSON on stdin, exits 2 to block

CMD=$(python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# 1. Block git clean (any flags)
if echo "$CMD" | grep -qiE 'git[[:space:]]+clean'; then
  echo "BLOCKED: git clean permanently deletes untracked files (docs, configs, plans). Use 'git checkout -- <file>' for tracked files." >&2
  exit 2
fi

# 2. Block blanket git checkout (-- . or just .)
if echo "$CMD" | grep -qiE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.[[:space:]]*$' || \
   echo "$CMD" | grep -qiE 'git[[:space:]]+checkout[[:space:]]+\.[[:space:]]*$'; then
  echo "BLOCKED: 'git checkout -- .' discards ALL uncommitted changes. Specify individual files: 'git checkout -- <file1> <file2>'" >&2
  exit 2
fi

# 3. Block git reset --hard
if echo "$CMD" | grep -qiE 'git[[:space:]]+reset[[:space:]]+--hard'; then
  echo "BLOCKED: git reset --hard discards commits. Use 'git revert' or 'git stash' instead." >&2
  exit 2
fi

# 4. Block force push to main/master
if echo "$CMD" | grep -qiE 'git[[:space:]]+push.*(-f|--force)' && \
   echo "$CMD" | grep -qiE '(^|[[:space:]])(main|master)([[:space:]]|$)'; then
  echo "BLOCKED: Force push to main/master destroys remote history." >&2
  exit 2
fi

# 5. Block git add of .env files (allow .env.example, .env.template, etc.)
if echo "$CMD" | grep -qiE 'git[[:space:]]+add.*\.env' && \
   ! echo "$CMD" | grep -qiE '\.(example|template)'; then
  echo "BLOCKED: .env files may contain secrets. Use 'wrangler secret put' for secrets." >&2
  exit 2
fi

exit 0
