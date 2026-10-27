#!/usr/bin/env bash
# Enable Contact FQDN on the Webex gateway AFTER Control Hub provisions the same FQDN.
# Usage: REMOTE=root@host REMOTE_DIR=/opt/freeswitch-webex-lgw ./scripts/enable-webex-contact-fqdn.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/esl.sh
source "$ROOT/scripts/lib/esl.sh"
load_esl_password "$ROOT"

REMOTE="${REMOTE:-}"
REMOTE_DIR="${REMOTE_DIR:-/opt/freeswitch-webex-lgw}"
ESL_PASSWORD="${ESL_PASSWORD:-ChangeMe-ESL-Password}"
GW_REL="runtime/config/sip_profiles/external/webex_gateway.xml"

run_local() {
  local gw="$1"
  sed -i.bak 's|<!-- <param name="extension-in-contact" value="true"/> -->|<param name="extension-in-contact" value="true"/>|' "$gw"
  sed -i.bak 's|<!-- <param name="contact-host" value="$${webex_contact_fqdn}"/> -->|<param name="contact-host" value="$${webex_contact_fqdn}"/>|' "$gw"
  rm -f "${gw}.bak"
  docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "$ESL_PASSWORD" -x "reloadxml"
  docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "$ESL_PASSWORD" -x "sofia profile external restart"
  sleep 15
  docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "$ESL_PASSWORD" -x "sofia status gateway webex" | grep -E "State|Contact|PingState"
}

if [[ -n "$REMOTE" ]]; then
  ssh "$REMOTE" bash -s <<EOF
set -euo pipefail
GW="${REMOTE_DIR}/${GW_REL}"
sed -i 's|<!-- <param name="extension-in-contact" value="true"/> -->|<param name="extension-in-contact" value="true"/>|' "\$GW"
sed -i 's|<!-- <param name="contact-host" value="\\\$\\\${webex_contact_fqdn}"/> -->|<param name="contact-host" value="\\\$\\\${webex_contact_fqdn}"/>|' "\$GW"
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "reloadxml"
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "sofia profile external restart"
sleep 15
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "sofia status gateway webex" | grep -E "State|Contact|PingState"
EOF
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  run_local "${ROOT}/${GW_REL}"
fi

echo
echo "Expect State REGED and Contact using webex_contact_fqdn."
echo "If FAIL_WAIT or TRYING: Control Hub has not provisioned this FQDN yet."
