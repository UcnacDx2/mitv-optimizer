#!/system/bin/sh

STATE_DIR="$1"
PORT="$2"
LOG_FILE="$STATE_DIR/optimizer.log"
PID_FILE="$STATE_DIR/adb-monitor.pid"

mkdir -p "$STATE_DIR"

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    exit 0
  fi
fi

printf '%s\n' "$$" > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

sleep 15
log "ADB monitor started: port=$PORT pid=$$"

while true; do
  state="$(getprop init.svc.adbd)"
  current_port="$(getprop service.adb.tcp.port)"
  if [ "$state" != "running" ] || [ "$current_port" != "$PORT" ]; then
    log "ADB monitor: unhealthy state=$state service_port=$current_port; reapplying TCP port $PORT and restarting adbd"
    /system/bin/settings put global adb_enabled 1 2>/dev/null || true
    /system/bin/setprop persist.adb.tcp.port "$PORT" 2>/dev/null || true
    /system/bin/setprop service.adb.tcp.port "$PORT" 2>/dev/null || true
    /system/bin/stop adbd 2>/dev/null || true
    /system/bin/start adbd 2>/dev/null || true
    sleep 2
    log "ADB monitor: restart result state=$(getprop init.svc.adbd) service_port=$(getprop service.adb.tcp.port)"
  fi
  sleep 10
done
