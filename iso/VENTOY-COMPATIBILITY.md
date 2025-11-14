# Ventoy Compatibility Issues and Solutions

## ⚠️ The Problem

If you're seeing a **blank screen** when booting this ISO with Ventoy, you've hit a known compatibility issue between Ventoy and NixOS ISOs.

### Why It Happens

1. **NixOS ISOs** expect to find their root filesystem by searching for a specific volume label (`NIXOS_ROUTER`)
2. **Ventoy** chainloads ISOs from its own partition and presents them differently
3. The NixOS kernel boots but **can't find its root filesystem** and hangs with a blank screen

This is a known issue with Ventoy and many NixOS-based ISOs, not specific to our router project.

---

## ✅ Recommended Solutions

### Solution 1: Use Direct Write (RECOMMENDED)

**Don't use Ventoy for this ISO.** Write it directly to a dedicated USB drive instead:

#### Windows - Use Rufus in DD Mode

1. Download [Rufus](https://rufus.ie/)
2. Select your USB drive
3. Select `nixos-router-installer.iso`
4. **Important:** When prompted, choose **"Write in DD Image mode"**
5. Click START

#### Linux - Use dd

```bash
# Find your USB device (BE CAREFUL!)
lsblk

# Write the ISO directly
sudo dd if=nixos-router-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Replace /dev/sdX with your actual USB device (e.g., /dev/sdb)
```

#### macOS - Use dd

```bash
# Find your USB device
diskutil list

# Unmount it
diskutil unmountDisk /dev/diskN

# Write the ISO
sudo dd if=nixos-router-installer.iso of=/dev/rdiskN bs=1m

# Replace diskN with your actual USB device
```

#### Alternative: balenaEtcher (Cross-platform)

Download [balenaEtcher](https://www.balena.io/etcher/) - works on Windows, Linux, and macOS:
1. Select the ISO
2. Select your USB drive
3. Click "Flash!"

---

### Solution 2: Use Ventoy's Memdisk Mode (Slower)

If you really want to use Ventoy, you can force it to load the entire ISO into memory:

1. Copy the ISO to your Ventoy USB
2. Create a JSON file in `/ventoy/` named `ventoy.json`:

```json
{
  "persistence": [
  ],
  "menu_alias": [
    {
      "image": "/nixos-router-installer.iso",
      "alias": "NixOS Router Installer (Memdisk)"
    }
  ],
  "menu_tip": [
  ],
  "menu_class": [
    {
      "key": "VTMEMDISK",
      "class": "vtmemdisk"
    }
  ],
  "auto_memdisk": [
    "/nixos-router-installer.iso"
  ]
}
```

**Warning:** This loads the entire ISO (~800MB) into RAM, so boot will be slower and you need enough memory.

---

### Solution 3: Try Ventoy's GRUB2 Mode

Ventoy has different boot modes. Try switching:

1. Press **F5** at the Ventoy menu (or during boot selection)
2. Select the ISO
3. Choose **"Boot in GRUB2 mode"** instead of default

This sometimes works better with NixOS ISOs.

---

### Solution 4: Manual Boot Parameters (Advanced)

If you want to debug or try to make it work with Ventoy:

1. At the Ventoy menu, press **`e`** to edit boot parameters
2. Find the `linux` line
3. Add these parameters:

```bash
root=live:LABEL=NIXOS_ROUTER iso-scan/filename=/nixos-router-installer.iso
```

This tells the kernel where to find the ISO, but results may vary.

---

## 🎯 Our Recommendation

**For the best experience with this router ISO:**

1. ✅ **Use a dedicated USB drive** with direct write (Rufus DD mode or `dd`)
2. ✅ After writing, you can add your `router-config.nix` to `/config/` on the USB
3. ✅ Boot from this dedicated USB

**Why?**
- Guaranteed to work
- No boot delays
- Better performance
- Can add your config directly to the USB

---

## 🔍 Debugging

If you still have boot issues (even with direct write):

### Check Boot Mode

Make sure your BIOS is configured correctly:
- **UEFI mode:** Most modern systems (recommended)
- **Legacy/BIOS mode:** Older systems
- The ISO supports both, but check your BIOS settings

### Check the ISO File

Verify the ISO isn't corrupted:

```bash
# On Linux/macOS
sha256sum nixos-router-installer.iso

# On Windows (PowerShell)
Get-FileHash nixos-router-installer.iso -Algorithm SHA256
```

### Serial Console Output

If you have a serial console connected, you can see actual boot errors:
1. Connect serial cable (if available)
2. Boot the ISO
3. Watch for error messages about "unable to find root device"

### Enable Verbose Boot

If you can get to a boot menu:
1. Press **`e`** at the boot menu
2. Remove `quiet` from kernel parameters
3. Add `debug` to see more output
4. Press **Ctrl+X** or **F10** to boot

---

## 📚 Additional Resources

- [NixOS ISO Issues on Ventoy GitHub](https://github.com/ventoy/Ventoy/issues?q=nixos)
- [NixOS Wiki - Creating Bootable Media](https://nixos.wiki/wiki/Bootable_USB_stick)
- [Ventoy Documentation](https://www.ventoy.net/en/doc_start.html)

---

## 💬 Still Having Issues?

If none of these solutions work:

1. **Check your hardware:**
   - Try a different USB port
   - Try a different USB drive
   - Check BIOS boot settings

2. **Try the traditional network install:**
   - Boot a minimal NixOS ISO
   - Run our online installer script:
     ```bash
     curl -L https://beard.click/nixos-router | sudo bash
     ```

3. **Check the project GitHub issues** for similar problems and solutions

---

## ✨ Summary

| Method | Speed | Complexity | Success Rate |
|--------|-------|------------|--------------|
| **Rufus DD Mode** ⭐ | Fast | Easy | 100% |
| **dd command** ⭐ | Fast | Medium | 100% |
| **balenaEtcher** ⭐ | Fast | Easy | 100% |
| Ventoy Memdisk | Slow | Medium | 90% |
| Ventoy GRUB2 | Fast | Medium | 60% |
| Ventoy Default | Fast | Easy | 10% ⚠️ |

**Bottom line:** Use a dedicated USB with direct write for the best experience.

