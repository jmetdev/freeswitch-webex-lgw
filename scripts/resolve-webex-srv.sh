#!/usr/bin/env bash
# Resolve Webex outbound-proxy SRV into runtime vars.xml (host-side, before restart).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARS_FILE="${1:-$ROOT/runtime/config/vars.xml}"
PROXY_HOST="$(sed -n 's|.*data="webex_outbound_proxy=\([^:"]*\)[^"]*".*|\1|p' "$VARS_FILE" | head -1)"

[[ "$PROXY_HOST" == *sipconnect* ]] || { echo "webex_outbound_proxy is not a sipconnect hostname; skip"; exit 0; }

SRV_LINE="$(dig +short SRV "_sips._tcp.${PROXY_HOST}" @8.8.8.8 2>/dev/null | sort -n | head -1)"
[[ -n "$SRV_LINE" ]] || { echo "No SRV for ${PROXY_HOST}" >&2; exit 1; }

SRV_PORT="$(echo "$SRV_LINE" | awk '{print $3}')"
SRV_TARGET="$(echo "$SRV_LINE" | awk '{print $4}' | sed 's/\.$//')"
RESOLVED="${SRV_TARGET}:${SRV_PORT}"

echo "Resolved ${PROXY_HOST} -> ${RESOLVED}"
sed -i.bak "s|data=\"webex_outbound_proxy=[^\"]*\"|data=\"webex_outbound_proxy=${RESOLVED}\"|" "$VARS_FILE"
rm -f "${VARS_FILE}.bak"
