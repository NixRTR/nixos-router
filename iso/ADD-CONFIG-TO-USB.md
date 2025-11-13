# Adding router-config.nix to the ISO USB Drive

This guide shows you how to add your `router-config.nix` file to the same USB drive as the ISO, so you only need **one USB drive** for automated installation.

## 🎯 Goal

Instead of using two USB drives (one for the ISO, one for the config), we'll add the config file directly to the ISO USB drive in the `/config/` directory.

## 📝 Overview

1. Write the ISO to USB (as normal)
2. Re-mount the USB drive
3. Add `router-config.nix` to the `/config/` directory
4. Boot and use automated installation

---

## 🖥️ On Windows

### Step 1: Write ISO to USB

Use **Rufus**:
1. Open Rufus
2. Select your USB drive
3. Select the `nixos-router-installer.iso` file
4. Click **START**
5. Choose **"Write in DD Image mode"** when prompted
6. Wait for completion

### Step 2: Re-mount the USB Drive

After Rufus completes:
1. **Safely eject** the USB drive in Windows
2. **Remove and re-insert** the USB drive
3. Windows should mount it and show it in File Explorer

### Step 3: Add Your Config File

The USB drive will show up as a drive letter (e.g., `E:\` or `F:\`)

1. Open File Explorer
2. Navigate to the USB drive
3. You should see a `/config/` folder (or `\config\` in Windows)
4. Copy your `router-config.nix` into this folder:

```
E:\config\router-config.nix  ← Place it here
```

**PowerShell method:**
```powershell
# Replace E: with your USB drive letter
copy C:\Users\Willi\github\nixos-router\router-config.nix E:\config\
```

### Step 4: Safely Eject

Right-click the USB drive in File Explorer and select **"Eject"**

### ✅ Done!

Your USB drive now contains both:
- The bootable NixOS Router ISO
- Your custom `router-config.nix` in `/config/`

Boot from this USB and select "Automated Installation"!

---

## 🐧 On Linux

### Step 1: Write ISO to USB

```bash
# Find your USB device (BE CAREFUL!)
lsblk

# Write the ISO (replace sdX with your USB device)
sudo dd if=nixos-router-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### Step 2: Re-mount the USB Drive

```bash
# Remove and re-insert the USB drive, or:
sudo partprobe /dev/sdX

# Find the partition (usually the larger one)
lsblk /dev/sdX

# Mount it (may auto-mount, check /media or /run/media first)
sudo mkdir -p /mnt/iso-usb
sudo mount /dev/sdX2 /mnt/iso-usb  # Adjust partition number as needed
```

### Step 3: Add Your Config File

```bash
# The /config directory should exist on the ISO
ls /mnt/iso-usb/config/

# Copy your router-config.nix
sudo cp router-config.nix /mnt/iso-usb/config/

# Verify it's there
ls -la /mnt/iso-usb/config/router-config.nix
```

### Step 4: Unmount

```bash
sudo umount /mnt/iso-usb
sudo eject /dev/sdX
```

### ✅ Done!

Boot from the USB and select "Automated Installation"!

---

## 🍎 On macOS

### Step 1: Write ISO to USB

```bash
# Find your USB device
diskutil list

# Unmount it (replace diskN)
diskutil unmountDisk /dev/diskN

# Write the ISO
sudo dd if=nixos-router-installer.iso of=/dev/rdiskN bs=1m
```

### Step 2: Re-mount the USB Drive

```bash
# Eject and re-insert the USB, or:
diskutil mountDisk /dev/diskN
```

### Step 3: Add Your Config File

```bash
# The USB should mount automatically
# Look for it in /Volumes/

ls /Volumes/*/config/

# Copy your config
cp router-config.nix /Volumes/NIXOS_ROUTER/config/

# Verify
ls -la /Volumes/NIXOS_ROUTER/config/router-config.nix
```

### Step 4: Eject

```bash
diskutil eject /dev/diskN
```

### ✅ Done!

Boot from the USB and select "Automated Installation"!

---

## 🔍 Troubleshooting

### Can't find /config/ directory

After writing the ISO, you may see multiple partitions. The `/config/` directory is on the **main ISO filesystem** (usually the larger partition).

**Check all mounted partitions:**

```bash
# Linux
findmnt | grep sdX

# macOS  
diskutil list

# Windows
# Check all drive letters that appear when you insert the USB
```

### Permission denied when copying

**Linux/macOS:**
```bash
# Use sudo
sudo cp router-config.nix /path/to/usb/config/
```

**Windows:**
- Run File Explorer or PowerShell as Administrator

### ISO filesystem is read-only

Some filesystems on the ISO may be read-only (like ISO9660). In this case:

**Option A:** Use the **EFI partition** instead (usually FAT32, writable):
```bash
# Linux example
sudo mount /dev/sdX1 /mnt/efi  # First partition is usually EFI
sudo mkdir -p /mnt/efi/config
sudo cp router-config.nix /mnt/efi/config/
```

Update the auto-menu.sh to also check `/boot/config/` or `/efi/config/`.

**Option B:** Use a separate USB drive (traditional method).

### Config not detected when booting

Verify the file is in the right place:

1. Boot from the USB
2. At the menu, select **"Open Shell"**
3. Run:
   ```bash
   # Check possible locations
   find / -name "router-config.nix" 2>/dev/null
   
   # Check ISO mount
   ls /iso/config/
   
   # Check EFI partition
   ls /boot/config/
   ```

If found in a different location, note it and the auto-menu should detect it.

---

## 💡 Tips

1. **Verify before booting:**
   - After copying, re-check the file exists
   - Ensure it's named exactly `router-config.nix` (case-sensitive)

2. **Test your config:**
   - Verify the syntax before copying:
     ```bash
     nix-instantiate --parse router-config.nix
     ```

3. **Keep a backup:**
   - Keep a copy of your working config somewhere safe
   - Version control is your friend!

4. **Multiple configs:**
   - You can prepare multiple USB drives with different configs
   - Great for deploying to multiple locations

---

## 🎯 What's Next?

Once your USB is prepared:

1. **Insert into target hardware**
2. **Boot from USB**
3. **Automated menu will detect your config**
4. **Select "Automated Installation"**
5. **Sit back and relax!**

The installer will use your pre-configured settings for a hands-off installation.

---

## 📚 See Also

- [ISO README](README.md) - Complete ISO documentation
- [BUILD-ON-WSL.md](BUILD-ON-WSL.md) - Building the ISO on Windows/WSL
- [Installation Guide](../docs/installation.md) - General installation guide

