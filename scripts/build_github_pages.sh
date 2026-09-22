#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo 'SUPABASE_URL and SUPABASE_ANON_KEY are required' >&2
  exit 1
fi

flutter build web \
  --release \
  --base-href=/chickmark/ \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
