#!/system/bin/sh

SKIPUNZIP=0
ui_print "POC_STAGE_CUSTOMIZE_ENTERED"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
ui_print "POC_STAGE_PERMISSIONS_APPLIED"
ui_print "POC_RESULT_INSTALLER_PATH_OK"
