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
    log_info "Updating hostname to: $HOSTNAME"
    awk -v hostname="$HOSTNAME" '
        /^networking\.hostName = ".*";$/ {
            print "networking.hostName = \"" hostname "\";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    log_info "Updating timezone to: $TIMEZONE"
    awk -v timezone="$TIMEZONE" '
        /^time\.timeZone = ".*";$/ {
            print "time.timeZone = \"" timezone "\";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    # Update network configuration
    log_info "Updating WAN interface to: $WAN_INTERFACE"
    awk -v wan_iface="$WAN_INTERFACE" '
        /^      interface = "eno1";$/ {
            print "      interface = \"" wan_iface "\";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    if [[ "$WAN_TYPE" == "pppoe" ]]; then
        # Switch to PPPoE configuration
        sed -i 's/      type = "dhcp";/      type = "pppoe";/g' /mnt/etc/nixos/configuration.nix
        sed -i 's/#      type = "pppoe";/       type = "pppoe";/g' /mnt/etc/nixos/configuration.nix
        sed -i 's/#      pppoe = {/       pppoe = {/g' /mnt/etc/nixos/configuration.nix
        sed -i 's/#        passwordFile = config.sops.secrets."pppoe-password".path;/         passwordFile = config.sops.secrets."pppoe-password".path;/g' /mnt/etc/nixos/configuration.nix
        sed -i 's/#        user = config.sops.secrets."pppoe-username".path;/         user = config.sops.secrets."pppoe-username".path;/g' /mnt/etc/nixos/configuration.nix
        sed -i 's/#        service = null;/         service = null;/g' /mnt/etc/nixos/configuration.nix
        sed -i 's/#        ipv6 = false;/         ipv6 = false;/g' /mnt/etc/nixos/configuration.nix
    fi

    # Update LAN configuration
    log_info "Updating LAN IP to: $LAN_IP"
    awk -v lan_ip="$LAN_IP" '
        /^      address = "192\.168\.4\.1";$/ {
            print "      address = \"" lan_ip "\";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    log_info "Updating LAN prefix to: $LAN_PREFIX"
    awk -v lan_prefix="$LAN_PREFIX" '
        /^      prefixLength = 24;$/ {
            print "      prefixLength = " lan_prefix ";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    log_info "Updating DHCP range: $DHCP_START - $DHCP_END"
    awk -v dhcp_start="$DHCP_START" '
        /^      rangeStart = "192\.168\.4\.100";$/ {
            print "      rangeStart = \"" dhcp_start "\";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    awk -v dhcp_end="$DHCP_END" '
        /^      rangeEnd = "192\.168\.4\.200";$/ {
            print "      rangeEnd = \"" dhcp_end "\";"
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

    # Update LAN interfaces - this is more complex as it's an array
    # Convert space-separated string to Nix array format
    LAN_INTERFACES_NIX=$(echo "$LAN_INTERFACES" | sed 's/ /" "/g' | sed 's/^/[/g' | sed 's/$/"];/g')
    log_info "Updating LAN interfaces to: $LAN_INTERFACES_NIX"
    awk -v lan_interfaces="$LAN_INTERFACES_NIX" '
        /^      bridge\.interfaces = \[ \"enp4s0\" \"enp5s0\" \"enp6s0\" \"enp7s0\" \];$/ {
            print "      bridge.interfaces = " lan_interfaces
            next
        }
        { print }
    ' /mnt/etc/nixos/configuration.nix > /tmp/configuration.nix.tmp && mv /tmp/configuration.nix.tmp /mnt/etc/nixos/configuration.nix

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
        nix run nixpkgs#age --extra-experimental-features nix-command\
            --extra-experimental-features flakes -- generate-keypair \
            --output /mnt/var/lib/sops-nix/key.txt
    fi

    # Copy Age key for root user
    cp /mnt/var/lib/sops-nix/key.txt /mnt/root/.config/sops/age/keys.txt
    chmod 400 /mnt/root/.config/sops/age/keys.txt

    # Get public key for user
    AGE_PUBKEY=$(nix run nixpkgs#age --extra-experimental-features nix-command -- keygen --output /dev/null --public-key < /mnt/var/lib/sops-nix/key.txt)

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
EOF

    if [[ "$WAN_TYPE" == "pppoe" ]]; then
        cat >> /mnt/etc/nixos/secrets/secrets.yaml << EOF
pppoe-username: "$PPPOE_USER"
pppoe-password: "$PPPOE_PASS"
EOF
    else
        cat >> /mnt/etc/nixos/secrets/secrets.yaml << EOF
# PPPoE credentials (only needed if using PPPoE WAN)
# pppoe-username: "your-isp-username"
# pppoe-password: "your-isp-password"
EOF
    fi

    cat >> /mnt/etc/nixos/secrets/secrets.yaml << EOF
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
