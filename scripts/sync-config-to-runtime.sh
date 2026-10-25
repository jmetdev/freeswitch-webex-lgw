#!/usr/bin/env bash
# Copy versioned config/ + FS_PROFILE overlay into runtime/config/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vars-xml.sh
source "$ROOT/scripts/lib/vars-xml.sh"

PROFILE="${FS_PROFILE:-webex}"
SRC="$ROOT/config"
DST="$ROOT/runtime/config"
PROFILE_DIR="$ROOT/profiles/${PROFILE}"

mkdir -p "$DST"

BACKUP=""
if [[ -f "$DST/vars.xml" ]]; then
  BACKUP="$(mktemp)"
  cp "$DST/vars.xml" "$BACKUP"
fi

rsync -a --delete \
  --exclude 'certs/' \
  "$SRC/" "$DST/"

if [[ -d "$PROFILE_DIR" ]]; then
  if [[ -f "$PROFILE_DIR/sip_profiles/external/webex_gateway.xml" ]]; then
    mkdir -p "$DST/sip_profiles/external"
    cp -f "$PROFILE_DIR/sip_profiles/external/webex_gateway.xml" "$DST/sip_profiles/external/"
  fi
  if [[ -f "$PROFILE_DIR/dialplan/default.xml" ]]; then
    cp -f "$PROFILE_DIR/dialplan/default.xml" "$DST/dialplan/default.xml"
  fi
  if [[ -f "$PROFILE_DIR/vars.xml" ]]; then
    merge_profile_vars_snippet "$PROFILE_DIR/vars.xml" "$DST/vars.xml"
  fi
fi

if [[ -n "$BACKUP" ]]; then
  merge_webex_vars "$BACKUP" "$DST/vars.xml"
  rm -f "$BACKUP"
  echo "Preserved webex_* values from existing runtime/config/vars.xml"
fi

render_env_to_vars "$DST/vars.xml"

mkdir -p "$ROOT/runtime/logs" "$ROOT/runtime/recordings" "$ROOT/runtime/fax"
echo "Synced config + profile=${PROFILE} -> $DST"
