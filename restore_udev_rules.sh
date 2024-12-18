#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define paths
SOURCE_RULE="$SCRIPT_DIR/99-thunderbolt.rules"
TARGET_RULE="/etc/udev/rules.d/99-thunderbolt.rules"
LOG_TAG="udev_rule_restore"

# Function for logging (both to syslog and shell)
log() {
    local message="$1"
    # Log to syslog
    logger -t "$LOG_TAG" "$message"
    # Echo to shell
    echo "[${LOG_TAG}] $message"
}

# Ensure script is run with root privileges
if [[ $EUID -ne 0 ]]; then
    log "This script must be run as root"
    echo "Error: This script requires root privileges. Use sudo." >&2
    exit 1
fi

# Check and update udev rule
if [[ ! -f "$TARGET_RULE" ]] || ! cmp -s "$SOURCE_RULE" "$TARGET_RULE"; then
    # Rule doesn't exist or is different
    log "Updating or adding udev rule..."
    
    # Attempt to copy the rule
    if cp "$SOURCE_RULE" "$TARGET_RULE"; then
        # Reload udev rules
        udevadm control --reload-rules
        udevadm trigger
        
        log "udev rule successfully updated or added."
    else
        log "Failed to copy udev rule"
        echo "Error: Failed to copy udev rule" >&2
        exit 1
    fi
else
    log "The udev rule already exists and is up-to-date. No action required."
fi

exit 0
