#!/usr/bin/env bash

set -euo pipefail

SECRET_PATTERN='sb_publishable_[A-Za-z0-9_-]{10,}|sb_secret_[A-Za-z0-9_-]{10,}|https://[A-Za-z0-9-]+\.supabase\.co|eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*(cm9sZSI6ImFub24i|cm9sZSI6InNlcnZpY2Vfcm9sZSI)[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+'

if git grep -nIE "${SECRET_PATTERN}" -- \
  ':!lib/core/constants/supabase_config.dart' \
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
