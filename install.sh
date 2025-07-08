#!/bin/bash
set -e

# TrueNAS Scale Thunderbolt Auto-Auth Installer
echo "Installing TrueNAS Scale Thunderbolt Auto-Auth..."

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Use current working directory as installation and working directory
INSTALL_DIR="$(pwd)"

# Enforce working directory must be under /mnt/<POOL_NAME>/
if [[ "$INSTALL_DIR" != /mnt/* ]]; then
    echo "ERROR: The script must be run from a directory under /mnt/<POOL_NAME>/."
    echo "Current directory: $INSTALL_DIR"
    exit 1
fi

# Prevent running directly from /home (just in case)
if [[ "$INSTALL_DIR" == /home/* ]]; then
    echo "ERROR: Do not run or install from /home. Use a directory under /mnt/<POOL_NAME>/"
    exit 1
fi

# Set the clone directory
CLONE_DIR="$INSTALL_DIR/truenas-thunderbolt-auth

# Create installation directory
mkdir -p "$CLONE_DIR"
cd "$CLONE_DIR"

# Clone the repository
echo "Cloning repository..."
git clone -q https://github.com/0x556c79/trunas-scale-thunderbolt-auto-auth.git .

# Make the restore script executable
chmod +x restore_udev_rules.sh

# Run the restore script to set up udev rules
echo "Setting up Thunderbolt udev rules..."
./restore_udev_rules.sh

# Optional: Add a step to help user configure init script
echo "IMPORTANT: To ensure persistence after updates, add this script as an init script in TrueNAS Scale:"
echo "1. Go to System > Advanced"
echo "2. Add an Init Script with:"
echo "   - Script Name: thunderbolt_auth"
echo "   - Script: ${CLONE_DIR}/restore_udev_rules.sh"
echo "   - When: preinit"

echo "TrueNAS Scale Thunderbolt Auto-Auth installation completed successfully!"
echo "Installed in: $CLONE_DIR"
