#!/usr/bin/env bash
# Preflight for a Pip Realtime OpenAI account: confirms the exact model
# aliases the app depends on are actually visible to this account BEFORE any
# switch (key rotation, new project, new org) ships. A silently-missing alias
# otherwise only surfaces later, as a live call failing for a real user.
#
# Checks, in order: gpt-5-nano, gpt-realtime-2.1-mini,
# gpt-4o-mini-transcribe, gpt-4o-mini-tts — via GET
# https://api.openai.com/v1/models/<id>. Stops at the first alias that is not
# available and exits nonzero.
#
# Never prints OPENAI_API_KEY, or any response header/body — only the model
# id and a pass/fail outcome, one line per alias.
set -euo pipefail

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is not set. Export it and re-run:" >&2
  echo "  export OPENAI_API_KEY=<your OpenAI API key>" >&2
  exit 64
fi

# The exact aliases Pip Live depends on, checked in this order.
model_aliases=(
  "gpt-5-nano"
  "gpt-realtime-2.1-mini"
  "gpt-4o-mini-transcribe"
  "gpt-4o-mini-tts"
)

urlencode() {
  local raw="$1" encoded="" char i
  for (( i = 0; i < ${#raw}; i++ )); do
    char="${raw:i:1}"
    case "${char}" in
      [a-zA-Z0-9.~_-]) encoded+="${char}" ;;
      *) encoded+="$(printf '%%%02X' "'${char}")" ;;
    esac
  done
  printf '%s' "${encoded}"
}

for model in "${model_aliases[@]}"; do
  encoded_model="$(urlencode "${model}")"
  # -o /dev/null discards the body; only the status line is ever inspected.
  # `|| echo 000` turns a transport-level failure (no connection, timeout)
  # into a synthetic unavailable status instead of tripping `set -e` here.
  http_status="$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time 15 \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    "https://api.openai.com/v1/models/${encoded_model}" || echo "000")"

  if [[ "${http_status}" != "200" ]]; then
    echo "${model}: UNAVAILABLE (HTTP ${http_status})"
    exit 1
  fi
  echo "${model}: available (HTTP ${http_status})"
done

echo
echo "All four model aliases are available on this account."
