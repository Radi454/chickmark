#!/usr/bin/env bash
# Rebuild ChickMark in release mode and install to the connected iPhone.
# Usage: ./reinstall_ios.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "🔎 Finding connected iPhone..."
DEVICE_ID=$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    devices = []
for d in devices:
    platform = d.get("targetPlatform", "")
    if platform.startswith("ios") and not d.get("emulator", False):
        print(d["id"])
        break
')

if [ -z "${DEVICE_ID:-}" ]; then
  echo "❌ No iPhone detected."
  echo "   Plug in via cable, unlock the phone, tap \"Trust\" if prompted, then re-run."
  exit 1
fi

echo "📱 Target device: $DEVICE_ID"
echo "🔨 Building release (pods cached → fast)..."
flutter build ios --release

echo "📲 Installing to device..."
flutter install --release -d "$DEVICE_ID"

echo "✅ Done. Reopen ChickMark on the phone to see your changes."
