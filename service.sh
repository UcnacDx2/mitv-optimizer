#!/system/bin/sh

MODDIR="${0%/*}"
STATE_DIR=/data/adb/mitv-optimizer
LOG_FILE="$STATE_DIR/optimizer.log"

mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

run_retry_logged() {
  local attempt output rc
  attempt=0
  while [ "$attempt" -lt 6 ]; do
    output="$("$@" 2>&1)"
    rc=$?
    [ -n "$output" ] && log "$output"
    [ "$rc" -eq 0 ] && return 0
    attempt=$((attempt + 1))
    sleep 3
  done
  return 1
}

LOCK_DIR="$STATE_DIR/service.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "service skipped: another instance is active"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

read_option() {
  local option_key option_value
  option_key="$1"
  option_value="$(sed -n "s/^${option_key}=//p" "$MODDIR/options.conf" | tail -n 1 | tr -d '\r')"
  [ -n "$option_value" ] && printf '%s' "$option_value" || printf '0'
}

component_state() {
  local comp pkg class state
  comp="$1"
  pkg="${comp%%/*}"
  class="${comp#*/}"
  case "$class" in
    .*) class="${pkg}${class}" ;;
  esac

  # This Android build stores package restrictions as ABX and does not provide
  # get-component-enabled-setting. Parse the small restrictions file instead
  # of repeatedly calling dumpsys package, which can exhaust Binder buffers.
  state="$(abx2xml /data/system/users/0/package-restrictions.xml - 2>/dev/null | \
    awk -v pkg="$pkg" -v target="$class" '
    index($0, "<pkg ") && index($0, "name=\"" pkg "\"") { in_pkg=1; section=""; next }
    in_pkg && index($0, "</pkg>") { exit }
    in_pkg && index($0, "<disabled-components>") { section="disabled"; next }
    in_pkg && index($0, "</disabled-components>") { section=""; next }
    in_pkg && index($0, "<enabled-components>") { section="enabled"; next }
    in_pkg && index($0, "</enabled-components>") { section=""; next }
    in_pkg && section != "" && index($0, "name=\"" target "\"") { print section; exit }
  ')"
  case "$state" in
    enabled|disabled) printf '%s' "$state" ;;
    *) printf 'default' ;;
  esac
}

package_state() {
  local pkg
  pkg="$1"
  if pm list packages -d --user 0 2>/dev/null | grep -qx "package:$pkg"; then
    printf 'disabled-user'
  else
    printf 'enabled'
  fi
}

snapshot_component() {
  local comp
  comp="$1"
  [ -f "$STATE_DIR/components.tsv" ] || : > "$STATE_DIR/components.tsv"
  grep -Fqx "$comp|default" "$STATE_DIR/components.tsv" 2>/dev/null && return
  grep -Fq "${comp}|" "$STATE_DIR/components.tsv" 2>/dev/null && return
  printf '%s|%s\n' "$comp" "$(component_state "$comp")" >> "$STATE_DIR/components.tsv"
}

disable_component() {
  local comp
  comp="$1"
  snapshot_component "$comp"
  if run_retry_logged /system/bin/pm disable --user 0 "$comp"; then
    log "disabled component: $comp"
  else
    log "component unavailable or could not be disabled: $comp"
  fi
}

snapshot_setting() {
  local snapshot_namespace snapshot_key old_value
  snapshot_namespace="$1"
  snapshot_key="$2"
  [ -f "$STATE_DIR/settings.tsv" ] || : > "$STATE_DIR/settings.tsv"
  grep -Fq "${snapshot_namespace}|${snapshot_key}|" "$STATE_DIR/settings.tsv" 2>/dev/null && return
  old_value="$(settings get "$snapshot_namespace" "$snapshot_key" 2>/dev/null | tr -d '\r')"
  [ "$old_value" = "null" ] && old_value="__NULL__"
  printf '%s|%s|%s\n' "$snapshot_namespace" "$snapshot_key" "$old_value" >> "$STATE_DIR/settings.tsv"
}

apply_setting() {
  local target_namespace target_key target_value
  target_namespace="$1"
  target_key="$2"
  target_value="$3"
  snapshot_setting "$target_namespace" "$target_key"
  if run_retry_logged /system/bin/settings put "$target_namespace" "$target_key" "$target_value"; then
    log "setting: $target_namespace/$target_key=$target_value"
  else
    log "setting failed: $target_namespace/$target_key=$target_value"
  fi
}

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 8
log "service start: device=$(getprop ro.product.device) build=$(getprop ro.build.version.incremental)"

monitor_adb_tcp() {
  local port
  port="$(read_option ADB_TCP_PORT)"
  /system/bin/setsid /system/bin/nohup "$MODDIR/adb-monitor.sh" "$STATE_DIR" "$port" \
    >/dev/null 2>&1 < /dev/null &
}

if [ "$(read_option ENABLE_ADB_TCP)" = "1" ]; then
  monitor_adb_tcp &
fi

if [ "$(read_option DISABLE_AD_COMPONENTS)" = "1" ]; then
  components="$(sed '/^[[:space:]]*$/d' "$MODDIR/components-ad.txt")"
  for comp in $components; do
    [ -n "$comp" ] || continue
    disable_component "$comp"
  done
fi

if [ "$(read_option DISABLE_OTA)" = "1" ]; then
  if [ ! -f "$STATE_DIR/packages.tsv" ]; then
    printf '%s|%s\n' \
      com.xiaomi.mitv.upgrade \
      "$(package_state com.xiaomi.mitv.upgrade)" \
      > "$STATE_DIR/packages.tsv"
  fi
  if run_retry_logged /system/bin/pm disable-user --user 0 com.xiaomi.mitv.upgrade; then
    log "disabled package: com.xiaomi.mitv.upgrade"
  else
    log "failed to disable package: com.xiaomi.mitv.upgrade"
  fi
fi

if [ "$(read_option APPLY_AD_SETTINGS)" = "1" ]; then
  apply_setting global mitv.settings.advertise.state 1
  apply_setting system boot_ad_switch 0
  apply_setting system personalized_ad 0
  apply_setting system personalized_recommendation 0
fi

log "service complete: Home ownership remains with mitv-home-bridge"
