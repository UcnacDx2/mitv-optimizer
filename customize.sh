#!/system/bin/sh

# APKs are bundled under system/; installation only needs Magisk permissions.
SKIPUNZIP=0

ui_print "*******************************"
ui_print "       MiTV Optimizer"
ui_print "*******************************"
ui_print "- Stage: module-files-extracted"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/adb-monitor.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Stage: permissions-applied"
ui_print "- Configuration installed"
