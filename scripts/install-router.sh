#!/usr/bin/env bash

# NixOS Router Installation Script
# Automated installation from NixOS installer ISO

set -euo pipefail

# Configuration
REPO_URL="https://github.com/beardedtek/nixos-router.git"  # Update this with your actual repo URL

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

    # Wipe existing partition table
    wipefs -a "$DISK"

    # Create GPT partition table
    parted "$DISK" -- mklabel gpt

    # Create EFI partition (512MB)
    parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
    parted "$DISK" -- set 1 esp on

    # Create root partition (remaining space)
    parted "$DISK" -- mkpart primary 512MiB 100%

    log_success "Disk partitioned successfully"
}

# Format partitions
format_partitions() {
    log_info "Formatting partitions"

    # Format EFI partition
    mkfs.fat -F 32 -n EFI "${DISK}1"

    # Format root partition with Btrfs
    mkfs.btrfs -L nixos "${DISK}2"

    log_success "Partitions formatted"
}

# Mount filesystems
mount_filesystems() {
    log_info "Mounting filesystems"

    # Mount root partition
    mount "${DISK}2" /mnt

    # Create and mount EFI partition
    mkdir -p /mnt/boot
    mount "${DISK}1" /mnt/boot

    log_success "Filesystems mounted"
}

# Generate NixOS configuration
generate_config() {
    log_info "Generating NixOS configuration"

    # Generate hardware configuration
    nixos-generate-config --root /mnt

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

    # Update hostname and timezone in configuration.nix
    sed -i "s/networking.hostName = \".*\";/networking.hostName = \"$HOSTNAME\";/g" /mnt/etc/nixos/configuration.nix
    sed -i "s/time.timeZone = \".*\";/time.timeZone = \"$TIMEZONE\";/g" /mnt/etc/nixos/configuration.nix

    log_success "Router configuration copied and customized"
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
        nix run nixpkgs#age -- generate-keypair \
            --output /mnt/var/lib/sops-nix/key.txt
    fi

    # Copy Age key for root user
    cp /mnt/var/lib/sops-nix/key.txt /mnt/root/.config/sops/age/keys.txt
    chmod 400 /mnt/root/.config/sops/age/keys.txt

    # Get public key for user
    AGE_PUBKEY=$(nix run nixpkgs#age -- keygen --output /dev/null --public-key < /mnt/var/lib/sops-nix/key.txt)

    log_success "Age keys configured"
    log_warning "IMPORTANT: Save this public key for encrypting secrets:"
    echo "$AGE_PUBKEY"
    log_warning "You will need it to encrypt your secrets.yaml file"
}

# Create initial secrets template
create_secrets_template() {
    log_info "Creating secrets template"

    cat > /mnt/etc/nixos/secrets/secrets.yaml << EOF
# Example secrets - replace with your actual values
# Encrypt this file with: sops --encrypt --age $AGE_PUBKEY secrets.yaml

pppoe-username: "your-isp-username"
pppoe-password: "your-isp-password"
password: "$(mkpasswd -m sha512)"
EOF

    log_warning "Created secrets template at /mnt/etc/nixos/secrets/secrets.yaml"
    log_warning "You MUST encrypt this file with your Age public key before booting"
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
    generate_config
    setup_router_config
    setup_secrets
    create_secrets_template
    install_nixos
    post_install_message
}

# Run main function
main "$@"
