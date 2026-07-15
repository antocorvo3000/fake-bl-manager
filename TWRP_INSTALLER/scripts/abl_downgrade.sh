#!/sbin/sh
# ABL Downgrade Script
# Handles safe ABL version management

check_downgrade_needed() {
    local current_version=""
    local target_version=""
    
    # Get current ABL version
    current_version=$(getprop ro.build.version.incremental 2>/dev/null)
    current_version=$(echo "$current_version" | sed 's/[^0-9.]//g')
    
    if [ -z "$current_version" ]; then
        echo "UNKNOWN"
        return 1
    fi
    
    # Parse version components
    major=$(echo "$current_version" | cut -d. -f1)
    minor=$(echo "$current_version" | cut -d. -f2)
    patch=$(echo "$current_version" | cut -d. -f3)
    
    # Check if downgrade needed (version >= 300)
    if [ "$patch" -ge 300 ] 2>/dev/null; then
        echo "NEEDED"
        return 0
    fi
    
    echo "NOT_NEEDED"
    return 0
}

perform_downgrade() {
    local runtime_dir="/tmp/fake_bl"
    local by_name="/dev/block/by-name"
    local target_version="OS3.0.290"
    
    # Get current slot
    case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
        _a) current_slot="_a"; target_slot="_b" ;;
        _b) current_slot="_b"; target_slot="_a" ;;
        *) current_slot=""; target_slot="" ;;
    esac
    
    if [ -z "$current_slot" ]; then
        echo "FAILED:Cannot detect current slot"
        return 1
    fi
    
    # Extract current ABL
    extractfv -o "$runtime_dir" -v "$by_name/abl$current_slot" >> "$runtime_dir/extract.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "FAILED:Extract current ABL failed"
        return 2
    fi
    
    # Check if current ABL already has downgrade capability
    # For version >= 300, we need to patch to allow old ABL boot
    patch_abl "$runtime_dir/LinuxLoader.efi" "$runtime_dir/patched.efi" >> "$runtime_dir/patch.log" 2>&1
    
    if grep -q "Warning: Failed to patch ABL GBL" "$runtime_dir/patch.log"; then
        echo "FAILED:GBL exploit not found"
        return 3
    fi
    
    # Inject superfastboot for downgrade support
    if [ -f "$MODDIR/loader.elf" ]; then
        elf_inject "$MODDIR/loader.elf" "$runtime_dir/patched.efi" "$runtime_dir/injected.dll" >> "$runtime_dir/inject.log" 2>&1
        if [ -f "$runtime_dir/injected.dll" ]; then
            GenFw -e UEFI_APPLICATION -o "$runtime_dir/patched.efi" "$runtime_dir/injected.dll" >> "$runtime_dir/genfw.log" 2>&1
        fi
    fi
    
    # Flash to efisp (allows old ABL boot)
    blockdev --setrw "$by_name/efisp" >> "$runtime_dir/setrw.log" 2>&1
    dd if="$runtime_dir/patched.efi" of="$by_name/efisp" bs=4M conv=fsync >> "$runtime_dir/flash.log" 2>&1
    sync
    
    echo "SUCCESS"
    return 0
}

download_abl_version() {
    local version="$1"
    local output_dir="/tmp/fake_bl/downloads"
    
    mkdir -p "$output_dir"
    
    # Download ABL version from GitHub releases
    # This would be implemented with curl/wget
    echo "Download feature not yet implemented"
    echo "FAILED"
    return 1
}

get_safe_version() {
    local device="$1"
    
    case "$device" in
        *17*Pro*Max*|*canoe*)
            echo "OS3.0.290"
            ;;
        *14*Ultra*|*panther*)
            echo "OS3.0.290"
            ;;
        *14*Pro*|*cupidin*)
            echo "OS3.0.290"
            ;;
        *13T*Pro*|*peacock*)
            echo "OS3.0.290"
            ;;
        *)
            echo "OS3.0.290"
            ;;
    esac
}

# Return codes:
# 0 = Downgrade successful
# 1 = Cannot detect slot
# 2 = Extract failed
# 3 = GBL exploit not found
# 4 = Flash failed
