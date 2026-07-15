#!/system/bin/sh
# Fake BL Manager - Magisk Module Service
# Background service for monitoring and OTA protection

MODPATH="${0%/*}"
RUNTIME_DIR="$MODPATH/tmp"
LOG_FILE="$RUNTIME_DIR/service.log"
PID_FILE="$RUNTIME_DIR/service.pid"

BY_NAME_DIR="/dev/block/by-name"

mkdir -p "$RUNTIME_DIR"

# Logging
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check if OTA completed
check_ota_completed() {
    # Check if boot completed
    boot_completed=$(getprop sys.boot_completed)
    if [ "$boot_completed" = "1" ]; then
        return 0
    fi
    return 1
}

# Get current version
get_current_version() {
    getprop ro.build.version.incremental 2>/dev/null | sed 's/[^0-9.]//g'
}

# Get stored version
get_stored_version() {
    if [ -f "$RUNTIME_DIR/version.txt" ]; then
        cat "$RUNTIME_DIR/version.txt"
    else
        echo ""
    fi
}

# Auto-patch after OTA
auto_patch_ota() {
    log_msg "OTA detected, auto-patching..."
    
    current_version=$(get_current_version)
    stored_version=$(get_stored_version)
    
    if [ "$current_version" != "$stored_version" ]; then
        log_msg "Version changed: $stored_version -> $current_version"
        
        # Check if downgrade needed
        current_patch=$(echo "$current_version" | cut -d. -f3)
        if [ "$current_patch" -ge 300 ] 2>/dev/null; then
            log_msg "Version >= 300, checking downgrade..."
            # TODO: Implement downgrade check
        fi
        
        # Auto-install patch
        log_msg "Auto-installing patch..."
        $MODPATH/bin/extractfv -o "$RUNTIME_DIR" -v "$BY_NAME_DIR/abl$current_slot" >> "$LOG_FILE" 2>&1
        $MODPATH/bin/patch_abl "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi" >> "$LOG_FILE" 2>&1
        
        if [ -f "$RUNTIME_DIR/patched.efi" ]; then
            blockdev --setrw "$BY_NAME_DIR/efisp" >> "$LOG_FILE" 2>&1
            dd if="$RUNTIME_DIR/patched.efi" of="$BY_NAME_DIR/efisp" bs=4M conv=fsync >> "$LOG_FILE" 2>&1
            sync
            
            log_msg "Auto-patch completed"
            
            # Store new version
            echo "$current_version" > "$RUNTIME_DIR/version.txt"
        fi
    fi
}

# Main service loop
main() {
    log_msg "Fake BL Manager service starting"
    
    # Store PID
    echo $$ > "$PID_FILE"
    
    # Wait for boot completion
    log_msg "Waiting for boot completion..."
    while true; do
        if check_ota_completed; then
            log_msg "Boot completed"
            break
        fi
        sleep 5
    done
    
    # Perform initial check
    current_version=$(get_current_version)
    echo "$current_version" > "$RUNTIME_DIR/version.txt"
    log_msg "Initial version stored: $current_version"
    
    # Monitor for version changes (OTA)
    log_msg "Starting OTA monitor..."
    while true; do
        current_version=$(get_current_version)
        stored_version=$(get_stored_version)
        
        if [ "$current_version" != "$stored_version" ]; then
            log_msg "Version change detected: $stored_version -> $current_version"
            auto_patch_ota
        fi
        
        sleep 300  # Check every 5 minutes
    done
}

# Start service
main
