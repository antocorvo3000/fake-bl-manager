#!/sbin/sh
# Safe Installation Script
# Performs the actual Fake BL patching and installation

install_safe_patch() {
    local runtime_dir="/tmp/fake_bl"
    local by_name="/dev/block/by-name"
    
    mkdir -p "$runtime_dir"
    
    # Detect current slot
    case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
        _a) current_slot="_a"; target_slot="_b" ;;
        _b) current_slot="_b"; target_slot="_a" ;;
        *) current_slot=""; target_slot="" ;;
    esac
    
    if [ -z "$current_slot" ]; then
        echo "FAILED:Cannot detect current slot"
        return 1
    fi
    
    # Extract FV from ABL
    print_msg "Extracting FV from ABL..."
    extractfv -o "$runtime_dir" -v "$by_name/abl$current_slot" >> "$runtime_dir/extract.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "FAILED:Extraction failed"
        return 2
    fi
    
    # Patch ABL
    print_msg "Patching ABL..."
    patch_abl "$runtime_dir/LinuxLoader.efi" "$runtime_dir/patched.efi" >> "$runtime_dir/patch.log" 2>&1
    if [ ! -f "$runtime_dir/patched.efi" ]; then
        echo "FAILED:Patch failed"
        return 3
    fi
    
    # Check for GBL error
    if grep -q "Warning: Failed to patch ABL GBL" "$runtime_dir/patch.log"; then
        echo "FAILED:GBL exploit not found"
        return 4
    fi
    
    # Inject superfastboot if available
    if [ -f "$MODDIR/loader.elf" ]; then
        print_msg "Injecting superfastboot..."
        elf_inject "$MODDIR/loader.elf" "$runtime_dir/patched.efi" "$runtime_dir/injected.dll" >> "$runtime_dir/inject.log" 2>&1
        if [ -f "$runtime_dir/injected.dll" ]; then
            GenFw -e UEFI_APPLICATION -o "$runtime_dir/patched.efi" "$runtime_dir/injected.dll" >> "$runtime_dir/genfw.log" 2>&1
        fi
    fi
    
    # Set efisp to read-write
    print_msg "Setting efisp to read-write..."
    if ! blockdev --setrw "$by_name/efisp" >> "$runtime_dir/setrw.log" 2>&1; then
        echo "FAILED:Cannot set efisp to read-write"
        return 5
    fi
    
    # Flash patched ABL to efisp
    print_msg "Flashing patched ABL to efisp..."
    if ! dd if="$runtime_dir/patched.efi" of="$by_name/efisp" bs=4M conv=fsync >> "$runtime_dir/flash.log" 2>&1; then
        echo "FAILED:Flash failed"
        return 6
    fi
    
    sync
    
    echo "SUCCESS"
    return 0
}

# Install with format option
install_with_format() {
    local runtime_dir="/tmp/fake_bl"
    local by_name="/dev/block/by-name"
    
    # Perform installation
    install_result=$(install_safe_patch)
    if [ "$install_result" = "SUCCESS" ]; then
        # Request format from recovery
        echo "SUCCESS:FORMAT_REQUIRED"
        return 0
    else
        echo "$install_result"
        return 1
    fi
}
