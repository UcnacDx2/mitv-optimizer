#!/system/bin/sh

STATE_DIR=/data/adb/mitv-optimizer
LOG_FILE=/data/adb/mitv-optimizer-uninstall.log
: > "$LOG_FILE"
TMP_DIR="/data/local/tmp/mitv-optimizer-restore-$$"
mkdir -p "$TMP_DIR"
chmod 0700 "$TMP_DIR"

for state_file in components.tsv packages.tsv settings.tsv; do
  if [ -f "$STATE_DIR/$state_file" ]; then
    cp -f "$STATE_DIR/$state_file" "$TMP_DIR/$state_file"
  fi
done

run_logged() {
  local output rc
  output="$("$@" 2>&1)"
  rc=$?
  [ -n "$output" ] && printf '%s\n' "$output" >> "$LOG_FILE"
  return "$rc"
}

restore_component() {
  local comp state
  comp="$1"
  state="$2"
  case "$state" in
    enabled) run_logged /system/bin/pm enable --user 0 "$comp" ;;
    disabled) run_logged /system/bin/pm disable --user 0 "$comp" ;;
    disabled-user) run_logged /system/bin/pm disable-user --user 0 "$comp" ;;
    disabled-until-used) run_logged /system/bin/pm disable-until-used --user 0 "$comp" ;;
    *) run_logged /system/bin/pm default-state --user 0 "$comp" ;;
  esac
}

if [ -f "$TMP_DIR/components.tsv" ]; then
  while IFS='|' read -r comp state; do
    [ -n "$comp" ] || continue
    restore_component "$comp" "$state"
  done < "$TMP_DIR/components.tsv"
fi

if [ -f "$TMP_DIR/packages.tsv" ]; then
  while IFS='|' read -r pkg state; do
    [ -n "$pkg" ] || continue
    case "$state" in
      disabled-user) run_logged /system/bin/pm disable-user --user 0 "$pkg" ;;
      *) run_logged /system/bin/pm enable --user 0 "$pkg" ;;
    esac
  done < "$TMP_DIR/packages.tsv"
fi

if [ -f "$TMP_DIR/settings.tsv" ]; then
  while IFS='|' read -r namespace key value; do
    [ -n "$namespace" ] && [ -n "$key" ] || continue
    if [ "$value" = "__NULL__" ]; then
      run_logged /system/bin/settings delete "$namespace" "$key"
    else
      run_logged /system/bin/settings put "$namespace" "$key" "$value"
    fi
  done < "$TMP_DIR/settings.tsv"
fi

if [ -s "$STATE_DIR/home.before" ]; then
  previous_home="$(cat "$STATE_DIR/home.before")"
  case "$previous_home" in
    */*) run_logged /system/bin/cmd package set-home-activity --user 0 "$previous_home" ;;
  esac
fi

rm -rf "$TMP_DIR"
rm -rf /data/adb/mitv-optimizer
