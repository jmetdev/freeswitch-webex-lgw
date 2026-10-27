#!/usr/bin/env bash
# Load ESL_PASSWORD from the repo .env when the caller did not already export it.

load_esl_password() {
  if [[ -n "${ESL_PASSWORD:-}" ]]; then
    return 0
  fi
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  local envfile="${root}/.env"
  [[ -f "$envfile" ]] || return 0

  local line val
  line="$(grep -E '^[[:space:]]*(export[[:space:]]+)?ESL_PASSWORD=' "$envfile" | tail -1 || true)"
  [[ -n "$line" ]] || return 0
  line="${line#export }"
  line="${line#"${line%%[![:space:]]*}"}"
  val="${line#ESL_PASSWORD=}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [[ ${#val} -ge 2 ]]; then
    local first="${val:0:1}" last="${val: -1}"
    if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
      val="${val:1:${#val}-2}"
    fi
  fi
  [[ -n "$val" ]] || return 0
  ESL_PASSWORD="$val"
  export ESL_PASSWORD
}
