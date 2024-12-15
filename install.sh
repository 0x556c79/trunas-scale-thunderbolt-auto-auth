#!/bin/bash
set -e

# TrueNAS Scale Thunderbolt Auto-Auth Installer
echo "Installing TrueNAS Scale Thunderbolt Auto-Auth..."

# Determine the user who invoked sudo
INSTALL_USER=$(logname)
INSTALL_HOME=$(eval echo ~$INSTALL_USER)
INSTALL_DIR="${INSTALL_HOME}/truenas-thunderbolt-auth"

# Ensure script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Change ownership to the original user
chown $INSTALL_USER:$INSTALL_USER "$INSTALL_DIR"

# Clone the repository
echo "Cloning repository..."
sudo -u $INSTALL_USER git clone https://github.com/0x556c79/trunas-scale-thunderbolt-auto-auth.git .

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
echo "   - Script: ${INSTALL_DIR}/restore_udev_rules.sh"
echo "   - When: preinit"

echo "TrueNAS Scale Thunderbolt Auto-Auth installation completed successfully!"
echo "Installed in: $INSTALL_DIR"
