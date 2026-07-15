#!/sbin/sh
# GBL Vulnerability Detection Script
# Checks if the device has the GBL exploit

check_gbl_vulnerability() {
    local abl_part="$1"
    local runtime_dir="/tmp/fake_bl"
    
    # Default to current slot if not specified
    if [ -z "$abl_part" ]; then
        case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
            _a) abl_part="/dev/block/by-name/abl_a" ;;
            _b) abl_part="/dev/block/by-name/abl_b" ;;
            *) abl_part="/dev/block/by-name/abl" ;;
        esac
    fi
    
    if [ ! -f "$abl_part" ]; then
        return 1
    fi
    
    # Extract FV
    extractfv -o "$runtime_dir" -v "$abl_part" >> "$runtime_dir/extract.log" 2>&1
    if [ $? -ne 0 ]; then
        return 2
    fi
    
    # Patch and check for GBL error
    patch_abl "$runtime_dir/LinuxLoader.efi" "$runtime_dir/patched.efi" >> "$runtime_dir/patch.log" 2>&1
    
    if [ ! -f "$runtime_dir/patched.efi" ]; then
        return 3
    fi
    
    # Check if patch was successful
    if grep -q "Warning: Failed to patch ABL GBL" "$runtime_dir/patch.log"; then
        return 4
    fi
    
    echo "FOUND"
    return 0
}

# Return codes:
# 0 = GBL found
# 1 = ABL partition not found
# 2 = Extraction failed
# 3 = Patch failed
# 4 = GBL exploit not found (patch failed)
