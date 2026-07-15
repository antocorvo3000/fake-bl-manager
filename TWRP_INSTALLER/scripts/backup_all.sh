#!/sbin/sh
# System Backup Script
# Backs up ABL, vbmeta, and boot partitions

backup_system() {
    local backup_dir="/tmp/fake_bl/backup_$(date +%Y%m%d_%H%M%S)"
    local by_name="/dev/block/by-name"
    
    mkdir -p "$backup_dir"
    
    # Backup ABL
    print_msg "Backing up ABL..."
    if [ -f "$by_name/abl_a" ]; then
        dd if="$by_name/abl_a" of="$backup_dir/abl_a.img" bs=4M conv=fsync 2>/dev/null
        sync
    fi
    if [ -f "$by_name/abl_b" ]; then
        dd if="$by_name/abl_b" of="$backup_dir/abl_b.img" bs=4M conv=fsync 2>/dev/null
        sync
    fi
    
    # Backup vbmeta
    print_msg "Backing up vbmeta..."
    for part in vbmeta vbmeta_system vbmeta_vendor vbmeta_boot; do
        if [ -f "$by_name/$part" ]; then
            dd if="$by_name/$part" of="$backup_dir/${part}.img" bs=4M conv=fsync 2>/dev/null
            sync
        fi
    done
    
    # Backup boot if different from recovery
    print_msg "Backing up boot partitions..."
    for part in boot vendor_boot init_boot; do
        if [ -f "$by_name/$part" ]; then
            dd if="$by_name/$part" of="$backup_dir/${part}.img" bs=4M conv=fsync 2>/dev/null
            sync
        fi
    done
    
    # Backup efisp (current state)
    print_msg "Backing up efisp..."
    if [ -f "$by_name/efisp" ]; then
        dd if="$by_name/efisp" of="$backup_dir/efisp_current.img" bs=4M conv=fsync 2>/dev/null
        sync
    fi
    
    # Create metadata
    cat > "$backup_dir/backup_info.txt" << EOF
Backup Date: $(date)
Device: $(getprop ro.product.model)
SOC: $(getprop ro.board.platform)
Android: $(getprop ro.build.version.release)
Version: $(getprop ro.build.version.incremental)
Slots: A=$(getprop ro.boot.slot_suffix)
EOF
    
    if [ -d "$backup_dir" ] && [ "$(ls -A $backup_dir 2>/dev/null)" ]; then
        echo "SUCCESS:$backup_dir"
        return 0
    else
        echo "FAILED"
        return 1
    fi
}

# Restore from backup
restore_system() {
    local backup_dir="$1"
    local by_name="/dev/block/by-name"
    
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        echo "FAILED:No backup directory"
        return 1
    fi
    
    # Set partitions to read-write
    blockdev --setrw "$by_name/abl_a" 2>/dev/null
    blockdev --setrw "$by_name/abl_b" 2>/dev/null
    blockdev --setrw "$by_name/efisp" 2>/dev/null
    
    # Restore ABL
    if [ -f "$backup_dir/abl_a.img" ]; then
        dd if="$backup_dir/abl_a.img" of="$by_name/abl_a" bs=4M conv=fsync 2>/dev/null
        sync
    fi
    if [ -f "$backup_dir/abl_b.img" ]; then
        dd if="$backup_dir/abl_b.img" of="$by_name/abl_b" bs=4M conv=fsync 2>/dev/null
        sync
    fi
    
    # Restore vbmeta
    for part in vbmeta vbmeta_system vbmeta_vendor; do
        if [ -f "$backup_dir/${part}.img" ]; then
            dd if="$backup_dir/${part}.img" of="$by_name/${part}" bs=4M conv=fsync 2>/dev/null
            sync
        fi
    done
    
    # Restore efisp
    if [ -f "$backup_dir/efisp_current.img" ]; then
        dd if="$backup_dir/efisp_current.img" of="$by_name/efisp" bs=4M conv=fsync 2>/dev/null
        sync
    fi
    
    echo "SUCCESS"
    return 0
}
