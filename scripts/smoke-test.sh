#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-ghcr.io/jmetdev/freeswitch-webex-lgw:latest}"
CONTAINER="freeswitch-smoke-test-$$"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ESL_PASSWORD="${ESL_PASSWORD:-ChangeMe-ESL-Password}"

ARCH="$(uname -m)"
if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
  PLATFORM="${SMOKE_PLATFORM:-linux/arm64}"
else
  PLATFORM="${SMOKE_PLATFORM:-linux/amd64}"
fi

"$ROOT/scripts/sync-config-to-runtime.sh"

mkdir -p "${ROOT}/runtime/config" "${ROOT}/runtime/logs" "${ROOT}/runtime/recordings" "${ROOT}/runtime/fax"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Starting container ${IMAGE} (${PLATFORM})"
docker run -d --name "${CONTAINER}" --platform "${PLATFORM}" \
  -p 18021:8021 \
  --cap-add SYS_NICE \
  -e FS_PROFILE=webex \
  -v "${ROOT}/runtime/config:/etc/freeswitch" \
  -v "${ROOT}/runtime/logs:/var/log/freeswitch" \
  -v "${ROOT}/runtime/recordings:/var/lib/freeswitch/recordings" \
  -v "${ROOT}/runtime/fax:/var/spool/fax" \
  "${IMAGE}" >/dev/null

echo "==> Waiting for FreeSWITCH to start"
for _ in $(seq 1 30); do
  if docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x status 2>/dev/null | grep -q '^UP'; then
    break
  fi
  sleep 2
done

echo "==> Status"
docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x status

echo "==> Module checks"
for mod in mod_event_socket mod_spandsp mod_sofia mod_sndfile; do
  docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "module_exists ${mod}" | grep -q true
  echo "  ${mod}: OK"
done

echo "==> mod_signalwire must be absent"
if docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "module_exists mod_signalwire" | grep -q true; then
  echo "ERROR: mod_signalwire is loaded" >&2
  exit 1
fi
echo "  mod_signalwire: absent (OK)"

echo
echo "All smoke tests passed."
