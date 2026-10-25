#!/usr/bin/env bash
# Toggle Sofia SIP trace on the external profile (debug registration / INVITEs).
set -euo pipefail

CONTAINER="${FS_CONTAINER:-freeswitch}"
ESL_PASSWORD="${ESL_PASSWORD:-ChangeMe-ESL-Password}"
ACTION="${1:-on}"

case "$ACTION" in
  on)
    docker exec "$CONTAINER" fs_cli -H 127.0.0.1 -P 8021 -p "$ESL_PASSWORD" -x "sofia profile external siptrace on"
    echo "SIP trace enabled on profile external"
    ;;
  off)
    docker exec "$CONTAINER" fs_cli -H 127.0.0.1 -P 8021 -p "$ESL_PASSWORD" -x "sofia profile external siptrace off"
    echo "SIP trace disabled"
    ;;
  *)
    echo "Usage: $0 on|off" >&2
    exit 1
    ;;
esac
