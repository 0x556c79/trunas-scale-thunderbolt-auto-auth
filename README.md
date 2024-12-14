## **TrueNAS Scale Thunderbolt Device Authorization**

### **Overview**
This repository provides a udev rule and bash script to automatically authorize Thunderbolt devices on TrueNAS Scale systems. This simplifies the process of connecting new Thunderbolt devices and eliminates the need for manual authorization.
It allows external storage devices to be used via Thunderbolt and ensures that zpools can be mounted because all devices are present.

### **Installation**
1. **Clone the Repository:**
   ```bash
   git clone https://github.com/0x556c79/trunas-scale-thunderbolt-auto-auth.git
   ```
2. **Make the Script Executable:**
   ```bash
   chmod +x trunas-thunderbolt-auth/restore_udev_rules.sh
   ```
3. **Run the Script:**
   ```bash
   sudo ./trunas-thunderbolt-auth/restore_udev_rules.sh
   ```
   This will copy the `99-thunderbolt.rules` file to the `/etc/udev/rules.d/` directory and reload the udev rules and trigger a rescan of Thunderbolt devices.

**IMPORTANT:**

Always store the script and the `99-thunderbolt.rules` file in the same folder. This is the only way the script can copy the file back to the required path if it is missing. Or ajust the first variable in the script.


## **Adding the Script to TrueNAS Scale as an Init Script**
This is required because otherwise the rule will disappear after an update. Adding the script as init script ensures that the udev rule is always there.

**To ensure the script runs automatically during the boot process, you can add it as an init script in TrueNAS Scale:**

1. **Navigate to the Advanced Settings:**
   - Log in to your TrueNAS Scale web interface.
   - Go to **System** > **Advanced**.

2. **Add a New Init Script:**
   - Under the **Init/Shutdown Scripts** section, click **Add**.
   - In the **Script Name** field, enter a descriptive name, such as "thunderbolt_auth".
   - In the **Script** field, paste the path ro the script. I would recommend to use the home directory of your user or the truenas_admin.<br>
     Replace `/home/truenas_admin/trunas-scale-thunderbolt-auto-auth/restore_udev_rules.sh` with the actual path to your `restore_udev_rules.sh` script:

   ```bash
   /home/truenas_admin/trunas-scale-thunderbolt-auto-auth/restore_udev_rules.sh
   ```

   - Set **When** to `preinit`. This ensures the script runs before other services.

3. **Save the Settings:**
   Click **Save** to apply the changes.

**Now, whenever your TrueNAS Scale system boots, the script will automatically execute and check if the udev rule file exsists. If not, it will copy it to the `/etc/udev/rules.d/` directory and apply it.
This way even after a system update all thunderbold devices should work out of the box.**

**Please note that this method is for advanced users. Incorrect configuration can lead to system instability.** 


### **How it Works**
The udev rule automatically sets the `authorized` attribute of Thunderbolt devices to `1` when they are plugged in. This allows the device to be used without manual intervention.<br>
The Bash script ensures that the udev rule is set up and reloaded. It's especially needed after having upgraded the System.

**Note:**
* Always run the script with `sudo` to ensure proper permissions.
