#!/system/bin/sh
# Fake BL Manager - Uninstall Script

ui_print "============================================="
ui_print "  Fake BL Manager - Uninstall"
ui_print "============================================="

BY_NAME_DIR="/dev/block/by-name"
RUNTIME_DIR="/data/adb/modules/fake_bl_manager/tmp"

# Restore original efisp if backup exists
if [ -f "$RUNTIME_DIR/efisp_backup.img" ]; then
    ui_print "Restoring original efisp..."
    blockdev --setrw "$BY_NAME_DIR/efisp"
    dd if="$RUNTIME_DIR/efisp_backup.img" of="$BY_NAME_DIR/efisp" bs=4M conv=fsync
    sync
    ui_print "Original efisp restored"
fi

# Remove service
ui_print "Removing service..."
rm -f /data/adb/modules/fake_bl_manager/tmp/service.pid
rm -f /data/adb/modules/fake_bl_manager/tmp/*.log

ui_print "Uninstall complete"
ui_print "Please reboot to complete"
