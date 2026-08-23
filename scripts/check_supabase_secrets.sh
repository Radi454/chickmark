#!/usr/bin/env bash

set -euo pipefail

# Provider API keys are in scope too, not just Supabase ones. Pip Realtime
# authenticates to OpenAI with OPENAI_API_KEY, and a key pasted into a doc is
# exactly as leaked as one pasted into source.
SECRET_PATTERN='sb_publishable_[A-Za-z0-9_-]{10,}|sb_secret_[A-Za-z0-9_-]{10,}|https://[A-Za-z0-9-]+\.supabase\.co|eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*(cm9sZSI6ImFub24i|cm9sZSI6InNlcnZpY2Vfcm9sZSI)[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+|[0-9]{8,12}:AA[A-Za-z0-9_-]{30,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-svcacct-[A-Za-z0-9_-]{20,}|sk-or-v1-[A-Za-z0-9]{20,}'

if git grep -nIE "${SECRET_PATTERN}" -- \
  ':!scripts/check_supabase_secrets.sh' \
  ':!.githooks/pre-commit' \
  ':!.mcp.json' \
  ':!build/*' \
  ':!ios/Pods/*' \
  ':!macos/Pods/*'; then
  echo
  echo "Supabase credential-like content found in tracked files."
  echo "Use --dart-define or --dart-define-from-file instead of hardcoding secrets."
  echo "Never commit service-role keys, legacy JWT anon keys, or Supabase URLs."
  exit 1
fi

echo "Supabase secret check passed."
