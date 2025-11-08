#!/usr/bin/env bash

# NixOS Router Installation Script
# Automated installation from NixOS installer ISO

set -euo pipefail

# Configuration
REPO_URL="https://github.com/beardedtek/nixos-router.git"  # Update this with your actual repo URL

# Initialize variables
PPPOE_USER=""
PPPOE_PASS=""
USER_PASSWORD=""

# Interactive configuration
echo "Available disks:"
lsblk -d -n -o NAME,SIZE,MODEL | grep -v loop
echo

read -p "Enter target disk [/dev/sda]: " DISK_INPUT
DISK="${DISK_INPUT:-/dev/sda}"

read -p "Enter hostname [nixos-router]: " HOSTNAME_INPUT
HOSTNAME="${HOSTNAME_INPUT:-nixos-router}"

read -p "Enter timezone [America/Anchorage]: " TIMEZONE_INPUT
TIMEZONE="${TIMEZONE_INPUT:-America/Anchorage}"

# Network configuration
echo
echo "Network Configuration:"
echo "Available network interfaces:"
ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/://' | grep -v lo
echo

read -p "Enter WAN interface [eno1]: " WAN_INTERFACE_INPUT
WAN_INTERFACE="${WAN_INTERFACE_INPUT:-eno1}"

echo "WAN connection types:"
echo "1) DHCP (most home networks)"
echo "2) PPPoE (some ISPs)"
read -p "Enter WAN type (1 or 2) [1]: " WAN_TYPE_CHOICE
case ${WAN_TYPE_CHOICE:-1} in
    1) WAN_TYPE="dhcp" ;;
    2) WAN_TYPE="pppoe" ;;
    *) WAN_TYPE="dhcp" ;;
esac

if [[ "$WAN_TYPE" == "pppoe" ]]; then
    read -p "Enter PPPoE username: " PPPOE_USER
    read -s -p "Enter PPPoE password: " PPPOE_PASS
    echo
fi

# Collect user password
read -s -p "Enter password for routeradmin user: " USER_PASSWORD
echo
read -s -p "Confirm password for routeradmin user: " USER_PASSWORD_CONFIRM
echo

# Verify passwords match
if [[ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
    log_error "Passwords do not match!"
    exit 1
fi

if [[ -z "$USER_PASSWORD" ]]; then
    log_error "Password cannot be empty!"
    exit 1
fi

read -p "Enter LAN IP address [192.168.4.1]: " LAN_IP_INPUT
LAN_IP="${LAN_IP_INPUT:-192.168.4.1}"

read -p "Enter LAN subnet prefix length [24]: " LAN_PREFIX_INPUT
LAN_PREFIX="${LAN_PREFIX_INPUT:-24}"

read -p "Enter DHCP range start [192.168.4.100]: " DHCP_START_INPUT
DHCP_START="${DHCP_START_INPUT:-192.168.4.100}"

read -p "Enter DHCP range end [192.168.4.200]: " DHCP_END_INPUT
DHCP_END="${DHCP_END_INPUT:-192.168.4.200}"

echo "Available interfaces for LAN bridge (space-separated):"
read -p "Enter LAN bridge interfaces [enp4s0 enp5s0 enp6s0 enp7s0]: " LAN_INTERFACES_INPUT
LAN_INTERFACES="${LAN_INTERFACES_INPUT:-enp4s0 enp5s0 enp6s0 enp7s0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if we're on NixOS installer
check_installer() {
    if ! command -v nixos-install &> /dev/null; then
        log_error "This script must be run from NixOS installer ISO"
        exit 1
    fi
}

# Partition disk
partition_disk() {
    log_info "Partitioning disk: $DISK"

    # Unmount any existing mounts on the disk
    for part in "${DISK}"[0-9]*; do
        if mountpoint -q "$part" 2>/dev/null; then
            umount "$part" || true
        fi
    done

    # Wipe existing partition table and filesystem signatures
    wipefs -a "$DISK"
    sgdisk --zap-all "$DISK" || true

    # Create GPT partition table
    parted "$DISK" -- mklabel gpt

    # Create EFI partition (512MB)
    parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
    parted "$DISK" -- set 1 esp on

    # Create root partition (remaining space)
    parted "$DISK" -- mkpart primary 512MiB 100%

    # Wait for kernel to recognize new partitions
    partprobe "$DISK" || true
    sleep 2

    log_success "Disk partitioned successfully"
}

# Format partitions
format_partitions() {
    log_info "Formatting partitions"

    # Format EFI partition
    mkfs.fat -F 32 -n EFI "${DISK}1"

    # Format root partition with Btrfs (force overwrite any existing filesystem)
    mkfs.btrfs -f -L nixos "${DISK}2"

    # Ensure partitions are recognized and have UUIDs
    partprobe "$DISK" || true
    sleep 2

    # Verify UUIDs are available
    local root_uuid efi_uuid
    root_uuid=$(blkid -s UUID -o value "${DISK}2" 2>/dev/null)
    efi_uuid=$(blkid -s UUID -o value "${DISK}1" 2>/dev/null)

    if [[ -z "$root_uuid" || -z "$efi_uuid" ]]; then
        log_warning "UUIDs not immediately available, waiting longer..."
        sleep 3
        root_uuid=$(blkid -s UUID -o value "${DISK}2" 2>/dev/null)
        efi_uuid=$(blkid -s UUID -o value "${DISK}1" 2>/dev/null)
    fi

    if [[ -n "$root_uuid" && -n "$efi_uuid" ]]; then
        log_info "Root UUID: $root_uuid"
        log_info "EFI UUID: $efi_uuid"
    else
        log_warning "UUIDs still not available - system may have boot issues"
    fi

    log_success "Partitions formatted"
}

# Mount filesystems
mount_filesystems() {
    log_info "Mounting filesystems"

    # Ensure partitions are recognized
    partprobe "$DISK" || true
    sleep 1

    # Get UUIDs for stable mounting
    local root_uuid
    local efi_uuid

    root_uuid=$(blkid -s UUID -o value "${DISK}2" 2>/dev/null)
    efi_uuid=$(blkid -s UUID -o value "${DISK}1" 2>/dev/null)

    if [[ -n "$root_uuid" && -n "$efi_uuid" ]]; then
        log_info "Mounting by UUID for stability"
        mount "UUID=$root_uuid" /mnt
        mkdir -p /mnt/boot
        mount "UUID=$efi_uuid" /mnt/boot
    else
        log_warning "UUIDs not available, mounting by device name"
        mount "${DISK}2" /mnt
        mkdir -p /mnt/boot
        mount "${DISK}1" /mnt/boot
    fi

    log_success "Filesystems mounted"
}

# Generate NixOS configuration
generate_config() {
    log_info "Generating NixOS configuration"

    # Ensure filesystems are properly detected
    partprobe "$DISK" || true
    sleep 1

    # Use a temporary directory to avoid overwriting existing config files
    local tmp_config
    tmp_config=$(mktemp -d)

    log_info "Running nixos-generate-config into temporary directory $tmp_config"
    if ! nixos-generate-config --root /mnt --dir "$tmp_config"; then
        log_error "nixos-generate-config failed"
        rm -rf "$tmp_config"
        exit 1
    fi

    # Copy the generated hardware configuration into our install
    if [[ -f "$tmp_config/hardware-configuration.nix" ]]; then
        log_info "Updating /etc/nixos/hardware-configuration.nix with generated version"
        cp "$tmp_config/hardware-configuration.nix" /mnt/etc/nixos/hardware-configuration.nix
    else
        log_error "Generated hardware-configuration.nix not found"
        rm -rf "$tmp_config"
        exit 1
    fi

    # Clean up temporary configuration
    rm -rf "$tmp_config"

    # Confirm filesystem entries and ensure Btrfs is set
    if [[ -f /mnt/etc/nixos/hardware-configuration.nix ]]; then
        log_info "Hardware configuration (filesystem section):"
        grep -A3 -B3 "fsType\|fileSystems" /mnt/etc/nixos/hardware-configuration.nix || true

        # Ensure fsType is set to btrfs for the root filesystem
        sed -i '0,/fsType = \"btrfs\"/s//fsType = \"btrfs\"/' /mnt/etc/nixos/hardware-configuration.nix
    fi

    log_success "NixOS configuration generated"
}

# Clone and setup router configuration
setup_router_config() {
    log_info "Setting up router configuration"

    # Clone the router repository
    git clone "$REPO_URL" /mnt/etc/nixos/router-config

    # Copy configuration files
    cp -r /mnt/etc/nixos/router-config/* /mnt/etc/nixos/
    rm -rf /mnt/etc/nixos/router-config  # Remove the cloned repo, keep only contents

    # Generate router configuration file
    log_info "Generating router configuration file"

    # Convert space-separated interfaces to Nix array format
    LAN_INTERFACES_NIX="[ $(echo "$LAN_INTERFACES" | sed 's/ /" "/g' | sed 's/^/"/g' | sed 's/$/"/g') ]"

    # Create router-config.nix with actual values
    cat > /mnt/etc/nixos/router-config.nix << EOF
# Router configuration variables
# This file is generated by the installation script

{
  # System settings
  hostname = "$HOSTNAME";
  timezone = "$TIMEZONE";
  username = "routeradmin";

  # WAN configuration
  wan = {
    type = "$WAN_TYPE";  # "dhcp" or "pppoe"
    interface = "$WAN_INTERFACE";
  };

  # LAN configuration
  lan = {
    interfaces = $LAN_INTERFACES_NIX;  # Bridge interfaces
    ip = "$LAN_IP";
    prefix = $LAN_PREFIX;
  };

  # DHCP configuration
  dhcp = {
    start = "$DHCP_START";
    end = "$DHCP_END";
  };
}
EOF

    log_info "Configuration file generated:"
    echo "  Hostname: $HOSTNAME"
    echo "  Timezone: $TIMEZONE"
    echo "  WAN: $WAN_INTERFACE ($WAN_TYPE)"
    echo "  LAN: $LAN_IP/$LAN_PREFIX"
    echo "  DHCP: $DHCP_START - $DHCP_END"
    echo "  Interfaces: $LAN_INTERFACES"

    log_success "Router configuration file generated"
}

# Setup Age keys and secrets
setup_secrets() {
    log_info "Setting up Age keys and secrets"

    mkdir -p /mnt/var/lib/sops-nix
    mkdir -p /mnt/root/.config/sops/age

    # Ask about existing Age key
    read -p "Do you have an existing Age private key? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Using existing Age key"

        # Ask how to provide the key
        echo "How would you like to provide your Age key?"
        echo "1) Paste it directly"
        echo "2) Specify a file path"
        read -p "Enter choice (1 or 2): " key_choice

        case $key_choice in
            1)
                echo "Paste your Age private key (end with Ctrl-D):"
                AGE_KEY=$(cat)
                echo "$AGE_KEY" > /mnt/var/lib/sops-nix/key.txt
                ;;
            2)
                read -p "Enter the path to your Age private key file: " key_file
                if [[ ! -f "$key_file" ]]; then
                    log_error "Key file not found: $key_file"
                    exit 1
                fi
                cp "$key_file" /mnt/var/lib/sops-nix/key.txt
                ;;
            *)
                log_error "Invalid choice"
                exit 1
                ;;
        esac
    else
        log_info "Generating new Age key"
        # Generate Age key
        nix shell --experimental-features nix-command --extra-experimental-features flakes nixpkgs#age -c age-keygen -o /mnt/var/lib/sops-nix/key.txt
    fi

    # Copy Age key for root user
    cp /mnt/var/lib/sops-nix/key.txt /mnt/root/.config/sops/age/keys.txt
    chmod 400 /mnt/root/.config/sops/age/keys.txt

    # Get public key for user (extract from the private key file comments)
    AGE_PUBKEY=$(grep "# public key:" /mnt/var/lib/sops-nix/key.txt | cut -d' ' -f4)

    log_success "Age keys configured"
    log_info "Age public key: $AGE_PUBKEY"
    log_info "Keys are ready for encrypting secrets"
}

# Create and encrypt secrets
create_and_encrypt_secrets() {
    log_info "Creating and encrypting secrets"

    # Create temporary plaintext secrets file
    local secrets_yaml="/tmp/secrets-plain.yaml"

    mkdir -p /mnt/etc/nixos/secrets

    cat > "$secrets_yaml" << EOF
# Router secrets - encrypted with Age
EOF

    # Include PPPoE credentials if provided
    if [[ -n "$PPPOE_USER" && -n "$PPPOE_PASS" ]]; then
        cat >> "$secrets_yaml" << EOF
pppoe-username: "$PPPOE_USER"
pppoe-password: "$PPPOE_PASS"
EOF
    fi

    # Store plain text password (will be hashed at runtime)
    cat >> "$secrets_yaml" << EOF
password: "$USER_PASSWORD"
EOF

    # Encrypt the secrets file
    log_info "Encrypting secrets with Age key"
    nix shell --experimental-features nix-command --extra-experimental-features flakes nixpkgs#sops -c \
        sops --encrypt --age $(grep -o 'age1[0-9a-z]*' /mnt/var/lib/sops-nix/key.txt | head -1) --in-place $secrets_yaml

    # Move encrypted secrets into the NixOS configuration directory
    cp "$secrets_yaml" /mnt/etc/nixos/secrets/secrets.yaml
    rm -f "$secrets_yaml"

    log_success "Secrets encrypted and saved to /mnt/etc/nixos/secrets/secrets.yaml"
    log_info "Your secrets are now securely encrypted with your Age key"
}

# Install NixOS
install_nixos() {
    log_info "Installing NixOS"

    # Install with flake
    nixos-install --flake /mnt/etc/nixos#router --no-root-passwd

    log_success "NixOS installed successfully"
}

# Post-installation message
post_install_message() {
    log_success "Installation completed!"
    echo
    log_warning "IMPORTANT NEXT STEPS:"
    echo
    echo "1. Encrypt your secrets:"
    echo "   cd /mnt/etc/nixos"
    echo "   sops --encrypt --age $AGE_PUBKEY secrets/secrets.yaml"
    echo
    echo "2. Unmount filesystems:"
    echo "   umount -R /mnt"
    echo
    echo "3. Reboot:"
    echo "   reboot"
    echo
    echo "4. After reboot, complete setup:"
    echo "   - Connect to router via SSH or console"
    echo "   - Update secrets with real values"
    echo "   - Configure network settings"
    echo
    log_warning "Age Public Key (save this): $AGE_PUBKEY"
}

# Main installation function
main() {
    echo "======================================="
    echo "  NixOS Router Installation Script"
    echo "======================================="

    check_root
    check_installer

    read -p "This will DESTROY all data on $DISK. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi

    partition_disk
    format_partitions
    mount_filesystems
    setup_router_config
    generate_config
    setup_secrets
    create_and_encrypt_secrets
    install_nixos
    post_install_message
}

# Run main function
main "$@"
