#!/system/bin/sh

MODDIR="${0%/*}"
STATE_DIR=/data/adb/mitv-optimizer

echo "MiTV Optimizer status"
echo "device: $(getprop ro.product.device)"
echo "build:  $(getprop ro.build.version.incremental)"
echo "home:"
cmd package resolve-activity --brief \
  -a android.intent.action.MAIN \
  -c android.intent.category.HOME 2>/dev/null | tail -n 1
echo "packages:"
for pkg in \
  com.dangbei1.tvlauncherx \
  com.ucnacdx2.mitvhomebridge \
  com.xiaomi.mitv.upgrade; do
  pm path "$pkg" 2>/dev/null | head -n 1
done
echo "component settings:"
components="$(sed '/^[[:space:]]*$/d' "$MODDIR/components-ad.txt")"
for comp in $components; do
  [ -n "$comp" ] || continue
  pkg="${comp%%/*}"
  class="${comp#*/}"
  case "$class" in .*) class="${pkg}${class}" ;; esac
  state="$(dumpsys package "$pkg" 2>/dev/null | awk -v target="$class" '
    /^[[:space:]]*User 0:/ { in_user=1; section=""; next }
    in_user && /^[[:space:]]*User [1-9][0-9]*:/ { exit }
    in_user && /^[[:space:]]+disabledComponents:/ { section="disabled"; next }
    in_user && /^[[:space:]]+enabledComponents:/ { section="enabled"; next }
    in_user && /^[[:space:]]+[[:alnum:]_. -]+:/ { section="" }
    in_user && section != "" && $1 == target { print section; exit }
  ')"
  [ -n "$state" ] || state=default
  echo "$state $comp"
done
for comp in \
  com.xiaomi.mitv.settings/com.xiaomi.mitv.settings.entry.FallbackHome \
  com.mitv.tvhome/com.mitv.tvhome.MainActivityUserMode; do
  pkg="${comp%%/*}"
  class="${comp#*/}"
  case "$class" in .*) class="${pkg}${class}" ;; esac
  state="$(dumpsys package "$pkg" 2>/dev/null | awk -v target="$class" '
    /^[[:space:]]*User 0:/ { in_user=1; section=""; next }
    in_user && /^[[:space:]]*User [1-9][0-9]*:/ { exit }
    in_user && /^[[:space:]]+disabledComponents:/ { section="disabled"; next }
    in_user && /^[[:space:]]+enabledComponents:/ { section="enabled"; next }
    in_user && /^[[:space:]]+[[:alnum:]_. -]+:/ { section="" }
    in_user && section != "" && $1 == target { print section; exit }
  ')"
  [ -n "$state" ] || state=default
  echo "$state $comp"
done
echo "log:"
tail -n 20 "$STATE_DIR/optimizer.log" 2>/dev/null
