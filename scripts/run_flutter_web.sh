#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

WEB_HOST="${WEB_HOST:-127.0.0.1}"
WEB_PORT="${WEB_PORT:-57863}"
RESTART="${RESTART:-0}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DEBUG_AUTH_BYPASS="${DEBUG_AUTH_BYPASS:-true}"
APP_URL="http://${WEB_HOST}:${WEB_PORT}/#/main"

is_port_in_use() {
  if command -v nc >/dev/null 2>&1 &&
    nc -z "${WEB_HOST}" "${WEB_PORT}" >/dev/null 2>&1; then
    return 0
  fi

  curl --silent --head --max-time 1 "http://${WEB_HOST}:${WEB_PORT}" \
    >/dev/null 2>&1
}

find_web_server_pids() {
  ps -ax -o pid=,command= |
    awk -v port="${WEB_PORT}" '
      $0 ~ /web-server/ &&
      ($0 ~ "--web-port=" port || $0 ~ "--web-port " port) {
        print $1
      }
    '
}

stop_web_server() {
  local pids=()
  local pid

  while IFS= read -r pid; do
    if [[ -n "${pid}" ]]; then
      pids+=("${pid}")
    fi
  done < <(find_web_server_pids)

  if [[ "${#pids[@]}" -eq 0 ]]; then
    return 0
  fi

  echo
  echo "Stopping existing ChickMark web server on ${WEB_HOST}:${WEB_PORT}..."
  kill "${pids[@]}" >/dev/null 2>&1 || true

  local attempts=0
  while is_port_in_use && [[ "${attempts}" -lt 20 ]]; do
    sleep 0.5
    attempts=$((attempts + 1))
  done

  if is_port_in_use; then
    kill -9 "${pids[@]}" >/dev/null 2>&1 || true
  fi

  attempts=0
  while is_port_in_use && [[ "${attempts}" -lt 10 ]]; do
    sleep 0.5
    attempts=$((attempts + 1))
  done

  if is_port_in_use; then
    echo "Port ${WEB_HOST}:${WEB_PORT} is still in use after restart cleanup."
    exit 1
  fi
}

if [[ "${RESTART}" == "1" || "${RESTART}" == "true" ]]; then
  stop_web_server
fi

if is_port_in_use; then
  echo
  echo "ChickMark is already running."
  echo "Restart current code on the stable data port with:"
  echo "  make restart-web"
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
"${FLUTTER_BIN}" run \
  --dart-define-from-file=.env \
  --dart-define=CHICKMARK_DEBUG_AUTH_BYPASS="${DEBUG_AUTH_BYPASS}" \
  -d web-server \
  --web-hostname="${WEB_HOST}" \
  --web-port="${WEB_PORT}" 2>&1 | tee "${LOG_FILE}"
FLUTTER_STATUS="${PIPESTATUS[0]}"
set -e

if [[ "${FLUTTER_STATUS}" -ne 0 ]] &&
  grep -q "Address already in use" "${LOG_FILE}"; then
  echo
  echo "ChickMark is already running."
  echo "Restart current code on the stable data port with:"
  echo "  make restart-web"
  echo "Open this in the Codex side browser:"
  echo "${APP_URL}"
  echo
  exit 0
fi

exit "${FLUTTER_STATUS}"
