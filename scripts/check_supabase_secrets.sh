#!/usr/bin/env bash

set -euo pipefail

if rg -n --hidden \
  --glob '!lib/core/constants/supabase_config.dart' \
  --glob '!scripts/check_supabase_secrets.sh' \
  --glob '!.githooks/pre-commit' \
  --glob '!.mcp.json' \
  --glob '!.git/*' \
  --glob '!build/*' \
  --glob '!ios/Pods/*' \
  --glob '!macos/Pods/*' \
  'sb_publishable_[A-Za-z0-9_-]{10,}|https://[A-Za-z0-9-]+\.supabase\.co' \
  .; then
  echo
  echo "Supabase credential-like content found in tracked files."
  echo "Use --dart-define or --dart-define-from-file instead of hardcoding secrets."
  exit 1
fi

echo "Supabase secret check passed."
