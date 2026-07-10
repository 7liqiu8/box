#!/system/bin/sh

BASE_DIR="/data/adb/box"
MIHOMO_DIR="${BASE_DIR}/mihomo"
SCRIPTS_DIR="${BASE_DIR}/scripts"
RUN_DIR="${BASE_DIR}/run"
STATE_DIR="${RUN_DIR}/state"

WIFI_CFG="${MIHOMO_DIR}/config-wifi.yaml"
CELL_CFG="${MIHOMO_DIR}/config-cellular.yaml"
ACTIVE_CFG="${MIHOMO_DIR}/config.yaml"

PROFILE_STATE="${STATE_DIR}/active_mihomo_profile"
SWITCH_LOG="${RUN_DIR}/profile_switch.log"
LOCK_FILE="${STATE_DIR}/profile_switch.lock"
STAMP_FILE="${STATE_DIR}/profile_switch.timestamp"
MIN_INTERVAL=8

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${SWITCH_LOG}"
}

same_file() {
  busybox cmp -s "$1" "$2" >/dev/null 2>&1
}

too_soon() {
  local now last diff
  now="$(date +%s)"
  last="$(cat "${STAMP_FILE}" 2>/dev/null)"

  case "${last}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  diff=$((now - last))
  [ "${diff}" -lt "${MIN_INTERVAL}" ]
}

mark_switch_time() {
  date +%s > "${STAMP_FILE}"
}

get_active_network() {
  if [ -f "${SCRIPTS_DIR}/ctr.utils" ]; then
    . "${SCRIPTS_DIR}/ctr.utils"

    if [ "$(is_wifi_connected)" = "wifi" ]; then
      local wifi_ip=""
      local i
      for i in 1 2 3 4; do
        wifi_ip="$(get_wifi_ip)"
        [ -n "${wifi_ip}" ] && break
        sleep 1
      done

      if [ -n "${wifi_ip}" ]; then
        echo "wifi"
        return 0
      fi
    fi
  fi

  echo "cellular"
}

choose_source_config() {
  case "$1" in
    wifi) echo "${WIFI_CFG}" ;;
    cellular) echo "${CELL_CFG}" ;;
    *) return 1 ;;
  esac
}

restart_box() {
  "${SCRIPTS_DIR}/box.iptables" disable >> "${SWITCH_LOG}" 2>&1
  "${SCRIPTS_DIR}/box.service" restart >> "${SWITCH_LOG}" 2>&1
  "${SCRIPTS_DIR}/box.iptables" enable >> "${SWITCH_LOG}" 2>&1
}

main() {
  mkdir -p "${STATE_DIR}" >/dev/null 2>&1 || true

  if [ -f "${LOCK_FILE}" ]; then
    log "skip: lock exists"
    exit 0
  fi
  echo $$ > "${LOCK_FILE}"
  trap 'rm -f "${LOCK_FILE}"' EXIT

  local target source current
  target="$(get_active_network)"
  source="$(choose_source_config "${target}")" || {
    log "unknown target: ${target}"
    exit 1
  }

  if [ ! -f "${source}" ]; then
    log "missing source config: ${source}"
    exit 1
  fi

  current="$(cat "${PROFILE_STATE}" 2>/dev/null)"

  if [ "${current}" = "${target}" ] && same_file "${source}" "${ACTIVE_CFG}"; then
    log "unchanged: ${target}"
    exit 0
  fi

  if too_soon; then
    log "skip: debounce active, target=${target}, current=${current}"
    exit 0
  fi

  cp "${source}" "${ACTIVE_CFG}" || {
    log "copy failed: ${source} -> ${ACTIVE_CFG}"
    exit 1
  }

  echo "${target}" > "${PROFILE_STATE}"
  mark_switch_time
  log "switched profile to ${target}"
  restart_box
}

main "$@"
