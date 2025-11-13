# Installation Guide

This guide covers installing the NixOS router from scratch.

## Prerequisites

- A dedicated PC/server for the router
- At least 2 network interfaces (1 WAN + 1+ LAN)
- USB drive with NixOS installer ISO
- 15 minutes of time

## Installation Methods

You can install the router using either:

1. **🎯 Custom ISO (Recommended)** - Pre-built ISO with automated menu system
   - No internet required during installation
   - Supports automated installation with pre-configured settings
   - Includes all tools and scripts
   - See [../iso/README.md](../iso/README.md) for build instructions

2. **🌐 Online Installer** - Download and run installation script
   - Requires internet connection during installation
   - Smaller initial ISO download
   - Always uses latest scripts

Both methods result in the same router configuration. Choose based on your preference.

---

## Method 1: Custom ISO Installation

### Build the Custom ISO

From NixOS or NixOS WSL:

```bash
cd iso
./build-iso.sh
```

**Detailed guides:**
- General: [iso/README.md](../iso/README.md)
- Windows/WSL: [iso/BUILD-ON-WSL.md](../iso/BUILD-ON-WSL.md)

### Write ISO to USB

Use Rufus (Windows), balenaEtcher, or `dd` (Linux/Mac) to write the ISO to a USB drive.

### Boot and Install

1. Boot your router hardware from the custom ISO
2. The automated menu will start automatically
3. Choose your installation option:
   - **Automated** (if you have `router-config.nix` on a separate USB)
   - **Guided** (interactive configuration)

The menu system will handle everything else!

---

## Method 2: Online Installer (Quick Install)

### Step 1: Boot NixOS Installer

1. Download the latest NixOS ISO from [nixos.org](https://nixos.org/download.html)
2. Create a bootable USB drive
3. Boot your router hardware from the USB
4. Wait for the installer to load

### Step 2: Run Automated Installer

```bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

The script will interactively ask for:

#### System Configuration
- **Target disk** (shows available disks)
- **Hostname** (default: `nixos-router`)
- **Timezone** (default: `America/Anchorage`)
- **Admin password** (for SSH/console access)

#### Network Configuration
- **WAN interface** (e.g., `eno1`)
- **WAN type** (DHCP or PPPoE)
- **PPPoE credentials** (if applicable)

#### LAN Configuration Mode

The installer offers two modes:

**1. Simple Mode (Recommended for most users)**
- Single bridge network (`br0`)
- One LAN IP and DHCP range
- All LAN ports bridged together
- Perfect for home networks

**2. Advanced Mode (Multi-network with isolation)**
- Two bridge networks (`br0` = HOMELAB, `br1` = LAN)
- Separate IP ranges and DHCP for each network
- Firewall isolation between networks
- Ideal for separating IoT/servers from workstations

The installer will prompt:
- **LAN mode** (Simple or Advanced)
- **LAN IP address(es)** and subnet
- **DHCP ranges** for each network
- **Bridge interfaces** for each network

#### Encryption Keys
- Option to use **existing Age key** or generate new one
- Age public key will be displayed (save this!)

### Step 3: Installation Process

The script will:
1. ✅ Partition and format the disk (GPT + EFI)
2. ✅ Install NixOS with router configuration
3. ✅ Set up encryption keys
4. ✅ Configure secrets
5. ✅ Install the system

### Step 4: First Boot

After installation completes:

```bash
# Unmount filesystems
sudo umount -R /mnt

# Reboot
sudo reboot
```

Remove the USB drive and let the system boot from disk.

### Step 5: Initial Login

The router will auto-login on the console as `routeradmin` (or your chosen username).

You can also SSH from a LAN device:

```bash
ssh routeradmin@192.168.2.1
# Or whatever IP you configured
```

---

## Manual Installation

If you prefer manual installation:

### 1. Partition and Format

```bash
# Example for /dev/sda
# EFI partition (512MB)
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 1 esp on
# Root partition (remaining space)
parted /dev/sda -- mkpart primary 512MiB 100%

# Format
mkfs.fat -F 32 -n EFI /dev/sda1
mkfs.ext4 -L nixos /dev/sda2
```

### 2. Mount Filesystems

```bash
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
```

### 3. Clone Configuration

```bash
cd /mnt/etc
git clone https://github.com/beardedtek/nixos-router.git nixos
cd nixos
```

### 4. Generate Hardware Config

```bash
nixos-generate-config --root /mnt --dir /mnt/etc/nixos
# This creates hardware-configuration.nix
```

### 5. Configure Router

Edit `/mnt/etc/nixos/router-config.nix` with your settings.

See [Configuration Guide](configuration.md) for details.

### 6. Set Up Encryption

```bash
# Generate Age key
mkdir -p /mnt/var/lib/sops-nix
age-keygen -o /mnt/var/lib/sops-nix/key.txt

# Get public key
grep "public key:" /mnt/var/lib/sops-nix/key.txt
# Save this key!

# Create secrets file
cat > /mnt/etc/nixos/secrets/secrets.yaml << EOF
password: "your-password-here"
EOF

# Encrypt with your Age public key
sops --encrypt --age age1... /mnt/etc/nixos/secrets/secrets.yaml
```

### 7. Install

```bash
nixos-install --flake /mnt/etc/nixos#router --no-root-passwd
```

### 8. Reboot

```bash
umount -R /mnt
reboot
```

---

## Post-Installation

After first boot:

### Verify Network

```bash
# Check interfaces
ip addr show

# Check bridges
ip link show br0
ip link show br1  # If using multi-LAN

# Test internet
ping 1.1.1.1
```

### Check Services

```bash
# DNS
systemctl status pdns-recursor powerdns

# DHCP
systemctl status kea-dhcp4-server

# Dashboard
systemctl status grafana
systemctl status prometheus
```

### Access Dashboard

**Grafana (Monitoring):**
- URL: `http://192.168.2.1:3000` (or your LAN IP)
- Default login: `admin` / `admin`
- Change password on first login!

**PowerDNS Admin (DNS Management):**
- URL: `http://192.168.2.1:9191` (or your LAN IP)
- Login: Use your system credentials (same as SSH)
- Already configured and ready to use
- See [PowerDNS Guide](powerdns.md) for details

---

## What's Next?

- **[Configuration Guide](configuration.md)** - Customize your router
- **[Network Isolation](isolation.md)** - Set up multi-LAN segments
- **[Optional Features](optional-features.md)** - Enable DynDNS, VPN, etc.
- **[Monitoring](monitoring.md)** - Explore the dashboard

---

## Troubleshooting Installation

### Network Interfaces Not Found

If the installer doesn't show your network interfaces:

```bash
# List all interfaces
ip link show

# Load drivers if needed
modprobe <driver-name>
```

### Disk Partitioning Errors

If the disk has existing partitions:

```bash
# Wipe all partitions
wipefs -a /dev/sda
sgdisk --zap-all /dev/sda
```

### Installation Fails

Check for errors:

```bash
# View full logs
journalctl -xb

# Check disk space
df -h /mnt
```

### Can't Boot After Install

1. Boot back into installer USB
2. Mount filesystems: `mount /dev/sda2 /mnt && mount /dev/sda1 /mnt/boot`
3. Check configuration: `cat /mnt/etc/nixos/configuration.nix`
4. Try reinstall: `nixos-install --flake /mnt/etc/nixos#router --no-root-passwd`

### Age Key Issues

If secrets aren't decrypting:

```bash
# Verify key exists
cat /var/lib/sops-nix/key.txt

# Verify secrets file is encrypted properly
sops --decrypt /etc/nixos/secrets/secrets.yaml
```

For more help, see [Troubleshooting](troubleshooting.md).

