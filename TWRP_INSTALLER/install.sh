#!/sbin/sh
# Fake BL Manager - TWRP Installer
# Version: 1.0.0
# Author: Fake BL Manager Team
#
# Simple, safe, and controlled installation of Fake Locked Bootloader

ui_print "================================================"
ui_print "  Fake BL Manager v1.0.0"
ui_print "  Simple, Safe, Controlled Installation"
ui_print "================================================"
ui_print ""

# Variables
MODDIR="${0%/*}"
BY_NAME="/dev/block/by-name"
RUNTIME_DIR="/tmp/fake_bl"
LOG_FILE="$RUNTIME_DIR/install.log"

# Create runtime dir
mkdir -p "$RUNTIME_DIR"
exec > "$LOG_FILE" 2>&1

# Load helper scripts
. "$MODDIR/scripts/detect_gbl.sh"
. "$MODDIR/scripts/check_abl_version.sh"
. "$MODDIR/scripts/check_rollback.sh"
. "$MODDIR/scripts/backup_all.sh"
. "$MODDIR/scripts/install_safe.sh"
. "$MODDIR/scripts/verify_install.sh"

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function: Print message
print_msg() {
    ui_print "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function: Print success
print_success() {
    ui_print "${GREEN}$1${NC}"
}

# Function: Print warning
print_warning() {
    ui_print "${YELLOW}$1${NC}"
}

# Function: Print error
print_error() {
    ui_print "${RED}$1${NC}"
}

# Function: Interactive menu for options
interactive_menu() {
    ui_print "================================================"
    ui_print "  Installation Options"
    ui_print "================================================"
    ui_print ""
    ui_print "Select options using volume keys:"
    ui_print ""
    ui_print "1. Format Data: $(if [ "$FORMAT_DATA" = "true" ]; then echo "YES (Recommended for first install)"; else echo "NO"; fi)"
    ui_print "2. Backup System: $(if [ "$BACKUP_SYSTEM" = "true" ]; then echo "YES"; else echo "NO (Not recommended)"; fi)"
    ui_print "3. ABL Downgrade: $(if [ "$DOWNGRADE_ABL" = "true" ]; then echo "YES"; else echo "NO"; fi)"
    ui_print ""
    ui_print "Volume Up: Confirm Installation"
    ui_print "Volume Down: Cancel"
    ui_print ""
}

# Default options
FORMAT_DATA="auto"
BACKUP_SYSTEM="true"
DOWNGRADE_ABL="auto"

# Main installation function
install_fake_bl() {
    print_msg "Starting installation..."
    
    # Step 1: Detect GBL
    print_msg "Step 1/6: Checking GBL vulnerability..."
    detect_gbl_result=$(check_gbl_vulnerability)
    if [ "$detect_gbl_result" != "FOUND" ]; then
        print_error "GBL exploit not found!"
        print_warning "This device may need ABL downgrade first"
        print_warning "Or the ABL version is too new (>= OS3.0.300)"
        abort "GBL exploit not found"
    fi
    print_success "GBL exploit detected"
    
    # Step 2: Check ABL version
    print_msg "Step 2/6: Checking ABL version..."
    abl_check_result=$(check_abl_compatibility)
    if [ "$abl_check_result" != "COMPATIBLE" ]; then
        print_warning "ABL version check failed"
        print_warning "Continuing anyway..."
    fi
    print_success "ABL version check completed"
    
    # Step 3: Check rollback version
    print_msg "Step 3/6: Checking rollback version..."
    rollback_check_result=$(check_rollback_version)
    if [ "$rollback_check_result" != "SAFE" ]; then
        print_warning "Rollback version not optimal"
        print_warning "Downgrade may be required"
    fi
    print_success "Rollback version check completed"
    
    # Step 4: Backup system
    if [ "$BACKUP_SYSTEM" = "true" ]; then
        print_msg "Step 4/6: Backing up system..."
        backup_result=$(backup_system)
        if [ "$backup_result" = "FAILED" ]; then
            print_error "Backup failed!"
            print_warning "Continuing without backup..."
        else
            print_success "Backup completed"
        fi
    else
        print_warning "Skipping backup (not recommended)"
    fi
    
    # Step 5: ABL Downgrade (if needed)
    if [ "$DOWNGRADE_ABL" = "true" ] || [ "$DOWNGRADE_ABL" = "auto" ]; then
        print_msg "Step 5/6: Checking ABL downgrade..."
        downgrade_result=$(check_downgrade_needed)
        if [ "$downgrade_result" = "NEEDED" ]; then
            print_msg "Performing ABL downgrade..."
            downgrade_result=$(perform_downgrade)
            if [ "$downgrade_result" = "FAILED" ]; then
                print_error "Downgrade failed!"
                abort "Downgrade failed"
            fi
            print_success "ABL downgrade completed"
        else
            print_msg "No downgrade needed"
        fi
    fi
    
    # Step 6: Install
    print_msg "Step 6/6: Installing Fake BL..."
    install_result=$(install_safe_patch)
    if [ "$install_result" = "FAILED" ]; then
        print_error "Installation failed!"
        
        # Try restore if backup exists
        if [ "$BACKUP_SYSTEM" = "true" ]; then
            print_msg "Attempting restore from backup..."
            restore_result=$(restore_system)
            if [ "$restore_result" = "SUCCESS" ]; then
                print_success "System restored from backup"
            fi
        fi
        
        abort "Installation failed"
    fi
    
    # Verify installation
    print_msg "Verifying installation..."
    verify_result=$(verify_installation)
    if [ "$verify_result" = "FAILED" ]; then
        print_warning "Verification failed!"
        print_warning "Installation may not be complete"
    else
        print_success "Installation verified"
    fi
    
    print_msg "Cleaning up..."
    rm -rf "$RUNTIME_DIR"
    
    print_success "================================================"
    print_success "Installation complete!"
    print_success "================================================"
    
    if [ "$FORMAT_DATA" = "true" ] || [ "$FORMAT_DATA" = "auto" ]; then
        print_warning "================================================"
        print_warning "IMPORTANT: Format data required!"
        print_warning "Please reboot to recovery and format data"
        print_warning "to complete the installation safely"
        print_warning "================================================"
    fi
    
    return 0
}

# Parse volume key input for interactive mode
parse_volume_keys() {
    while true; do
        keyevent=$(timeout 1 getevent -l 2>/dev/null)
        if echo "$keyevent" | grep -q "KEY_VOLUMEUP"; then
            echo "CONFIRM"
            break
        elif echo "$keyevent" | grep -q "KEY_VOLUMEDOWN"; then
            echo "CANCEL"
            break
        fi
    done
}

# Main execution
print_msg "Fake BL Manager starting..."
print_msg "Device: $(getprop ro.product.model)"
print_msg "SOC: $(getprop ro.board.platform)"
print_msg "Android: $(getprop ro.build.version.release)"

# Check if interactive mode
if [ "$1" = "interactive" ]; then
    # Interactive menu
    while true; do
        interactive_menu
        choice=$(parse_volume_keys)
        
        if [ "$choice" = "CONFIRM" ]; then
            install_fake_bl
            exit $?
        elif [ "$choice" = "CANCEL" ]; then
            print_msg "Installation cancelled by user"
            abort "Installation cancelled"
        fi
    done
else
    # Auto mode (non-interactive)
    print_msg "Running in auto mode..."
    install_fake_bl
fi
