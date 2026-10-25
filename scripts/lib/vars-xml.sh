#!/usr/bin/env bash
# Shared vars.xml helpers for sync and deploy.
set -euo pipefail

WEBEX_RUNTIME_VARS=(
  webex_registrar
  webex_outbound_proxy
  webex_contact_fqdn
  webex_line_port
  webex_username
  webex_password
  webex_otg
)

is_webex_placeholder() {
  [[ "$1" == *CHANGE_ME* ]]
}

vars_xml_get() {
  local file="$1" var="$2"
  sed -n "s|.*data=\"${var}=\([^\"]*\)\".*|\1|p" "$file" | head -1
}

escape_sed_repl() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Copy non-placeholder webex_* values from $src into $dst (in-place).
merge_webex_vars() {
  local src="$1" dst="$2"
  [[ -f "$src" && -f "$dst" ]] || return 0

  local var val escaped
  for var in "${WEBEX_RUNTIME_VARS[@]}"; do
    val="$(vars_xml_get "$src" "$var")"
    [[ -n "$val" ]] || continue
    is_webex_placeholder "$val" && continue
    escaped="$(escape_sed_repl "$val")"
    sed -i.bak "s|data=\"${var}=[^\"]*\"|data=\"${var}=${escaped}\"|" "$dst"
  done
  rm -f "${dst}.bak"
}

# Insert profile vars snippet before closing </include> if not already present.
merge_profile_vars_snippet() {
  local snippet="$1" dst="$2"
  [[ -f "$snippet" && -f "$dst" ]] || return 0
  if grep -q 'data="webex_registrar=' "$dst" 2>/dev/null; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  grep -v '</include>' "$dst" > "$tmp"
  cat "$snippet" >> "$tmp"
  echo '</include>' >> "$tmp"
  mv "$tmp" "$dst"
}

vars_xml_set() {
  local file="$1" var="$2" val="$3"
  [[ -f "$file" ]] || return 0
  local escaped
  escaped="$(escape_sed_repl "$val")"
  if grep -q "data=\"${var}=" "$file"; then
    sed -i.bak "s|data=\"${var}=[^\"]*\"|data=\"${var}=${escaped}\"|" "$file"
  else
    sed -i.bak "/<\/include>/i\\
  <X-PRE-PROCESS cmd=\"set\" data=\"${var}=${escaped}\"/>\\
" "$file"
  fi
  rm -f "${file}.bak"
}

render_env_to_vars() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local v
  for v in EXTERNAL_SIP_IP EXTERNAL_RTP_IP; do
    if [[ -n "${!v:-}" ]]; then
      case "$v" in
        EXTERNAL_SIP_IP) vars_xml_set "$file" external_sip_ip "${!v}"
                         vars_xml_set "$file" local_ip_v4 "${!v}" ;;
        EXTERNAL_RTP_IP) vars_xml_set "$file" external_rtp_ip "${!v}" ;;
      esac
    fi
  done

  local map
  map="WEBEX_REGISTRAR:webex_registrar
WEBEX_OUTBOUND_PROXY:webex_outbound_proxy
WEBEX_CONTACT_FQDN:webex_contact_fqdn
WEBEX_LINE_PORT:webex_line_port
WEBEX_USERNAME:webex_username
WEBEX_PASSWORD:webex_password
WEBEX_OTG:webex_otg"

  while IFS=: read -r env_name xml_name; do
    [[ -n "${!env_name:-}" ]] && vars_xml_set "$file" "$xml_name" "${!env_name}"
  done <<< "$map"
}
