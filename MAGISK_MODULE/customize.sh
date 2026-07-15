#!/system/bin/sh
# Fake BL Manager - Magisk Module
# Author: Fake BL Manager Team
# Version: 1.0.0

ui_print "============================================="
ui_print "  Fake BL Manager v1.0.0"
ui_print "  Simple, Safe, Controlled Installation"
ui_print "============================================="

LANG="en"
if [ -f "$MODPATH/lang.txt" ]; then
    USER_LANG=$(cat "$MODPATH/lang.txt" | tr -d '[:space:]')
    if [ "$USER_LANG" = "zh" ]; then
        LANG="zh"
    fi
fi

if [ "$LANG" = "zh" ]; then
  ui_print "[已选择中文 / Chinese selected]"
else
  ui_print "[English selected / 已选择英文]"
fi

# Setup paths
BY_NAME_DIR="/dev/block/by-name"
RUNTIME_DIR="$MODPATH/tmp"
LOG_FILE="$RUNTIME_DIR/install.log"
WEB_SERVER_PORT=8080

# Create directories
mkdir -p "$RUNTIME_DIR"
mkdir -p "$MODPATH/webroot"

# Copy binaries to runtime
cp "$MODPATH/bin/extractfv" "$RUNTIME_DIR/"
cp "$MODPATH/bin/patch_abl" "$RUNTIME_DIR/"
cp "$MODPATH/bin/elf_inject" "$RUNTIME_DIR/"
cp "$MODPATH/bin/GenFw" "$RUNTIME_DIR/"
chmod +x "$RUNTIME_DIR/"*

# Initialize log
: > "$LOG_FILE"

# Logging function
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Get current slot
detect_current_slot() {
    case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
        _a) echo "_a" ;;
        _b) echo "_b" ;;
        *) return 1 ;;
    esac
}

# Check GBL vulnerability
check_gbl() {
    local abl_part="$BY_NAME_DIR/abl$current_slot"
    
    log_msg "Checking GBL vulnerability..."
    
    $RUNTIME_DIR/extractfv -o "$RUNTIME_DIR" -v "$abl_part" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_msg "Extract failed"
        return 1
    fi
    
    $RUNTIME_DIR/patch_abl "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi" >> "$LOG_FILE" 2>&1
    
    if [ ! -f "$RUNTIME_DIR/patched.efi" ]; then
        log_msg "Patch failed"
        return 2
    fi
    
    if grep -q "Warning: Failed to patch ABL GBL" "$LOG_FILE"; then
        log_msg "GBL not found"
        return 3
    fi
    
    log_msg "GBL found"
    return 0
}

# Check ABL version
check_abl_version() {
    local version=$(getprop ro.build.version.incremental 2>/dev/null)
    version=$(echo "$version" | sed 's/[^0-9.]//g')
    
    if [ -z "$version" ]; then
        log_msg "Version unknown"
        return 0
    fi
    
    local patch=$(echo "$version" | cut -d. -f3)
    
    if [ "$patch" -ge 300 ] 2>/dev/null; then
        log_msg "Version >= 300, may need downgrade"
        return 1
    fi
    
    log_msg "Version compatible"
    return 0
}

# Perform installation
do_install() {
    local current_slot=$(detect_current_slot)
    
    if [ -z "$current_slot" ]; then
        ui_print "Cannot detect current slot"
        log_msg "Slot detection failed"
        return 1
    fi
    
    ui_print "Checking GBL..."
    check_gbl
    gbl_result=$?
    
    if [ $gbl_result -ne 0 ]; then
        ui_print "GBL exploit not found"
        log_msg "GBL check failed"
        return 2
    fi
    
    ui_print "Patching ABL..."
    
    # Patch ABL
    $RUNTIME_DIR/extractfv -o "$RUNTIME_DIR" -v "$BY_NAME_DIR/abl$current_slot" >> "$LOG_FILE" 2>&1
    $RUNTIME_DIR/patch_abl "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi" >> "$LOG_FILE" 2>&1
    
    if [ ! -f "$RUNTIME_DIR/patched.efi" ]; then
        ui_print "Patch failed"
        return 3
    fi
    
    # Inject superfastboot if available
    if [ -f "$MODPATH/loader.elf" ]; then
        ui_print "Injecting superfastboot..."
        $RUNTIME_DIR/elf_inject "$MODPATH/loader.elf" "$RUNTIME_DIR/patched.efi" "$RUNTIME_DIR/injected.dll" >> "$LOG_FILE" 2>&1
        if [ -f "$RUNTIME_DIR/injected.dll" ]; then
            $RUNTIME_DIR/GenFw -e UEFI_APPLICATION -o "$RUNTIME_DIR/patched.efi" "$RUNTIME_DIR/injected.dll" >> "$LOG_FILE" 2>&1
        fi
    fi
    
    # Flash to efisp
    ui_print "Flashing to efisp..."
    blockdev --setrw "$BY_NAME_DIR/efisp" >> "$LOG_FILE" 2>&1
    dd if="$RUNTIME_DIR/patched.efi" of="$BY_NAME_DIR/efisp" bs=4M conv=fsync >> "$LOG_FILE" 2>&1
    sync
    
    ui_print "Installation complete!"
    log_msg "Installation complete"
    return 0
}

# Show status
show_status() {
    local current_slot=$(detect_current_slot)
    
    ui_print "Current slot: $current_slot"
    ui_print "Module installed: Yes"
    ui_print "Web UI: http://localhost:$WEB_SERVER_PORT"
    
    # Check if already patched
    if strings "$BY_NAME_DIR/efisp" 2>/dev/null | grep -q "superfastboot"; then
        ui_print "Patch status: Installed"
    else
        ui_print "Patch status: Not installed"
    fi
}

# Start web server for UI
start_web_server() {
    # Simple HTTP server using Python or toybox
    if [ -f "$(which python3 2>/dev/null)" ]; then
        cd "$MODPATH/webroot"
        python3 -m http.server $WEB_SERVER_PORT &
    elif [ -f "$(which toybox 2>/dev/null)" ]; then
        cd "$MODPATH/webroot"
        toybox httpd -p $WEB_SERVER_PORT &
    fi
    
    log_msg "Web server started on port $WEB_SERVER_PORT"
}

# Main execution
case "$1" in
    install)
        ui_print "Starting installation..."
        do_install
        exit $?
        ;;
    status)
        show_status
        ;;
    start-web)
        start_web_server
        ;;
    *)
        # Auto mode - install if not already installed
        ui_print "Fake BL Manager Module"
        ui_print "Checking installation status..."
        
        # Check if already installed
        if strings "$BY_NAME_DIR/efisp" 2>/dev/null | grep -q "superfastboot"; then
            ui_print "Already installed. Starting web UI..."
            start_web_server
        else
            ui_print "Not installed. Installing..."
            do_install
        fi
        ;;
esac
