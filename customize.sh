#!/system/bin/sh

SKIPUNZIP=0

ui_print "*******************************"
ui_print "       MiTV Optimizer"
ui_print "*******************************"

$BOOTMODE || abort "Install from the Magisk app after Android has booted"

install_or_capture_package() {
  pkg="$1"
  dest="$2"
  label="$3"
  enabled="$4"
  artifact="$5"

  [ "$enabled" = "1" ] || return 0

  # Release builds ship the APKs in artifacts/. Capture is only a compatibility
  # fallback for locally assembled modules that omitted one of those files.
  if [ -n "$artifact" ] && [ -f "$MODPATH/artifacts/$artifact" ]; then
    mkdir -p "$dest" || abort "Cannot create $dest"
    cp -af "$MODPATH/artifacts/$artifact" "$dest/base.apk" \
      || abort "Cannot install bundled $label APK"
    ui_print "- Installed bundled $label APK"
    return 0
  fi

  paths="$(pm path "$pkg" 2>/dev/null | sed 's/^package://')"
  [ -n "$paths" ] || abort "$label is not installed: $pkg"

  mkdir -p "$dest" || abort "Cannot create $dest"
  echo "$paths" | while IFS= read -r src; do
    [ -n "$src" ] || continue
    name="${src##*/}"
    cp -af "$src" "$dest/$name" || exit 1
  done
  [ "$?" = "0" ] || abort "Cannot capture $label APK"
  ui_print "- Captured $label from the installed package"
}

. "$MODPATH/options.conf"

# Capture installed proprietary applications instead of redistributing them.
install_or_capture_package \
  com.dangbei1.tvlauncherx \
  "$MODPATH/system/priv-app/DangBeiTVLauncher" \
  "Dangbei launcher" \
  "$SYSTEMIZE_DANGBEI" \
  "com.dangbei1.tvlauncherx.apk"

install_or_capture_package \
  com.ucnacdx2.mitvhomebridge \
  "$MODPATH/system/app/MiTVHomeBridge" \
  "MiTV Home bridge" \
  "$SYSTEMIZE_HOME_BRIDGE" \
  "mitv-home-bridge.apk"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

ui_print "- Configuration installed"
ui_print "- Reboot once, then run the module action for status"
