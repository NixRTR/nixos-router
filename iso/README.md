# NixOS Router - Custom Installation ISO

This directory contains everything needed to build a custom NixOS installation ISO specifically for the router project.

## 🎯 Features

The custom ISO provides:

- **🚀 Automated Boot Menu** - Starts automatically when the ISO boots
- **📦 Pre-configured Installation** - Uses `router-config.nix` from USB for hands-off setup
- **🔧 Multiple Installation Modes**:
  - Automated installation (with pre-made config)
  - Guided installation (interactive)
  - Update existing router software
  - Update router configuration
- **🛠️ All Tools Included** - No need to download scripts during installation
- **💾 USB Config Detection** - Automatically finds and uses your configuration file

## 📋 Prerequisites

To build the ISO, you need:

- **NixOS** (physical install or WSL2)
- **Nix Flakes** enabled
- **~10 GB free disk space** for the build
- **Fast internet connection** (first build downloads packages)

### Enable Flakes (if not already enabled)

Add to your `/etc/nixos/configuration.nix`:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

## 🔨 Building the ISO

### Option 1: Using the Build Script (Recommended)

```bash
cd iso
chmod +x build-iso.sh
./build-iso.sh
```

The script will:
1. Build the ISO using Nix flakes
2. Show the ISO location and size
3. (On WSL) Copy the ISO to your Windows Downloads folder

### Option 2: Manual Build

```bash
cd iso
nix build .#nixosConfigurations.iso.config.system.build.isoImage
```

The ISO will be in `result/iso/nixos-router-installer.iso`

## 💿 Writing the ISO to USB

### On Windows (from WSL or native)

Use **Rufus** (recommended):
1. Download Rufus from https://rufus.ie/
2. Select your USB drive
3. Select the ISO file
4. Click "START"
5. Choose "Write in DD Image mode" when prompted

Or use **balenaEtcher**:
1. Download from https://www.balena.io/etcher/
2. Select ISO
3. Select USB drive
4. Click "Flash"

### On Linux

```bash
# Find your USB device (BE CAREFUL!)
lsblk

# Write the ISO (replace sdX with your USB device)
sudo dd if=result/iso/nixos-router-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Eject safely
sudo eject /dev/sdX
```

### On macOS

```bash
# Find your disk
diskutil list

# Unmount it (replace diskN)
diskutil unmountDisk /dev/diskN

# Write the ISO
sudo dd if=result/iso/nixos-router-installer.iso of=/dev/rdiskN bs=1m

# Eject
diskutil eject /dev/diskN
```

## 🎮 Using the Custom ISO

### Automated Installation (Recommended)

Perfect for rebuilds or multiple routers with the same configuration:

1. **Prepare your configuration:**
   ```bash
   # Copy your working router-config.nix to a USB drive
   cp router-config.nix /path/to/usb/router-config.nix
   ```

2. **Boot the target machine:**
   - Insert BOTH the installation ISO USB and the config USB
   - Boot from the installation ISO
   - The menu will automatically detect your `router-config.nix`

3. **Select "Automated Installation"** from the menu

4. **Wait for completion** - The installer will:
   - Partition disks
   - Install NixOS
   - Apply your router configuration
   - Set up secrets
   - Reboot into your configured router

### Guided Installation

For first-time setup or when you want to configure interactively:

1. Boot from the ISO
2. Select "Guided Installation" from the menu
3. Follow the interactive prompts
4. Choose Simple or Advanced network configuration
5. Complete the installation

### Updating Existing Router

You can boot an existing router from this ISO to update it:

1. Boot the router from the ISO (without removing its hard drive)
2. Select "Update Router Software" or "Update Router Config"
3. Follow the prompts

## 🗂️ ISO Contents

```
iso/
├── flake.nix              # Nix flake for building the ISO
├── configuration.nix      # ISO system configuration
├── auto-menu.sh          # Automated boot menu script
├── build-iso.sh          # Build script (run this)
└── README.md             # This file
```

### What's Included in the ISO

- **NixOS 25.05** minimal installation environment
- **Auto-menu system** that starts on boot
- **All router installation scripts** (no internet needed during install)
- **Networking tools** (ethtool, tcpdump, nmap, etc.)
- **Text editors** (vim, nano)
- **SSH server** (for remote installation)

## 🔧 Customization

### Changing Default Passwords

Edit `iso/configuration.nix`:

```nix
users.users.nixos.initialPassword = "your-password-here";
```

### Adding Additional Tools

Edit `iso/configuration.nix` and add to `environment.systemPackages`:

```nix
environment.systemPackages = with pkgs; [
  # ... existing packages ...
  your-additional-package
];
```

### Modifying the Boot Menu

Edit `iso/auto-menu.sh` to customize:
- Menu options
- USB detection logic
- Installation workflows
- Branding and colors

### Changing ISO Name

Edit `iso/configuration.nix`:

```nix
isoImage.isoName = "my-custom-name.iso";
isoImage.volumeID = "MY_LABEL";
```

## 🐛 Troubleshooting

### Build Fails with "disk quota exceeded"

You need more disk space:

```bash
# On WSL, increase WSL disk size or clean up space
nix-collect-garbage -d
```

### USB Config Not Detected

The auto-menu looks for `router-config.nix` in:
- `/media/*`
- `/mnt/*`
- `/run/media/*`
- Auto-mounted USB devices

Try mounting manually:

```bash
# Find your USB device
lsblk

# Mount it
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb

# Verify the file is there
ls /mnt/usb/router-config.nix
```

### Menu Doesn't Start Automatically

Run it manually:

```bash
sudo router-menu
```

### ISO Won't Boot

- Ensure **Secure Boot is disabled** in BIOS
- Try **DD mode** in Rufus instead of ISO mode
- Verify the ISO downloaded completely:
  ```bash
  sha256sum result/iso/*.iso
  ```

### Need to Rebuild the ISO

After making changes:

```bash
cd iso
rm -rf result
./build-iso.sh
```

## 📚 Additional Documentation

For router configuration and usage:

- **[Main README](../README.md)** - Project overview
- **[Installation Guide](../docs/installation.md)** - Detailed installation steps
- **[Configuration Guide](../docs/configuration.md)** - Router configuration options
- **[Troubleshooting](../docs/troubleshooting.md)** - Common issues

## 🤝 Contributing

Found a bug or have an improvement for the ISO build system? Open an issue or PR in the main repository.

## 📄 License

MIT License - Same as the main project

