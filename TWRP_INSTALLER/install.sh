#!/sbin/sh
# Fake BL Manager - TWRP Installer v1.0.0
# Author: antocorvo3000
#
# Supports: Xiaomi 17 series (popsicle), other Snapdragon 8 Gen 5 / Elite devices
#
# Logic:
# - Xiaomi 17 series (popsicle, 2509FPN*, etc.): auto-downgrade ABL if >= 300, then flash patched efisp
# - Other devices: check GBL, if ABL >= 300 prompt user to flash old ABL via fastboot first

ui_print "================================================"
ui_print "  Fake BL Manager v1.0.0"
ui_print "  Simple, Safe, Controlled Installation"
ui_print "================================================"
ui_print "  Author: antocorvo3000"
ui_print "  https://github.com/antocorvo3000/fake-bl-manager"
ui_print "================================================"

# Variables
MODDIR="${0%/*}"
BY_NAME="/dev/block/by-name"
RUNTIME_DIR="/tmp/fake_bl"
LOG_FILE="$RUNTIME_DIR/install.log"

# Create runtime dir and redirect output
mkdir -p "$RUNTIME_DIR"
exec > "$LOG_FILE" 2>&1

# Device info
MODEL=$(getprop ro.product.model 2>/dev/null)
CODENAME=$(getprop ro.product.name 2>/dev/null)
SOC=$(getprop ro.board.platform 2>/dev/null)
VERSION=$(getprop ro.build.version.incremental 2>/dev/null)
ABI=$(getprop ro.product.cpu.abi 2>/dev/null)

print_msg() {
    ui_print "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Xiaomi 17 series detection (popsicle, 2509FPN*, etc.)
is_xiaomi_17_series() {
    case "$MODEL" in
        *17*Pro*Max*|*17Pro*Max*) return 0 ;;
        *17*Pro*|*17Pro*) return 0 ;;
        *17*Ultra*|*17Ultra*) return 0 ;;
        *17*|*canoe*|*popsicle*) return 0 ;;
        *2509FPN*) return 0 ;;
    esac
    case "$CODENAME" in
        popsicle|canoe) return 0 ;;
        *17*) return 0 ;;
    esac
    return 1
}

# Extract ABL version number from string like "OS3.0.315.0.WPBCNXM" -> "315"
get_abl_ver() {
    local ver="$1"
    echo "$ver" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | cut -d. -f3
}

# Check GBL exploit on given ABL partition
check_gbl_on_abl() {
    local abl_part="$1"
    
    if [ ! -f "$abl_part" ]; then
        return 1
    fi
    
    # Extract FV
    $MODDIR/bin/extractfv -o "$RUNTIME_DIR" -v "$abl_part" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    if [ ! -f "$RUNTIME_DIR/LinuxLoader.efi" ]; then
        return 1
    fi
    
    # Try patching
    $MODDIR/bin/patch_abl "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi" >> "$LOG_FILE" 2>&1
    
    if [ ! -f "$RUNTIME_DIR/patched.efi" ]; then
        return 1
    fi
    
    # Check results
    if grep -q "Sink patched successfully" "$LOG_FILE"; then
        return 0  # GBL OK
    elif grep -q "Warning:" "$LOG_FILE"; then
        return 2  # GBL issues
    else
        return 1  # Failed
    fi
}

# Find ABL partition for current slot
find_abl_partition() {
    local slot=""
    
    case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
        _a) slot="_a" ;;
        _b) slot="_b" ;;
    esac
    
    # Try standard by-name path first
    if [ -f "$BY_NAME/abl$slot" ]; then
        echo "$BY_NAME/abl$slot"
        return 0
    fi
    
    # Try bootloader by-name path
    if [ -f "/dev/block/bootloader/by-name/abl$slot" ]; then
        echo "/dev/block/bootloader/by-name/abl$slot"
        return 0
    fi
    
    # Fallback to active slot
    for part in abl_active abl_a abl_b abl; do
        if [ -f "$BY_NAME/$part" ]; then
            echo "$BY_NAME/$part"
            return 0
        fi
        if [ -f "/dev/block/bootloader/by-name/$part" ]; then
            echo "/dev/block/bootloader/by-name/$part"
            return 0
        fi
    done
    
    return 1
}

# Flash patched EFI to efisp
flash_to_efisp() {
    local patched_file="$1"
    
    # Find efisp partition
    local efisp=""
    for path in "$BY_NAME/efisp" "/dev/block/bootloader/by-name/efisp"; do
        if [ -f "$path" ]; then
            efisp="$path"
            break
        fi
    done
    
    if [ -z "$efisp" ]; then
        print_msg "  ❌ efisp partition not found"
        return 1
    fi
    
    print_msg "  Found efisp: $efisp"
    
    # Set read-write
    blockdev --setrw "$efisp" >> "$LOG_FILE" 2>&1
    
    # Flash
    dd if="$patched_file" of="$efisp" bs=4M conv=fsync >> "$LOG_FILE" 2>&1
    sync
    
    if [ $? -eq 0 ]; then
        print_msg "  ✅ Patched ABL flashed to efisp"
        return 0
    else
        print_msg "  ❌ Flash failed"
        return 1
    fi
}

# Downgrade ABL partition
downgrade_abl() {
    local abl_img="$1"
    
    # Find ABL partitions
    local abl_a="" abl_b=""
    for slot in _a _b; do
        for path in "$BY_NAME/abl$slot" "/dev/block/bootloader/by-name/abl$slot"; do
            if [ -f "$path" ]; then
                if [ "$slot" = "_a" ]; then abl_a="$path"; else abl_b="$path"; fi
            fi
        done
    done
    
    # Flash to both slots
    if [ -n "$abl_a" ]; then
        blockdev --setrw "$abl_a" >> "$LOG_FILE" 2>&1
        dd if="$abl_img" of="$abl_a" bs=4M conv=fsync >> "$LOG_FILE" 2>&1
        sync
        print_msg "  ✅ ABL downgraded (slot A)"
    fi
    
    if [ -n "$abl_b" ]; then
        blockdev --setrw "$abl_b" >> "$LOG_FILE" 2>&1
        dd if="$abl_img" of="$abl_b" bs=4M conv=fsync >> "$LOG_FILE" 2>&1
        sync
        print_msg "  ✅ ABL downgraded (slot B)"
    fi
    
    return 0
}

# ========== MAIN ==========

print_msg ""
print_msg "Device: $MODEL"
print_msg "Codename: $CODENAME"
print_msg "SOC: $SOC"
print_msg "Version: $VERSION"
print_msg ""

# Check if Xiaomi 17 series
if is_xiaomi_17_series; then
    XIAOMI_17=true
    print_msg "✅ Xiaomi 17 series detected (auto-downgrade available)"
else
    XIAOMI_17=false
    print_msg "ℹ️ Other Snapdragon 8 Gen 5 / Elite device"
fi

print_msg ""

# Find ABL partition
ABL_PART=$(find_abl_partition)
if [ -z "$ABL_PART" ]; then
    print_msg "❌ ERROR: Cannot find ABL partition"
    exit 1
fi
print_msg "ABL partition: $ABL_PART"

# Check GBL on current ABL
print_msg ""
print_msg "Step 1: Checking GBL exploit..."
check_gbl_on_abl "$ABL_PART"
gbl_result=$?

if [ $gbl_result -eq 0 ]; then
    print_msg "✅ GBL exploit detected on current ABL"
fi

# If GBL not found, need to downgrade
if [ $gbl_result -ne 0 ]; then
    print_msg "⚠️ GBL exploit NOT found (ABL may be patched)"
    
    if [ "$XIAOMI_17" = true ]; then
        print_msg ""
        print_msg "Xiaomi 17 series: auto-downgrading ABL..."
        
        # Check for bundled old ABL
        OLD_ABL=""
        for f in "$MODDIR/bin/"abl_old_"$CODENAME".* "$MODDIR/bin/abl_old.img"; do
            if [ -f "$f" ]; then
                OLD_ABL="$f"
                break
            fi
        done
        # Try popsicle fallback
        if [ -z "$OLD_ABL" ] && [ -f "$MODDIR/bin/abl_old_popsicle.img" ]; then
            OLD_ABL="$MODDIR/bin/abl_old_popsicle.img"
        fi
        
        if [ -n "$OLD_ABL" ]; then
            print_msg "  Found ABL downgrade: $OLD_ABL"
            downgrade_abl "$OLD_ABL"
            
            # Re-check GBL on downgraded ABL
            print_msg ""
            print_msg "  Re-checking GBL..."
            rm -f "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi"
            check_gbl_on_abl "$ABL_PART"
            gbl_result=$?
            
            if [ $gbl_result -eq 0 ]; then
                print_msg "  ✅ GBL exploit confirmed after downgrade"
            else
                print_msg "  ❌ GBL still not found after downgrade"
                exit 1
            fi
        else
            print_msg "❌ No ABL downgrade image found in package"
            print_msg "Flash ABL < OS3.0.300 manually, then retry"
            exit 1
        fi
    else
        # Non-Xiaomi-17: cannot auto-downgrade, prompt user
        print_msg ""
        print_msg "❌ GBL not found and auto-downgrade not available."
        print_msg ""
        print_msg "For non-Xiaomi-17 devices with ABL >= 300:"
        print_msg "  1. Download firmware with ABL < OS3.0.300"
        print_msg "  2. Reboot to fastboot"
        print_msg "  3. Run: fastboot flash abl abl.img"
        print_msg "  4. Reboot and re-run this installer"
        print_msg ""
        exit 1
    fi
fi

# Step 2: Patch and flash to efisp
print_msg ""
print_msg "Step 2: Patching ABL and flashing to efisp..."

# Check if we already have a pre-patched file for this device
PREPATCHED=""
for f in "$MODDIR/bin/ABL_patched_"${CODENAME}".img" "$MODDIR/bin/ABL_patched_"${MODEL}".img"; do
    if [ -f "$f" ]; then
        PREPATCHED="$f"
        break
    fi
done
# Try popsicle fallback
if [ -z "$PREPATCHED" ] && [ -f "$MODDIR/bin/ABL_patched_popsicle.img" ]; then
    PREPATCHED="$MODDIR/bin/ABL_patched_popsicle.img"
fi

if [ -n "$PREPATCHED" ]; then
    print_msg "  Using pre-patched ABL: $PREPATCHED"
    flash_to_efisp "$PREPATCHED"
    if [ $? -ne 0 ]; then
        exit 1
    fi
else
    # Dynamic patching
    print_msg "  Dynamically patching ABL..."
    
    # Extract
    rm -f "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi"
    $MODDIR/bin/extractfv -o "$RUNTIME_DIR" -v "$ABL_PART" >> "$LOG_FILE" 2>&1
    
    # Patch
    $MODDIR/bin/patch_abl "$RUNTIME_DIR/LinuxLoader.efi" "$RUNTIME_DIR/patched.efi" >> "$LOG_FILE" 2>&1
    
    if [ -f "$RUNTIME_DIR/patched.efi" ]; then
        flash_to_efisp "$RUNTIME_DIR/patched.efi"
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        print_msg "  ❌ Patching failed"
        exit 1
    fi
fi

# Done
print_msg ""
print_msg "================================================"
print_msg "  ✅ Fake BL installation complete!"
print_msg "================================================"
print_msg ""
print_msg "IMPORTANT: Format data is recommended."
print_msg "  - Reboot to Recovery"
print_msg "  - Format Data"
print_msg "  - Reboot to System"
print_msg ""
print_msg "If you skip format, device may show 'corrupted'."
print_msg ""
exit 0
