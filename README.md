# TrueNAS Scale Thunderbolt Auto-Authorization

This repository provides bash script to automatically authorize Thunderbolt devices on TrueNAS Scale systems by injecting Thunderbolt authorization directly into the initramfs boot environment.
This simplifies the process of connecting new Thunderbolt devices and eliminates the need for manual authorization. It allows external storage devices to be used via Thunderbolt and ensures that zpools can be mounted because all devices are present.

---

## Quick Start

### Prerequisites

- TrueNAS Scale system with boot pool on Thunderbolt device
- Root/SSH access to your TrueNAS system
- 5-10 minutes of time

## Installation

### 1. Clone this repository to a persistent location (Store on your data pool, NOT /home or /root)

```bash
git clone https://github.com/0x556c79/trunas-scale-thunderbolt-auto-auth.git
cd trunas-scale-thunderbolt-auto-auth
```

**Alternatively, you can download just the install-thunderbolt-boot.sh script directly.**

```bash
curl -O https://raw.githubusercontent.com/0x556c79/trunas-scale-thunderbolt-auto-auth/main/install-thunderbolt-boot.sh
```

**or donwload and run it directly:**

```bash
curl -s https://raw.githubusercontent.com/0x556c79/trunas-scale-thunderbolt-auto-auth/main/install-thunderbolt-boot.sh | sudo bash
```

### 2. Make script executable

```bash
chmod +x install-thunderbolt-boot.sh
```

### 3. Run the installer

```bash
sudo ./install-thunderbolt-boot.sh
```

### 4. Reboot and test

```bash
sudo reboot
```

After rebooting, your system should boot automatically without requiring manual Thunderbolt authorization!

## Features

### Intelligent Installation

- ✅ Detects current boot environment and installs hook
- ✅ Automatically finds newer boot environments (for future updates)
- ✅ Skips backup and older boot environments
- ✅ Version-aware: only processes newer versions than currently running

### NVIDIA Docker Support

- ✅ Automatically detects NVIDIA Docker extension
- ✅ Temporarily disables extension during installation
- ✅ Re-enables extension after completion
- ✅ No manual intervention required

### Safety Features

- ✅ Makes filesystems writable only when needed
- ✅ Automatically restores read-only status
- ✅ Cleanup on error (trap handlers)
- ✅ Idempotent (safe to run multiple times)
- ✅ Verifies installation success

### Future-Proof

- ✅ Installs to upcoming boot environments
- ✅ Survives TrueNAS Scale updates
- ✅ Can be automated via TrueNAS Init Scripts

## How It Works

The script injects a hook into `/usr/share/initramfs-tools/hooks/thunderbolt` which creates a premount script that runs before the boot pool import.

## What The Script Does

### Phase 1: Current System

1. Checks if hook is already installed
2. Detects and disables NVIDIA Docker extension (if active)
3. Makes `/usr` and `/` writable (ZFS readonly=off)
4. Installs Thunderbolt authorization hook
5. Runs `update-initramfs -u -k all`
6. Verifies hook is in initramfs
7. Restores filesystems to read-only
8. Re-enables NVIDIA extension

### Phase 2: Future Boot Environments

1. Scans all boot environments in `boot-pool/ROOT/`
2. Parses version numbers from BE names
3. Identifies BEs **newer** than current version
4. Skips backup/old BEs (names with "backup", dates, or "initial")
5. For each newer BE:
   - Mounts BE at temporary location
   - Installs hook to BE's `/usr`
   - Uses chroot to rebuild initramfs
   - Unmounts and cleans up

### Phase 3: Cleanup

1. Restores all readonly states
2. Re-enables NVIDIA if it was disabled
3. Reports success/failure for each BE

## Automation (Recommended)

To automatically reinstall the hook after TrueNAS updates:

### Add as TrueNAS Init Script

1. Open TrueNAS Scale Web UI
2. Go to: **System → Advanced**
3. Click **Add** under "Init/Shutdown Scripts"
4. Configure:
   - **Description:** `Thunderbolt Boot Pool Support`
   - **Type:** `Script`
   - **Script:** `/mnt/your-pool/trunas-scale-thunderbolt-auto-auth/install-thunderbolt-boot.sh`
   - **When:** `Post Init`
   - **Enabled:** ✓ (checked)
   - **Timeout:** `120` seconds
5. Click **Save**

The script will run after every boot, detecting if reinstallation is needed after updates.

## Verification

After installation and reboot, verify the hook is working:

```bash
# Check if hook exists
ls -la /usr/share/initramfs-tools/hooks/thunderbolt

# Check if hook is in initramfs
lsinitramfs /boot/initrd.img-$(uname -r) 2>/dev/null | grep thunderbolt

# Check boot logs
dmesg | grep -i thunderbolt
journalctl -b | grep "thunderbolt-auth"
```

You should see messages like:

```txt
thunderbolt-auth: Loading thunderbolt module...
thunderbolt-auth: Authorized 1 Thunderbolt device(s)
thunderbolt-auth: Thunderbolt authorization complete
```

## Troubleshooting

### System Still Drops to Emergency Shell

**Check hook installation:**

```bash
lsinitramfs /boot/initrd.img-$(uname -r) 2>/dev/null | grep thunderbolt
```

If missing, re-run the installation script:

```bash
sudo ./install-thunderbolt-boot.sh
```

### After TrueNAS Update, Manual Authorization Needed Again

If you configured the init script (recommended), wait for one more boot cycle - it will reinstall automatically.

If not configured, manually re-run:

```bash
sudo ./install-thunderbolt-boot.sh
```

### Error: "Cannot write to /usr" or "Cannot write to /boot"

The script should handle this automatically. If you see this error:

1. Check if NVIDIA Docker extension is active: `mount | grep sysext`
2. Manually disable: `midclt call --job docker.update '{"nvidia": false}'`
3. Re-run script
4. Re-enable: `midclt call --job docker.update '{"nvidia": true}'`

### Devices Need More Time

Some Thunderbolt devices need more time to initialize. Edit the hook to increase sleep values:

```bash
sudo nano /usr/share/initramfs-tools/hooks/thunderbolt
# Find "sleep 2" and change to "sleep 4"
sudo update-initramfs -u -k all
sudo reboot
```

---

## Security Considerations

This solution **automatically authorizes ALL Thunderbolt devices** without user confirmation.

**Security Implications:**

- Any Thunderbolt device plugged in during boot will be authorized
- Equivalent to Thunderbolt security level "none"
- Potential DMA (Direct Memory Access) attack surface

**Acceptable for:**

- Dedicated NAS in physically secure location
- Home lab / home office with physical security
- Systems where convenience > strict security

**Not recommended for:**

- Public or untrusted environments
- High-security requirements
- Multi-user systems with untrusted users

---

## Technical Details

### Filesystem Structure

TrueNAS Scale uses ZFS for the boot pool:

```txt
boot-pool/ROOT/25.04.2.6/          ← Root (read-only by default)
├── /boot                          ← Part of root
├── /usr                           ← Separate dataset
└── /etc, /var, /home, etc.        ← Separate datasets
```

The script temporarily makes these writable using:

```bash
zfs set readonly=off boot-pool/ROOT/25.04.2.6
zfs set readonly=off boot-pool/ROOT/25.04.2.6/usr
```

### Initramfs Hook System

TrueNAS Scale uses **initramfs-tools** for boot environment:

- Hooks in `/usr/share/initramfs-tools/hooks/` run during initramfs build
- They inject scripts into `/scripts/init-premount/` in the initramfs
- These scripts run early in boot, before storage is accessed

### Boot Environment Management

TrueNAS creates new boot environments for updates:

```txt
boot-pool/ROOT/
├── 25.04.2.6      ← Current version
├── 25.04.2.7      ← Newer version (after update)
└── 25.04.0-backup ← Backup (script skips this)
```

The script ensures the hook is in both current and future BEs.

---

## Emergency Recovery

If something goes wrong and the system won't boot, you can still manually authorize at the emergency shell:

```bash
modprobe thunderbolt 2>/dev/null || true
sleep 2
for d in /sys/bus/thunderbolt/devices/*/authorized; do
    if [ -f "$d" ]; then
        echo 1 > "$d" 2>/dev/null
    fi
done
sleep 2
/sbin/zpool import -N -f 'boot-pool'
sleep 2
exit
```

Once booted, you can remove the hook if needed:

```bash
sudo rm /usr/share/initramfs-tools/hooks/thunderbolt
sudo update-initramfs -u -k all
```

## For issues and questions

- Check the troubleshooting section above
- Open an issue on GitHub

**Note:** This is a community solution and is not officially supported by iXsystems.
