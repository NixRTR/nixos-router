# Building the ISO on NixOS WSL

This guide walks you through building the custom NixOS Router installation ISO using NixOS WSL on Windows.

## 📋 Prerequisites

1. **NixOS WSL installed** - You mentioned you have this at `@NixOS WSL`
2. **~10-15 GB free space** in your WSL instance
3. **Fast internet connection** for the first build

## 🚀 Quick Start

### Step 1: Open NixOS WSL

Open PowerShell or Windows Terminal and start your NixOS WSL instance:

```powershell
wsl -d NixOS
```

### Step 2: Clone or Navigate to the Repository

If you're working from your Windows files:

```bash
# Navigate to the Windows directory
cd /mnt/c/Users/Willi/github/nixos-router/iso
```

Or clone fresh:

```bash
cd ~
git clone https://github.com/your-username/nixos-router.git
cd nixos-router/iso
```

### Step 3: Ensure Flakes are Enabled

Check if flakes are enabled:

```bash
nix flake --version
```

If you get an error, enable flakes:

```bash
# Edit NixOS configuration
sudo nano /etc/nixos/configuration.nix

# Add this line inside the { ... } block:
#   nix.settings.experimental-features = [ "nix-command" "flakes" ];

# Save and rebuild
sudo nixos-rebuild switch
```

### Step 4: Build the ISO

```bash
chmod +x build-iso.sh
./build-iso.sh
```

The build process will:
1. Download required packages (~2-3 GB)
2. Build the custom ISO (~5-10 minutes)
3. Copy the ISO to your Windows Downloads folder

### Step 5: Write to USB

Once complete, the ISO will be at:
```
C:\Users\Willi\Downloads\nixos-router-installer.iso
```

Use **Rufus** to write it to a USB drive:
1. Download Rufus: https://rufus.ie/
2. Select your USB drive (⚠️ all data will be erased!)
3. Select the ISO file
4. Click START
5. Choose "Write in DD Image mode"

## 🎯 Testing the ISO (Optional)

You can test the ISO in QEMU before writing to USB:

```bash
# From NixOS WSL
cd /mnt/c/Users/Willi/github/nixos-router/iso

# Run in QEMU (requires QEMU installed in WSL)
nix-shell -p qemu --run "qemu-system-x86_64 -cdrom result/iso/*.iso -m 2048 -enable-kvm"
```

Note: KVM acceleration won't work in WSL, so it will be slow. Physical hardware testing is better.

## 🔧 Troubleshooting

### "No space left on device"

WSL has limited disk space by default. Increase it:

1. Shut down WSL:
   ```powershell
   wsl --shutdown
   ```

2. Find your WSL disk:
   ```powershell
   # Usually at:
   %USERPROFILE%\AppData\Local\Packages\*NixOS*\LocalState\ext4.vhdx
   ```

3. Expand it (in PowerShell as Administrator):
   ```powershell
   Resize-VHD -Path "C:\Users\Willi\AppData\Local\Packages\...\ext4.vhdx" -SizeBytes 100GB
   ```

4. Restart WSL and resize the filesystem:
   ```bash
   sudo resize2fs /dev/sdb
   ```

Or clean up space:

```bash
# Remove old build artifacts
nix-collect-garbage -d

# Check free space
df -h
```

### "Permission denied" when copying to Downloads

Make sure the Windows path is accessible:

```bash
# Check if Windows user directory is accessible
ls /mnt/c/Users/Willi/Downloads

# If not, you may need to adjust WSL permissions or copy manually
```

### Build is taking forever

The first build will download several GB of packages. Subsequent builds will be much faster.

To see progress:

```bash
# Build with verbose output
nix build .#nixosConfigurations.iso.config.system.build.isoImage -L --show-trace
```

### Getting "experimental feature 'flakes' not enabled"

Enable flakes as shown in Step 3 above, or build without flakes:

```bash
# Legacy build method (not recommended)
nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=./configuration.nix
```

## 📦 What Gets Built

The ISO includes:

- **NixOS 25.05** minimal installer
- **Automated boot menu** that starts on boot
- **All router installation scripts** embedded (no internet needed)
- **Networking tools** for debugging
- **SSH server** for remote installation

## 🎮 After Building

Once you have the ISO on USB:

1. **Boot your target router hardware** from the USB
2. **The menu will start automatically**
3. **Select your installation option**:
   - Automated (if you have router-config.nix on a separate USB)
   - Guided (interactive configuration)

## 🔄 Rebuilding After Changes

If you modify the ISO configuration:

```bash
cd /mnt/c/Users/Willi/github/nixos-router/iso

# Clean old build
rm -rf result

# Rebuild
./build-iso.sh
```

## 💡 Tips

1. **Save the built ISO** - Keep a copy somewhere safe so you don't need to rebuild every time
2. **Version your ISOs** - Rename them with dates: `nixos-router-2025-11-13.iso`
3. **Test in VM first** - If possible, test major changes in a VM before physical hardware
4. **Keep config separate** - Don't embed sensitive configs in the ISO; use the USB detection feature

## 🆘 Still Having Issues?

1. Check the main [ISO README](README.md)
2. Check the [Troubleshooting Guide](../docs/troubleshooting.md)
3. Verify your NixOS WSL installation:
   ```bash
   cat /etc/NIXOS
   nix --version
   ```

## 🚀 Next Steps

After building the ISO:

1. Write it to USB (see Step 5 above)
2. Prepare your `router-config.nix` (optional)
3. Boot your router hardware from the USB
4. Follow the automated menu

See [ISO README](README.md) for detailed usage instructions.

