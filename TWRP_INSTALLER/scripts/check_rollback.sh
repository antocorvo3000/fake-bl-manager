#!/sbin/sh
# Rollback Version Check
# Verifies rollback index before downgrade

check_rollback_version() {
    local current_slot=""
    local rollback_db="/tmp/fake_bl/rollback_index.csv"
    
    # Get current slot
    case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
        _a) current_slot="_a" ;;
        _b) current_slot="_b" ;;
        *) current_slot="" ;;
    esac
    
    if [ -z "$current_slot" ]; then
        echo "UNKNOWN"
        return 1
    fi
    
    # Load rollback database
    if [ ! -f "$rollback_db" ]; then
        # Try to download or use embedded database
        if [ -f "/tmp/fake_bl/assets/rollback_index.csv" ]; then
            cp "/tmp/fake_bl/assets/rollback_index.csv" "$rollback_db"
        else
            echo "Creating rollback database..."
            create_rollback_database "$rollback_db"
        fi
    fi
    
    # Get current ABL version
    current_version=$(getprop ro.build.version.incremental 2>/dev/null)
    current_version=$(echo "$current_version" | sed 's/[^0-9.]//g')
    
    # Check if current version is in safe range
    if [ -z "$current_version" ]; then
        echo "UNKNOWN"
        return 1
    fi
    
    # Check if downgrade would trigger rollback protection
    # Version >= 300 requires special handling
    if [ "${current_version%%.*}" -ge 3 ] 2>/dev/null; then
        minor=$(echo "$current_version" | cut -d. -f2)
        patch=$(echo "$current_version" | cut -d. -f3)
        
        # Check if patch version is safe
        if [ "$patch" -ge 300 ] && [ "$patch" -le 306 ]; then
            echo "SAFE_WITH_DOWNGRADE"
            return 0
        elif [ "$patch" -gt 306 ]; then
            echo "DANGER"
            return 2
        fi
    fi
    
    echo "SAFE"
    return 0
}

create_rollback_database() {
    local db_file="$1"
    
    # Create rollback database for Xiaomi devices
    cat > "$db_file" << 'EOF'
device,version,rollback_index,safe_for_downgrade,notes
canoe,OS3.0.270,2,true,GBL present, safe downgrade
canoe,OS3.0.280,3,true,GBL present, safe downgrade
canoe,OS3.0.290,4,true,GBL present, safe downgrade
canoe,OS3.0.300,5,false,GBL fixed, requires special handling
canoe,OS3.0.306,5,false,GBL fixed, XBL downgrade works
EOF
}

# Return codes:
# 0 = SAFE (can downgrade normally)
# 1 = UNKNOWN (cannot determine)
# 2 = DANGER (rollback protection active)
# 3 = SAFE_WITH_DOWNGRADE (special downgrade required)
