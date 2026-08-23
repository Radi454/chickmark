#!/usr/bin/env bash
#
# Live smoke test for the deployed iot-gateway Edge Function.
#
# Exercises the whole firmware-critical path against the real server: the two
# unauthenticated bootstrap endpoints, token issuance, telemetry with both
# idempotency layers, the 413 body cap, heartbeat, topology, config with ETag,
# events, the OTA check, and the documented 4xx behaviour.
#
# No secrets are embedded. Supply them from the environment:
#
#   IOT_BASE_URL=https://<project-ref>.supabase.co/functions/v1/iot-gateway \
#   IOT_DEV_SERIAL=CMH-DEV00001 \
#   IOT_DEV_FACTORY_SECRET=<64 hex> \
#   IOT_UNCLAIMED_SERIAL=CMH-DEV00002 \
#   IOT_UNCLAIMED_FACTORY_SECRET=<64 hex> \
#   bash scripts/smoke_iot_gateway.sh
#
# Requires curl, jq and python3. Exits non-zero if any check fails.
#
# NOTE: this calls /v1/provision, which mints a NEW device_secret and kills the
# previous one along with every token issued from it. Do not run it against a hub
# somebody is actively using.

set -uo pipefail

: "${IOT_BASE_URL:?set IOT_BASE_URL}"
: "${IOT_DEV_SERIAL:?set IOT_DEV_SERIAL}"
: "${IOT_DEV_FACTORY_SECRET:?set IOT_DEV_FACTORY_SECRET}"
: "${IOT_UNCLAIMED_SERIAL:=}"
: "${IOT_UNCLAIMED_FACTORY_SECRET:=}"

BASE="${IOT_BASE_URL}"
SERIAL="${IOT_DEV_SERIAL}"
FS="${IOT_DEV_FACTORY_SECRET}"

HDR=(-H "Content-Type: application/json" -H "X-Device-Firmware: 1.4.2" -H "X-Device-Serial: ${SERIAL}")
pass=0; fail=0
NOW=$(date +%s)

check() { # name expected actual
  if [[ "$2" == "$3" ]]; then echo "  PASS  $1 ($3)"; pass=$((pass+1));
  else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi
}

req() { # method path body [token] -> writes /tmp/body, echoes status
  local method="$1" path="$2" body="${3:-}" token="${4:-}"
  local args=(-s -o /tmp/iotbody -w "%{http_code}" -X "$method" "${BASE}${path}" "${HDR[@]}")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer ${token}")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

echo "== 1. provision, unclaimed hub =="
if [[ -n "${IOT_UNCLAIMED_SERIAL}" && -n "${IOT_UNCLAIMED_FACTORY_SECRET}" ]]; then
  s=$(req POST /v1/provision "{\"hub_serial\":\"${IOT_UNCLAIMED_SERIAL}\",\"factory_secret\":\"${IOT_UNCLAIMED_FACTORY_SECRET}\",\"firmware_version\":\"1.4.2\"}")
  check "409 DEVICE_NOT_CLAIMED" 409 "$s"
  check "retryable true" true "$(jq -r .error.retryable /tmp/iotbody)"
  check "retry_after_s 60" 60 "$(jq -r .error.retry_after_s /tmp/iotbody)"
else
  echo "  SKIP  no unclaimed hub configured"
fi

echo "== 2. provision, unknown serial =="
s=$(req POST /v1/provision "{\"hub_serial\":\"CMH-NOSUCH\",\"factory_secret\":\"${FS}\"}")
check "404 UNKNOWN_SERIAL" 404 "$s"

echo "== 3. provision, wrong factory secret =="
s=$(req POST /v1/provision "{\"hub_serial\":\"${SERIAL}\",\"factory_secret\":\"$(printf '0%.0s' {1..64})\"}")
check "401 INVALID_FACTORY_SECRET" 401 "$s"

echo "== 4. provision, valid =="
s=$(req POST /v1/provision "{\"hub_serial\":\"${SERIAL}\",\"factory_secret\":\"${FS}\",\"hardware_model\":\"chickmark-hub-v1\",\"firmware_version\":\"1.4.2\",\"boot_count\":1}")
check "200" 200 "$s"
HUB_ID=$(jq -r .hub_id /tmp/iotbody)
DS=$(jq -r .device_secret /tmp/iotbody)
check "device_secret is 64 hex" true "$(printf '%s' "$DS" | grep -Eq '^[0-9a-f]{64}$' && echo true || echo false)"
echo "  hub_id=${HUB_ID}"

echo "== 5. auth/token, wrong secret =="
s=$(req POST /v1/auth/token "{\"hub_id\":\"${HUB_ID}\",\"device_secret\":\"$(printf 'a%.0s' {1..64})\"}")
check "401 INVALID_DEVICE_SECRET" 401 "$s"
check "code" INVALID_DEVICE_SECRET "$(jq -r .error.code /tmp/iotbody)"

echo "== 6. auth/token, valid =="
s=$(req POST /v1/auth/token "{\"hub_id\":\"${HUB_ID}\",\"device_secret\":\"${DS}\"}")
check "200" 200 "$s"
TOKEN=$(jq -r .device_token /tmp/iotbody)
check "expires_in 86400" 86400 "$(jq -r .expires_in /tmp/iotbody)"

echo "== 7. bad bearer token =="
s=$(req POST /v1/heartbeat '{}' "v1.deadbeef")
check "401 DEVICE_UNAUTHORIZED" 401 "$s"

echo "== 8. telemetry =="
BATCH="${SERIAL}-000000000001-${NOW}"
s=$(req POST /v1/telemetry "{\"batch_id\":\"${BATCH}\",\"sent_at\":${NOW},\"readings\":[{\"sensor_uid\":\"A4CF12B93D07\",\"measured_at\":$((NOW-60)),\"metrics\":{\"temperature_c\":27.4,\"humidity_rh\":61.2,\"co2_ppm\":1240},\"battery_percent\":87,\"rssi\":-68},{\"sensor_uid\":\"7C9E44A10B22\",\"measured_at\":$((NOW-30)),\"metrics\":{\"temperature_c\":37.6},\"t_est\":true},{\"sensor_uid\":\"7C9E44A10B22\",\"measured_at\":$((NOW-20)),\"metrics\":{\"temperature_c\":900}},{\"sensor_uid\":\"BADUID\",\"measured_at\":$((NOW-10)),\"metrics\":{\"temperature_c\":20}},{\"sensor_uid\":\"A4CF12B93D07\",\"measured_at\":$((NOW+9999)),\"metrics\":{\"temperature_c\":20}}]}" "$TOKEN")
check "202" 202 "$s"
check "accepted 3" 3 "$(jq -r .accepted /tmp/iotbody)"
check "rejected 2" 2 "$(jq -r '.rejected|length' /tmp/iotbody)"
check "flagged 1" 1 "$(jq -r '.flagged|length' /tmp/iotbody)"
check "reject reasons" "UNKNOWN_SENSOR FUTURE_TIMESTAMP" "$(jq -r '[.rejected[].reason]|join(" ")' /tmp/iotbody)"

echo "== 9. telemetry replay (idempotency) =="
s=$(req POST /v1/telemetry "{\"batch_id\":\"${BATCH}\",\"sent_at\":${NOW},\"readings\":[{\"sensor_uid\":\"A4CF12B93D07\",\"measured_at\":$((NOW-60)),\"metrics\":{\"temperature_c\":27.4}}]}" "$TOKEN")
check "202 duplicate" 202 "$s"
check "duplicate flag" true "$(jq -r .duplicate /tmp/iotbody)"
check "accepted 0" 0 "$(jq -r .accepted /tmp/iotbody)"

echo "== 10. telemetry oversized body =="
BIG=$(python3 -c "import json,sys;n=$NOW;print(json.dumps({'batch_id':'big-'+str(n),'readings':[{'sensor_uid':'A4CF12B93D07','measured_at':n-100,'metrics':{'temperature_c':1.0},'pad':'x'*400} for _ in range(100)]}))")
s=$(req POST /v1/telemetry "$BIG" "$TOKEN")
check "413 PAYLOAD_TOO_LARGE" 413 "$s"

echo "== 11. heartbeat =="
s=$(req POST /v1/heartbeat "{\"sent_at\":${NOW},\"firmware_version\":\"1.4.2\",\"uptime_s\":864210,\"boot_count\":14,\"reset_reason\":\"power_on\",\"free_heap_bytes\":118432,\"wifi_rssi\":-57,\"sensors_known\":2,\"sensors_online\":2,\"queue_depth\":0,\"config_version\":1}" "$TOKEN")
check "200" 200 "$s"
check "topology_stale is boolean" true "$(jq -r '.topology_stale|type=="boolean"' /tmp/iotbody)"
check "next_heartbeat_s 60" 60 "$(jq -r .next_heartbeat_s /tmp/iotbody)"
s=$(req POST /v1/heartbeat "{\"sent_at\":${NOW},\"topology_hash\":\"deadbeef\"}" "$TOKEN")
check "changed hash -> topology_stale true" true "$(jq -r .topology_stale /tmp/iotbody)"

echo "== 12. topology =="
s=$(req POST /v1/topology "{\"sent_at\":${NOW},\"topology_hash\":\"8a41c9f2\",\"hub\":{\"firmware_version\":\"1.4.2\",\"hardware_model\":\"chickmark-hub-v1\",\"radio\":\"esp-now\",\"channel\":6},\"sensors\":[{\"sensor_uid\":\"A4CF12B93D07\",\"model\":\"chickmark-node-th-v1\",\"firmware_version\":\"0.9.3\",\"capabilities\":[\"temperature_c\",\"humidity_rh\"],\"state\":\"online\",\"last_seen_at\":$((NOW-20)),\"battery_percent\":87,\"rssi\":-68},{\"sensor_uid\":\"7C9E44A10B22\",\"model\":\"chickmark-node-air-v1\",\"capabilities\":[\"temperature_c\",\"co2_ppm\"],\"state\":\"offline\",\"last_seen_at\":$((NOW-4000)),\"battery_percent\":41,\"rssi\":-81}]}" "$TOKEN")
check "200" 200 "$s"
check "accepted 2" 2 "$(jq -r .accepted /tmp/iotbody)"

echo "== 13. config =="
s=$(req GET /v1/config "" "$TOKEN")
check "200" 200 "$s"
ETAG=$(jq -r .etag /tmp/iotbody)
check "has base_url" true "$(jq -r 'has("config") and (.config|has("base_url"))' /tmp/iotbody)"
check "has espnow_pmk" true "$(jq -r '.config|has("espnow_pmk")' /tmp/iotbody)"
check "telemetry_interval_s 300" 300 "$(jq -r .config.telemetry_interval_s /tmp/iotbody)"
s=$(curl -s -o /dev/null -w "%{http_code}" -X GET "${BASE}/v1/config" "${HDR[@]}" -H "Authorization: Bearer ${TOKEN}" -H "If-None-Match: ${ETAG}")
check "304 on If-None-Match" 304 "$s"

echo "== 14. events =="
s=$(req POST /v1/events "{\"sent_at\":${NOW},\"events\":[{\"event_id\":\"${SERIAL}-e-${NOW}1\",\"event_type\":\"hub_boot\",\"severity\":\"info\",\"occurred_at\":$((NOW-500))},{\"event_id\":\"${SERIAL}-e-${NOW}2\",\"event_type\":\"sensor_disconnected\",\"severity\":\"warning\",\"occurred_at\":$((NOW-100)),\"sensor_uid\":\"7C9E44A10B22\",\"detail\":{\"missed_intervals\":65}}]}" "$TOKEN")
check "202" 202 "$s"
check "accepted 2" 2 "$(jq -r .accepted /tmp/iotbody)"
s=$(req POST /v1/events "{\"sent_at\":${NOW},\"events\":[{\"event_id\":\"${SERIAL}-e-${NOW}1\",\"event_type\":\"hub_boot\",\"severity\":\"info\",\"occurred_at\":$((NOW-500))}]}" "$TOKEN")
check "replay -> duplicates 1" 1 "$(jq -r .duplicates /tmp/iotbody)"

echo "== 15. firmware =="
s=$(req GET /v1/firmware "" "$TOKEN")
check "200" 200 "$s"
check "update_available false" false "$(jq -r .update_available /tmp/iotbody)"

echo "== 16. unknown endpoint =="
s=$(req POST /v1/nonsense '{}' "$TOKEN")
check "404" 404 "$s"

echo
echo "RESULT: ${pass} passed, ${fail} failed"
echo "HUB_ID=${HUB_ID}"
[[ $fail -eq 0 ]]
