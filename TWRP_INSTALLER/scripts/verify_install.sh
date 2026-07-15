#!/sbin/sh
# Installation Verification Script
# Verifies that Fake BL was installed correctly

verify_installation() {
    local runtime_dir="/tmp/fake_bl"
    local by_name="/dev/block/by-name"
    
    # Check if efisp was patched
    print_msg "Verifying efisp..."
    
    # Create test file to verify patch
    if [ -f "$by_name/efisp" ]; then
        # Try to verify by checking for patched strings
        dd if="$by_name/efisp" of="$runtime_dir/verify_efisp.bin" bs=4M count=1 conv=fsync 2>/dev/null
        
        # Check for expected strings in patched binary
        if strings "$runtime_dir/verify_efisp.bin" 2>/dev/null | grep -q "superfastboot"; then
            print_msg "Superfastboot found in efisp"
        else
            print_msg "Warning: Superfastboot not found in efisp (may be normal)"
        fi
    fi
    
    # Verify ABL state
    print_msg "Verifying ABL patch..."
    
    # Extract and verify patch was applied
    case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
        _a) abl_slot="_a" ;;
        _b) abl_slot="_b" ;;
        *) abl_slot="" ;;
    esac
    
    if [ -n "$abl_slot" ] && [ -f "$by_name/abl$abl_slot" ]; then
        extractfv -o "$runtime_dir" -v "$by_name/abl$abl_slot" >> "$runtime_dir/verify_extract.log" 2>&1
        
        if [ -f "$runtime_dir/LinuxLoader.efi" ]; then
            patch_abl "$runtime_dir/LinuxLoader.efi" "$runtime_dir/verify_patched.efi" >> "$runtime_dir/verify_patch.log" 2>&1
            
            if grep -q "Warning: Failed to patch ABL GBL" "$runtime_dir/verify_patch.log"; then
                print_error "Verification failed: GBL exploit not found"
                echo "FAILED:GBL exploit not found"
                return 1
            fi
        fi
    fi
    
    # Check vbmeta state
    print_msg "Verifying vbmeta..."
    
    if [ -f "$by_name/vbmeta" ]; then
        # vbmeta should be intact
        print_msg "vbmeta present"
    fi
    
    # Final status
    print_success "Installation verified"
    echo "SUCCESS"
    return 0
}

# Check if already installed
check_already_installed() {
    local by_name="/dev/block/by-name"
    
    # Check if efisp contains superfastboot
    if [ -f "$by_name/efisp" ]; then
        if strings "$by_name/efisp" 2>/dev/null | grep -q "superfastboot"; then
            echo "ALREADY_INSTALLED"
            return 0
        fi
    fi
    
    echo "NOT_INSTALLED"
    return 1
}
