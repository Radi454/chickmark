#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

WEB_HOST="${WEB_HOST:-127.0.0.1}"
WEB_PORT="${WEB_PORT:-57861}"
APP_URL="http://${WEB_HOST}:${WEB_PORT}/#/main"

is_port_in_use() {
  if command -v nc >/dev/null 2>&1 &&
    nc -z "${WEB_HOST}" "${WEB_PORT}" >/dev/null 2>&1; then
    return 0
  fi

  curl --silent --head --max-time 1 "http://${WEB_HOST}:${WEB_PORT}" \
    >/dev/null 2>&1
}

if is_port_in_use; then
  echo
  echo "ChickMark is already running."
  echo "Open this in the Codex side browser:"
  echo "${APP_URL}"
  echo
  exit 0
fi

echo
echo "Starting ChickMark..."
echo "Open this in the Codex side browser when Flutter is ready:"
echo "${APP_URL}"
echo

LOG_FILE="$(mktemp -t chickmark_flutter_web.XXXXXX.log)"
trap 'rm -f "${LOG_FILE}"' EXIT

set +e
flutter run \
  --dart-define-from-file=.env \
  -d web-server \
  --web-hostname="${WEB_HOST}" \
  --web-port="${WEB_PORT}" 2>&1 | tee "${LOG_FILE}"
FLUTTER_STATUS="${PIPESTATUS[0]}"
set -e

if [[ "${FLUTTER_STATUS}" -ne 0 ]] &&
  grep -q "Address already in use" "${LOG_FILE}"; then
  echo
  echo "ChickMark is already running."
  echo "Open this in the Codex side browser:"
  echo "${APP_URL}"
  echo
  exit 0
fi

exit "${FLUTTER_STATUS}"
