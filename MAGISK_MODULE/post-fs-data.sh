# Fake BL Manager
# Simple, Safe, Controlled Installation

# Copy binaries
cp -f "$MODPATH/bin/extractfv" "$MODPATH/bin/patch_abl" "$MODPATH/bin/elf_inject" "$MODPATH/bin/GenFw" "/data/adb/modules/fake_bl_manager/bin/" 2>/dev/null || true

# Set permissions
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

# Copy loader.elf if exists
if [ -f "$MODPATH/loader.elf" ]; then
    cp "$MODPATH/loader.elf" "/data/adb/modules/fake_bl_manager/"
fi

# Create runtime directory
mkdir -p /data/adb/modules/fake_bl_manager/tmp
mkdir -p /data/adb/modules/fake_bl_manager/bin

# Copy binaries to runtime
cp -f "$MODPATH/bin/"* /data/adb/modules/fake_bl_manager/bin/
