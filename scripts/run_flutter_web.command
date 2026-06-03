#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

RESTART=1 scripts/run_flutter_web.sh
