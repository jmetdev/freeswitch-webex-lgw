#!/bin/sh
set -eu

DEFAULT_CONFIG="/etc/freeswitch.default"
LIVE_CONFIG="/etc/freeswitch"
PROFILE="${FS_PROFILE:-webex}"
PROFILE_DIR="/etc/freeswitch.profiles/${PROFILE}"

if [ ! -f "${LIVE_CONFIG}/freeswitch.xml" ]; then
  echo "Seeding ${LIVE_CONFIG} from ${DEFAULT_CONFIG}..."
  cp -a "${DEFAULT_CONFIG}/." "${LIVE_CONFIG}/"
fi

if [ -d "${PROFILE_DIR}" ]; then
  if [ -f "${PROFILE_DIR}/sip_profiles/external/webex_gateway.xml" ]; then
    mkdir -p "${LIVE_CONFIG}/sip_profiles/external"
    cp -f "${PROFILE_DIR}/sip_profiles/external/webex_gateway.xml" \
      "${LIVE_CONFIG}/sip_profiles/external/webex_gateway.xml"
  fi
  if [ -f "${PROFILE_DIR}/dialplan/default.xml" ]; then
    cp -f "${PROFILE_DIR}/dialplan/default.xml" "${LIVE_CONFIG}/dialplan/default.xml"
  fi
  if [ -f "${PROFILE_DIR}/vars.xml" ] && [ -f "${LIVE_CONFIG}/vars.xml" ]; then
    if ! grep -q 'data="webex_registrar=' "${LIVE_CONFIG}/vars.xml" 2>/dev/null; then
      grep -v '</include>' "${LIVE_CONFIG}/vars.xml" > "${LIVE_CONFIG}/vars.xml.tmp"
      cat "${PROFILE_DIR}/vars.xml" >> "${LIVE_CONFIG}/vars.xml.tmp"
      echo '</include>' >> "${LIVE_CONFIG}/vars.xml.tmp"
      mv "${LIVE_CONFIG}/vars.xml.tmp" "${LIVE_CONFIG}/vars.xml"
    fi
  fi
fi

if [ -f "${DEFAULT_CONFIG}/fs_cli.conf" ]; then
  cp -f "${DEFAULT_CONFIG}/fs_cli.conf" /etc/fs_cli.conf
fi

# event_socket.conf.xml uses name="password", not data="password".
ESL_CONF="${LIVE_CONFIG}/autoload_configs/event_socket.conf.xml"
if [ -n "${ESL_PASSWORD:-}" ] && [ -f "${ESL_CONF}" ]; then
  sed -i "s|name=\"password\" value=\"[^\"]*\"|name=\"password\" value=\"${ESL_PASSWORD}\"|" \
    "${ESL_CONF}" 2>/dev/null || true
  if [ -f /etc/fs_cli.conf ]; then
    sed -i "s|name=\"password\" value=\"[^\"]*\"|name=\"password\" value=\"${ESL_PASSWORD}\"|" \
      /etc/fs_cli.conf 2>/dev/null || true
  fi
fi
if [ -n "${ESL_LISTEN_IP:-}" ] && [ -f "${ESL_CONF}" ]; then
  sed -i "s|name=\"listen-ip\" value=\"[^\"]*\"|name=\"listen-ip\" value=\"${ESL_LISTEN_IP}\"|" \
    "${ESL_CONF}" 2>/dev/null || true
fi

CERTS_DIR="${LIVE_CONFIG}/certs"
mkdir -p "${CERTS_DIR}"
if [ ! -f "${CERTS_DIR}/agent.pem" ] && command -v openssl >/dev/null 2>&1; then
  echo "Generating self-signed TLS agent certificate..."
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=freeswitch" \
    -keyout "${CERTS_DIR}/agent.key" -out "${CERTS_DIR}/agent.crt"
  cat "${CERTS_DIR}/agent.crt" "${CERTS_DIR}/agent.key" > "${CERTS_DIR}/agent.pem"
  rm -f "${CERTS_DIR}/agent.crt" "${CERTS_DIR}/agent.key"
  chmod 600 "${CERTS_DIR}/agent.pem"
fi
if [ ! -f "${CERTS_DIR}/cafile.pem" ] && [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  cp /etc/ssl/certs/ca-certificates.crt "${CERTS_DIR}/cafile.pem"
fi

VARS_FILE="${LIVE_CONFIG}/vars.xml"
if [ -f "${VARS_FILE}" ]; then
  # Env-driven vars (see .env.example)
  set_var() {
    local name="$1" value="$2"
    [ -n "$value" ] || return 0
    sed -i "s|data=\"${name}=[^\"]*\"|data=\"${name}=${value}\"|" "${VARS_FILE}" 2>/dev/null || true
  }
  [ -n "${EXTERNAL_SIP_IP:-}" ] && set_var external_sip_ip "${EXTERNAL_SIP_IP}" && set_var local_ip_v4 "${EXTERNAL_SIP_IP}"
  [ -n "${EXTERNAL_RTP_IP:-}" ] && set_var external_rtp_ip "${EXTERNAL_RTP_IP}"
  [ -n "${WEBEX_REGISTRAR:-}" ] && set_var webex_registrar "${WEBEX_REGISTRAR}"
  [ -n "${WEBEX_OUTBOUND_PROXY:-}" ] && set_var webex_outbound_proxy "${WEBEX_OUTBOUND_PROXY}"
  [ -n "${WEBEX_CONTACT_FQDN:-}" ] && set_var webex_contact_fqdn "${WEBEX_CONTACT_FQDN}"
  [ -n "${WEBEX_LINE_PORT:-}" ] && set_var webex_line_port "${WEBEX_LINE_PORT}"
  [ -n "${WEBEX_USERNAME:-}" ] && set_var webex_username "${WEBEX_USERNAME}"
  [ -n "${WEBEX_PASSWORD:-}" ] && set_var webex_password "${WEBEX_PASSWORD}"
  [ -n "${WEBEX_OTG:-}" ] && set_var webex_otg "${WEBEX_OTG}"
fi

# Resolve Webex outbound-proxy SRV (sipconnect hostname → target:8934)
if [ -f "${VARS_FILE}" ] && command -v dig >/dev/null 2>&1; then
  PROXY_HOST="$(sed -n 's|.*data="webex_outbound_proxy=\([^:"]*\)[^"]*".*|\1|p' "${VARS_FILE}" | head -1)"
  case "${PROXY_HOST}" in
    *sipconnect*)
      SRV_LINE="$(dig +short SRV "_sips._tcp.${PROXY_HOST}" @8.8.8.8 2>/dev/null | sort -n | head -1)"
      if [ -n "${SRV_LINE}" ]; then
        SRV_PORT="$(echo "${SRV_LINE}" | awk '{print $3}')"
        SRV_TARGET="$(echo "${SRV_LINE}" | awk '{print $4}' | sed 's/\.$//')"
        if [ -n "${SRV_TARGET}" ] && [ -n "${SRV_PORT}" ]; then
          echo "Resolved Webex outbound proxy ${PROXY_HOST} -> ${SRV_TARGET}:${SRV_PORT}"
          sed -i "s|data=\"webex_outbound_proxy=[^\"]*\"|data=\"webex_outbound_proxy=${SRV_TARGET}:${SRV_PORT}\"|" "${VARS_FILE}"
        fi
      fi
      ;;
  esac
fi

mkdir -p \
  "${LIVE_CONFIG}" \
  /var/log/freeswitch \
  /var/lib/freeswitch/recordings \
  /var/spool/fax \
  /run/freeswitch

chown -R freeswitch:freeswitch \
  /var/log/freeswitch \
  /var/lib/freeswitch \
  /var/spool/fax \
  /run/freeswitch \
  2>/dev/null || true

exec "$@"
