#!/usr/bin/env bash
# Print Webex gateway registration summary (run on docker host).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/esl.sh
source "$ROOT/scripts/lib/esl.sh"
load_esl_password "$ROOT"

CONTAINER="${FS_CONTAINER:-freeswitch}"
ESL_PASSWORD="${ESL_PASSWORD:-ChangeMe-ESL-Password}"

docker exec "$CONTAINER" fs_cli -H 127.0.0.1 -P 8021 -p "$ESL_PASSWORD" -x "sofia status gateway webex"
