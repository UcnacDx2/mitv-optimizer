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

LOCK_FILE="$STATE_DIR/service.pid"
if [ -f "$LOCK_FILE" ]; then
  old_pid="$(cat "$LOCK_FILE" 2>/dev/null | tr -d '\r')"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    log "service skipped: another instance is active pid=$old_pid"
    exit 0
  fi
  rm -f "$LOCK_FILE"
fi
# Recover the directory lock left by older module versions after an interrupted
# service run. It is no longer used as the lock primitive.
rmdir "$STATE_DIR/service.lock" 2>/dev/null || true
printf '%s\n' "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

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

snapshot_appop() {
  local snapshot_package snapshot_op current_mode
  snapshot_package="$1"
  snapshot_op="$2"
  [ -f "$STATE_DIR/appops.tsv" ] || : > "$STATE_DIR/appops.tsv"
  grep -Fq "${snapshot_package}|${snapshot_op}|" "$STATE_DIR/appops.tsv" 2>/dev/null && return
  # An op left at its default is dropped from the listing entirely, so an empty
  # parse means "default" rather than "unknown".
  current_mode="$(/system/bin/cmd appops get --user 0 "$snapshot_package" "$snapshot_op" 2>/dev/null | \
    sed -n "s/^${snapshot_op}: //p" | head -n 1 | tr -d '\r')"
  [ -n "$current_mode" ] || current_mode="default"
  printf '%s|%s|%s\n' "$snapshot_package" "$snapshot_op" "$current_mode" >> "$STATE_DIR/appops.tsv"
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

# The package installer refuses to install packages the vendor ROM has not
# approved, and it enforces that by rewriting system settings through its
# WRITE_SETTINGS appop. Removing that appop leaves the installer without the
# capability, and clearing pi_config drops the approval list it wrote. This needs
# root: the appop belongs to another package, so a non-privileged caller cannot
# change it, and `settings --user 0` additionally needs MANAGE_USERS. The bridge
# app runs the same sequence through su, but only when the user opens it; here it
# applies on every boot without that.
INSTALLER_PACKAGE="com.android.packageinstaller"
PI_CONFIG_KEY="pi_config"
PI_CONFIG_VALUE='{"pi_intercept_switch":false,"app_pi_control":false}'

remove_installer_restriction() {
  snapshot_appop "$INSTALLER_PACKAGE" WRITE_SETTINGS
  if run_retry_logged /system/bin/cmd appops set --user 0 "$INSTALLER_PACKAGE" WRITE_SETTINGS deny; then
    log "installer restriction: WRITE_SETTINGS deny applied"
  else
    log "installer restriction: could not deny WRITE_SETTINGS"
  fi

  snapshot_setting system "$PI_CONFIG_KEY"
  # Delete before the put so a stale value cannot survive a rejected write.
  run_retry_logged /system/bin/settings delete system "$PI_CONFIG_KEY"
  if run_retry_logged /system/bin/settings put system "$PI_CONFIG_KEY" "$PI_CONFIG_VALUE"; then
    log "installer restriction: pi_config=$(/system/bin/settings get system "$PI_CONFIG_KEY" 2>/dev/null | tr -d '\r')"
  else
    log "installer restriction: could not write pi_config"
  fi

  run_retry_logged /system/bin/am force-stop --user 0 "$INSTALLER_PACKAGE"
  log "installer restriction applied: appop=$(/system/bin/cmd appops get --user 0 "$INSTALLER_PACKAGE" WRITE_SETTINGS 2>/dev/null | tr '\n' ' ')"
}

apply_adb() {
  local port ready i listening adb_value
  port="$(read_option ADB_PORT)"
  [ -n "$port" ] || port=5555
  setprop persist.adb.tcp.port "$port"
  setprop service.adb.tcp.port "$port"
  setprop sys.set_adb_disabled 1

  # Wait for the Settings provider instead of sleeping a fixed amount. The
  # Xiaomi boot receiver can otherwise overwrite adb_enabled during startup.
  ready=0
  i=0
  while [ "$i" -lt 20 ]; do
    adb_value="$(/system/bin/settings get global adb_enabled 2>/dev/null | tr -d '\r')"
    case "$adb_value" in
      0|1|null)
      ready=1
      break
      ;;
    esac
    sleep 1
    i=$((i + 1))
  done
  if [ "$ready" -eq 1 ]; then
    sleep 5
    /system/bin/settings put global adb_enabled 1
    log "adb settings: enabled=$(/system/bin/settings get global adb_enabled 2>/dev/null) port=$port"
  else
    log "adb settings service not ready; watchdog will retry"
  fi

  setprop ctl.stop adbd
  sleep 1
  setprop ctl.start adbd

  watchdog_pid_file="$STATE_DIR/adb-watchdog.pid"
  if [ -f "$watchdog_pid_file" ] && kill -0 "$(cat "$watchdog_pid_file" 2>/dev/null)" 2>/dev/null; then
    log "adb watchdog already active pid=$(cat "$watchdog_pid_file")"
    return 0
  fi

  adb_watchdog() {
    while true; do
      listening=0
      if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -q ":$port " && listening=1
      elif command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -q ":$port " && listening=1
      fi
      if [ "$listening" -eq 0 ]; then
        /system/bin/settings put global adb_enabled 1 2>/dev/null || true
        setprop persist.adb.tcp.port "$port"
        setprop service.adb.tcp.port "$port"
        setprop ctl.stop adbd
        sleep 1
        setprop ctl.start adbd
        log "adb watchdog restarted adbd port=$port"
      fi
      sleep 30
    done
  }
  adb_watchdog &
  printf '%s\n' "$!" > "$watchdog_pid_file"
  log "adb service configured: port=$port"
}

# FallbackHome is the ROM recovery launcher. The bridge disables it only after
# it confirms a usable third-party Home. If the selected Home later goes missing
# or gets disabled while the vendor Home stays disabled, nothing answers HOME
# and the TV boots onto a black screen. This guard re-enables FallbackHome in
# that one case so the device stays enterable. It only ever *enables* the
# component, and only after HOME resolution has actually failed, so it cannot
# override or fight a healthy Home.
FALLBACK_HOME_COMP="com.xiaomi.mitv.settings/.entry.FallbackHome"
FALLBACK_HOME_PKG="com.xiaomi.mitv.settings"
FALLBACK_HOME_CLASS="com.xiaomi.mitv.settings.entry.FallbackHome"
BRIDGE_PACKAGE="com.ucnacdx2.mitvhomebridge"

resolved_home() {
  /system/bin/cmd package resolve-activity --brief \
    -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | \
    grep '/' | tail -n 1 | tr -d '\r'
}

home_ready() {
  # Bounded re-check so a transient empty resolution during startup is not
  # mistaken for a missing Home.
  local attempt
  attempt=0
  while [ "$attempt" -lt 3 ]; do
    [ -n "$(resolved_home)" ] && return 0
    sleep 2
    attempt=$((attempt + 1))
  done
  [ -n "$(resolved_home)" ]
}

# Least-privileged first: this script already runs as root, so the plain command
# normally succeeds. The verified TvService temporary-root path and su are only
# reached if that somehow did not make HOME resolve again.
enable_fallback_via_tvservice() {
  local script_path
  script_path="/sdcard/Download/mitv-optimizer-fallback.sh"
  {
    printf '%s\n' '#!/system/bin/sh'
    printf '%s\n' 'export PATH=/system/bin:/system/xbin:$PATH'
    printf '%s\n' "/system/bin/service call package 83 i32 1 s16 '$FALLBACK_HOME_PKG' s16 '$FALLBACK_HOME_CLASS' i32 1 i32 0 i32 0 s16 '$BRIDGE_PACKAGE'"
  } > "$script_path" 2>/dev/null || return 1
  chmod 0755 "$script_path" 2>/dev/null || true
  /system/bin/service call TvService 4400 s16 s s16 "$script_path" >/dev/null 2>&1
  rm -f "$script_path" 2>/dev/null || true
  return 0
}

enable_fallback_via_su() {
  command -v su >/dev/null 2>&1 || return 1
  su -c "pm enable --user 0 $FALLBACK_HOME_COMP" >/dev/null 2>&1
}

recover_missing_home() {
  log "boot guard: home=$(resolved_home)"
  if home_ready; then
    return 0
  fi
  log "boot guard: no HOME activity resolved; FallbackHome state=$(component_state "$FALLBACK_HOME_COMP")"

  local recovered
  recovered=0
  if run_retry_logged /system/bin/pm enable --user 0 "$FALLBACK_HOME_COMP"; then
    sleep 1
    [ -n "$(resolved_home)" ] && recovered=1 && log "boot guard: FallbackHome enabled via pm"
  fi
  if [ "$recovered" -eq 0 ] && enable_fallback_via_tvservice; then
    sleep 1
    [ -n "$(resolved_home)" ] && recovered=1 && log "boot guard: FallbackHome enabled via TvService"
  fi
  if [ "$recovered" -eq 0 ] && enable_fallback_via_su; then
    sleep 1
    [ -n "$(resolved_home)" ] && recovered=1 && log "boot guard: FallbackHome enabled via su"
  fi

  if [ "$recovered" -eq 1 ]; then
    log "boot guard: HOME recovered: $(resolved_home)"
  else
    log "boot guard: WARNING home still unresolved after FallbackHome recovery"
  fi
  return 0
}

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 8
log "service start: device=$(getprop ro.product.device) build=$(getprop ro.build.version.incremental)"

if [ "$(read_option ENABLE_ADB)" = "1" ]; then
  apply_adb
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

if [ "$(read_option DISABLE_INSTALLER_RESTRICTION)" = "1" ]; then
  remove_installer_restriction
fi

if [ "$(read_option DISABLE_BOOT_HOME_GUARD)" != "1" ]; then
  recover_missing_home
fi

log "service complete: Home ownership remains with mitv-home-bridge"
