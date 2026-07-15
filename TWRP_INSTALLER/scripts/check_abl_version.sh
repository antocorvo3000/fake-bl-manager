#!/sbin/sh
# ABL Version Compatibility Check
# Checks if ABL version is compatible with Fake BL Manager

check_abl_compatibility() {
    local abl_part="$1"
    local current_version=""
    local min_version="OS3.0.270"
    local max_version="OS3.0.306"
    
    # Default to current slot if not specified
    if [ -z "$abl_part" ]; then
        case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
            _a) abl_part="/dev/block/by-name/abl_a" ;;
            _b) abl_part="/dev/block/by-name/abl_b" ;;
            *) abl_part="/dev/block/by-name/abl" ;;
        esac
    fi
    
    # Get version from build properties
    current_version=$(getprop ro.build.version.incremental 2>/dev/null)
    
    if [ -z "$current_version" ]; then
        echo "UNKNOWN"
        return 0
    fi
    
    # Check if version is in safe range
    # Extract version number (e.g., "3.0.300" from "OS3.0.300")
    version_num=$(echo "$current_version" | sed 's/[^0-9.]//g')
    
    # Parse version components
    major=$(echo "$version_num" | cut -d. -f1)
    minor=$(echo "$version_num" | cut -d. -f2)
    patch=$(echo "$version_num" | cut -d. -f3)
    
    # Check if version >= 300 (GBL fixed)
    if [ "$patch" -ge 300 ] 2>/dev/null; then
        echo "CHECK_WARNING"
        return 1
    fi
    
    echo "COMPATIBLE"
    return 0
}

# Return codes:
# 0 = Compatible (version < 300)
# 1 = Check warning (version >= 300, may need downgrade)
# 2 = Unknown version
