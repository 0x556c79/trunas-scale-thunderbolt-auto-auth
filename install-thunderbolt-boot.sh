#!/bin/bash
set -e

# TrueNAS Scale Thunderbolt Boot Pool Auto-Authorization
# Comprehensive installation script for current and future boot environments
# Version: 2.0

# =============================================================================
# CONFIGURATION
# =============================================================================

HOOK_NAME="thunderbolt"
HOOK_TARGET_DIR="/usr/share/initramfs-tools/hooks"
HOOK_TARGET="${HOOK_TARGET_DIR}/${HOOK_NAME}"
BOOT_POOL="boot-pool"
BE_ROOT="${BOOT_POOL}/ROOT"

# Thunderbolt authorization hook content
read -r -d '' HOOK_CONTENT << 'EOFHOOK' || true
#!/bin/sh
# Initramfs hook for Thunderbolt authorization
# This script is called when building the initramfs

PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Copy thunderbolt module
manual_add_modules thunderbolt

# Ensure the script directory exists
mkdir -p "${DESTDIR}/scripts/init-premount"

# Create the premount script that will run during boot
cat > "${DESTDIR}/scripts/init-premount/thunderbolt" << 'EOF'
#!/bin/sh
PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Log function
log_msg() {
    echo "Thunderbolt: $1"
    [ -w /dev/kmsg ] && echo "<6>thunderbolt-auth: $1" > /dev/kmsg
}

log_msg "Loading thunderbolt module..."
modprobe thunderbolt 2>/dev/null || log_msg "Warning: Could not load thunderbolt module"

# Wait a moment for devices to be detected
sleep 2

log_msg "Authorizing Thunderbolt devices..."
authorized_count=0
for auth_file in /sys/bus/thunderbolt/devices/*/authorized; do
    if [ -f "$auth_file" ]; then
        current_val=$(cat "$auth_file" 2>/dev/null)
        if [ "$current_val" = "0" ]; then
            if echo 1 > "$auth_file" 2>/dev/null; then
                authorized_count=$((authorized_count + 1))
                device=$(dirname "$auth_file")
                log_msg "Authorized device: $device"
            fi
        fi
    fi
done

if [ $authorized_count -gt 0 ]; then
    log_msg "Authorized $authorized_count Thunderbolt device(s)"
    # Give devices time to settle after authorization
    sleep 2
else
    log_msg "No Thunderbolt devices required authorization"
fi

log_msg "Thunderbolt authorization complete"
EOF

# Make the premount script executable
chmod +x "${DESTDIR}/scripts/init-premount/thunderbolt"

exit 0
EOFHOOK

# =============================================================================
# COLORS AND FORMATTING
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Parse version string from BE name (e.g., "25.04.2.6" from "boot-pool/ROOT/25.04.2.6")
parse_version() {
    local be_name="$1"
    local version=$(echo "$be_name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
    echo "$version"
}

# Compare two version strings
# Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
compare_versions() {
    local v1="$1"
    local v2="$2"

    if [ "$v1" = "$v2" ]; then
        return 0
    fi

    local IFS=.
    local i ver1=($v1) ver2=($v2)

    # Fill empty positions with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done

    return 0
}

# Check if BE name indicates a backup or old snapshot
is_backup_be() {
    local be_name="$1"

    # Check for "backup" in name (case insensitive)
    if echo "$be_name" | grep -iq "backup"; then
        return 0
    fi

    # Check for date pattern YYYYMMDD or YYYY-MM-DD
    if echo "$be_name" | grep -qE '[0-9]{4}[0-9]{2}[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
        return 0
    fi

    # Check for initial/install BE
    if echo "$be_name" | grep -iqE 'initial|install'; then
        return 0
    fi

    return 1
}

# Detect if NVIDIA Docker extension is active
detect_nvidia_active() {
    if mount | grep -q "sysext.*nvidia"; then
        return 0
    fi
    return 1
}

# Check if hook is installed and functional in initramfs
check_hook_installed() {
    local kernel_version="${1:-$(uname -r)}"
    local initramfs_path="/boot/initrd.img-${kernel_version}"

    # Check if hook file exists
    if [ ! -f "${HOOK_TARGET}" ]; then
        return 1
    fi

    # Check if it's in the initramfs
    if [ -f "$initramfs_path" ]; then
        if lsinitramfs "$initramfs_path" 2>/dev/null | grep -q "scripts/init-premount/thunderbolt"; then
            return 0
        fi
    fi

    return 1
}

# Get current boot environment
get_current_be() {
    local root_mount=$(mount | grep " / " | grep "^${BE_ROOT}" | awk '{print $1}')
    echo "$root_mount"
}

# Get all boot environments
get_all_bes() {
    zfs list -H -o name -t filesystem "${BE_ROOT}" 2>/dev/null | grep -v "^${BE_ROOT}$" || true
}

# =============================================================================
# NVIDIA HANDLING
# =============================================================================

NVIDIA_WAS_ACTIVE=false

disable_nvidia_if_needed() {
    if detect_nvidia_active; then
        log_info "NVIDIA Docker extension is active, disabling temporarily..."
        NVIDIA_WAS_ACTIVE=true

        if midclt call --job docker.update '{"nvidia": false}' 2>/dev/null; then
            log_success "NVIDIA extension disabled"
            sleep 2  # Wait for unmount
            return 0
        else
            log_warning "Could not disable NVIDIA extension via midclt, trying systemctl..."
            if systemctl stop systemd-sysext.service 2>/dev/null; then
                log_success "systemd-sysext stopped"
                sleep 2
                return 0
            else
                log_error "Failed to disable NVIDIA extension"
                return 1
            fi
        fi
    fi
    return 0
}

restore_nvidia_if_needed() {
    if [ "$NVIDIA_WAS_ACTIVE" = true ]; then
        log_info "Re-enabling NVIDIA Docker extension..."

        if midclt call --job docker.update '{"nvidia": true}' 2>/dev/null; then
            log_success "NVIDIA extension re-enabled"
        else
            log_warning "Could not re-enable NVIDIA via midclt, trying systemctl..."
            systemctl start systemd-sysext.service 2>/dev/null || log_warning "Failed to restart systemd-sysext"
        fi
    fi
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

# Make ZFS dataset writable
make_writable() {
    local dataset="$1"
    local was_readonly=false

    local current_ro=$(zfs get -H -o value readonly "$dataset" 2>/dev/null || echo "unknown")

    if [ "$current_ro" = "on" ]; then
        was_readonly=true
        if ! zfs set readonly=off "$dataset"; then
            log_error "Failed to set $dataset to read-write"
            return 1
        fi

        # Remount to apply
        local mountpoint=$(zfs get -H -o value mountpoint "$dataset")
        if [ "$mountpoint" != "-" ] && [ "$mountpoint" != "none" ]; then
            mount -o remount,rw "$mountpoint" 2>/dev/null || true
        fi
    fi

    echo "$was_readonly"
}

# Restore readonly status
restore_readonly() {
    local dataset="$1"
    local was_readonly="$2"

    if [ "$was_readonly" = "true" ]; then
        if zfs set readonly=on "$dataset"; then
            local mountpoint=$(zfs get -H -o value mountpoint "$dataset")
            if [ "$mountpoint" != "-" ] && [ "$mountpoint" != "none" ]; then
                mount -o remount,ro "$mountpoint" 2>/dev/null || true
            fi
        else
            log_warning "Failed to restore readonly status for $dataset"
        fi
    fi
}

# Install hook to current running system
install_to_current_system() {
    local current_be=$(get_current_be)
    local usr_dataset="${current_be}/usr"

    # Make filesystems writable
    local usr_was_ro=$(make_writable "$usr_dataset")
    local root_was_ro=$(make_writable "$current_be")

    # Ensure cleanup happens
    local cleanup_done=false
    cleanup_current() {
        if [ "$cleanup_done" = false ]; then
            cleanup_done=true
            restore_readonly "$current_be" "$root_was_ro"
            restore_readonly "$usr_dataset" "$usr_was_ro"
        fi
    }
    trap cleanup_current EXIT INT TERM

    # Verify write access
    if ! touch /usr/.test-write 2>/dev/null; then
        log_error "Cannot write to /usr"
        return 1
    fi
    rm /usr/.test-write

    if ! touch /boot/.test-write 2>/dev/null; then
        log_error "Cannot write to /boot"
        return 1
    fi
    rm /boot/.test-write

    # Create hook directory
    mkdir -p "$HOOK_TARGET_DIR"

    # Install hook
    echo "$HOOK_CONTENT" > "$HOOK_TARGET"
    chmod +x "$HOOK_TARGET"

    log_success "Hook file installed to $HOOK_TARGET"

    # Update initramfs
    log_info "Updating initramfs..."
    if update-initramfs -u -k all 2>&1; then
        log_success "Initramfs updated"
    else
        log_error "Failed to update initramfs"
        return 1
    fi

    # Verify installation
    if check_hook_installed; then
        log_success "Hook successfully installed and verified in current system"
        cleanup_current
        return 0
    else
        log_error "Hook installation verification failed"
        return 1
    fi
}

# Install hook to a different boot environment
install_to_be() {
    local be_dataset="$1"
    local be_name=$(basename "$be_dataset")

    log_info "Installing to boot environment: $be_name"

    # Create temporary mount points
    local temp_root="/tmp/be-root-$$-${be_name}"
    local temp_usr="/tmp/be-usr-$$-${be_name}"

    mkdir -p "$temp_root" "$temp_usr"

    local mounted_root=false
    local mounted_usr=false
    local root_was_ro=""
    local usr_was_ro=""

    # Cleanup function
    cleanup_be() {
        log_info "Cleaning up mounts for $be_name..."

        # Restore readonly
        if [ -n "$usr_was_ro" ]; then
            restore_readonly "${be_dataset}/usr" "$usr_was_ro"
        fi
        if [ -n "$root_was_ro" ]; then
            restore_readonly "$be_dataset" "$root_was_ro"
        fi

        # Unmount
        if [ "$mounted_usr" = true ]; then
            umount "$temp_usr" 2>/dev/null || true
        fi
        if [ "$mounted_root" = true ]; then
            umount "$temp_root/proc" 2>/dev/null || true
            umount "$temp_root/sys" 2>/dev/null || true
            umount "$temp_root/dev" 2>/dev/null || true
            umount "$temp_root" 2>/dev/null || true
        fi

        # Remove temp dirs
        rmdir "$temp_usr" 2>/dev/null || true
        rmdir "$temp_root" 2>/dev/null || true
    }

    trap cleanup_be EXIT INT TERM

    # Make writable
    root_was_ro=$(make_writable "$be_dataset")
    usr_was_ro=$(make_writable "${be_dataset}/usr")

    # Mount root
    if ! zfs mount "$be_dataset" 2>/dev/null; then
        # Already mounted, need to mount at our temp location
        mount -t zfs "$be_dataset" "$temp_root" || {
            log_error "Failed to mount $be_dataset"
            cleanup_be
            return 1
        }
        mounted_root=true
    else
        # Get actual mountpoint
        local actual_mount=$(zfs get -H -o value mountpoint "$be_dataset")
        if [ "$actual_mount" != "$temp_root" ]; then
            # Remount at temp location
            zfs umount "$be_dataset"
            mount -t zfs "$be_dataset" "$temp_root" || {
                log_error "Failed to mount at temp location"
                cleanup_be
                return 1
            }
            mounted_root=true
        else
            temp_root="$actual_mount"
        fi
    fi

    # Check if usr needs separate mount
    if zfs list "${be_dataset}/usr" >/dev/null 2>&1; then
        if ! zfs mount "${be_dataset}/usr" 2>/dev/null; then
            mount -t zfs "${be_dataset}/usr" "${temp_root}/usr" || {
                log_error "Failed to mount usr"
                cleanup_be
                return 1
            }
            mounted_usr=true
        fi
    fi

    # Install hook
    local hook_path="${temp_root}${HOOK_TARGET}"
    mkdir -p "$(dirname "$hook_path")"
    echo "$HOOK_CONTENT" > "$hook_path"
    chmod +x "$hook_path"

    log_success "Hook installed to $hook_path"

    # Prepare chroot environment
    mount --bind /proc "${temp_root}/proc"
    mount --bind /sys "${temp_root}/sys"
    mount --bind /dev "${temp_root}/dev"

    # Update initramfs in chroot
    log_info "Updating initramfs in chroot..."
    if chroot "$temp_root" update-initramfs -u -k all 2>&1; then
        log_success "Initramfs updated for $be_name"
        cleanup_be
        return 0
    else
        log_error "Failed to update initramfs for $be_name"
        cleanup_be
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "=============================================="
    echo "TrueNAS Scale Thunderbolt Boot Pool Installer"
    echo "=============================================="
    echo ""

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Usage: sudo $0"
        exit 1
    fi

    # Check if update-initramfs is available
    if ! command -v update-initramfs >/dev/null 2>&1; then
        log_error "update-initramfs not found. This system may not be compatible."
        exit 1
    fi

    # Get current BE
    local current_be=$(get_current_be)
    if [ -z "$current_be" ]; then
        log_error "Could not determine current boot environment"
        exit 1
    fi

    local current_version=$(parse_version "$current_be")
    log_info "Current boot environment: $(basename $current_be) (version: $current_version)"
    echo ""

    # Check if hook is already installed in current system
    local hook_installed=false
    if check_hook_installed; then
        log_success "Hook already installed in current system"
        hook_installed=true
    else
        log_info "Hook not installed in current system"
    fi

    echo ""
    log_info "Scanning for newer boot environments..."
    echo ""

    # Get all BEs
    local all_bes=$(get_all_bes)
    local newer_bes=()

    # Filter for newer versions only
    for be in $all_bes; do
        # Skip current BE
        if [ "$be" = "$current_be" ]; then
            continue
        fi

        # Skip backup BEs
        if is_backup_be "$be"; then
            log_info "Skipping backup/old BE: $(basename $be)"
            continue
        fi

        # Parse and compare version
        local be_version=$(parse_version "$be")
        if [ -z "$be_version" ]; then
            log_warning "Could not parse version from: $(basename $be), skipping"
            continue
        fi

        compare_versions "$be_version" "$current_version"
        local result=$?

        if [ $result -eq 1 ]; then
            # BE is newer
            log_info "Found newer BE: $(basename $be) (version: $be_version)"
            newer_bes+=("$be")
        else
            log_info "Skipping older/equal BE: $(basename $be) (version: $be_version)"
        fi
    done

    echo ""

    # Check if any work needs to be done
    if [ "$hook_installed" = true ] && [ ${#newer_bes[@]} -eq 0 ]; then
        log_success "Hook already installed and no newer boot environments found"
        log_info "Nothing to do - exiting"
        echo ""
        echo "=============================================="
        echo "System is up to date!"
        echo "=============================================="
        echo ""
        log_info "Thunderbolt authorization is already configured for all boot environments"
        return 0
    fi

    # Work is needed, disable NVIDIA if necessary
    disable_nvidia_if_needed
    trap restore_nvidia_if_needed EXIT INT TERM

    # Install to current system if needed
    if [ "$hook_installed" = false ]; then
        log_info "Installing Thunderbolt hook to current system..."
        echo ""
        if ! install_to_current_system; then
            log_error "Failed to install to current system"
            exit 1
        fi
        echo ""
    fi

    # Install to newer BEs
    if [ ${#newer_bes[@]} -gt 0 ]; then
        log_info "Installing to ${#newer_bes[@]} newer boot environment(s)..."
        echo ""

        local success_count=0
        for be in "${newer_bes[@]}"; do
            if install_to_be "$be"; then
                ((success_count++))
            else
                log_warning "Installation to $(basename $be) failed, continuing..."
            fi
            echo ""
        done

        log_success "Successfully installed to $success_count of ${#newer_bes[@]} newer BE(s)"
    fi

    echo ""
    echo "=============================================="
    echo "Installation Complete!"
    echo "=============================================="
    echo ""
    log_success "Thunderbolt authorization hook has been installed"
    echo ""
    echo "NEXT STEPS:"
    echo "1. Reboot your system: sudo reboot"
    echo "2. System should boot automatically from Thunderbolt device"
    echo "3. Verify with: dmesg | grep thunderbolt-auth"
    echo ""
    echo "TO AUTOMATE AFTER UPDATES:"
    echo "Add this script as a TrueNAS Init Script:"
    echo "  - System > Advanced > Init/Shutdown Scripts"
    echo "  - Type: Script"
    echo "  - Script: $(realpath "$0")"
    echo "  - When: Post Init"
    echo "  - Timeout: 120 seconds"
    echo ""

    return 0
}

# Run main function
main "$@"
