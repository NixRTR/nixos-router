#!/usr/bin/env bash

# NixOS Router Installation Script
# Automated installation from NixOS installer ISO

set -euo pipefail

# Configuration
REPO_URL="https://github.com/NixRTR/nixos-router.git"  # Update this with your actual repo URL

# Initialize variables
PPPOE_USER=""
PPPOE_PASS=""
USER_PASSWORD=""
MULTI_LAN_MODE=false

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

read -p "Enter domain [example.com]: " DOMAIN_INPUT
DOMAIN="${DOMAIN_INPUT:-example.com}"

read -p "Enter nameservers (space-separated) [1.1.1.1 9.9.9.9]: " NAMESERVERS_INPUT
NAMESERVERS="${NAMESERVERS_INPUT:-1.1.1.1 9.9.9.9}"

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

# CAKE traffic shaping configuration
echo
echo "CAKE Traffic Shaping Configuration:"
echo "CAKE (Common Applications Kept Enhanced) reduces bufferbloat and improves latency"
echo "Options:"
echo "  1) Disabled (no traffic shaping)"
echo "  2) Auto (monitors bandwidth and adjusts automatically) - Recommended"
echo "  3) Conservative (minimal shaping, best for high-speed links)"
echo "  4) Moderate (balanced latency/throughput)"
echo "  5) Aggressive (maximum latency reduction, best for slower links)"
read -p "Enable CAKE traffic shaping? (1-5) [1]: " CAKE_CHOICE
case ${CAKE_CHOICE:-1} in
    1) CAKE_ENABLE="false"; CAKE_AGGRESSIVENESS="auto"; CAKE_UPLOAD_BW=""; CAKE_DOWNLOAD_BW="" ;;
    2) CAKE_ENABLE="true"; CAKE_AGGRESSIVENESS="auto" ;;
    3) CAKE_ENABLE="true"; CAKE_AGGRESSIVENESS="conservative" ;;
    4) CAKE_ENABLE="true"; CAKE_AGGRESSIVENESS="moderate" ;;
    5) CAKE_ENABLE="true"; CAKE_AGGRESSIVENESS="aggressive" ;;
    *) CAKE_ENABLE="false"; CAKE_AGGRESSIVENESS="auto"; CAKE_UPLOAD_BW=""; CAKE_DOWNLOAD_BW="" ;;
esac

# If CAKE is enabled, ask about explicit bandwidth limits
if [[ "$CAKE_ENABLE" == "true" ]]; then
    echo
    echo "Bandwidth Configuration (optional):"
    echo "You can set explicit bandwidth limits to improve CAKE performance."
    echo "If not set, CAKE will automatically detect bandwidth using autorate-ingress."
    echo "Recommend setting to ~95% of your actual speeds to account for overhead."
    echo
    read -p "Set explicit upload bandwidth? (e.g., 190Mbit for 200Mbit connection) [leave blank for auto-detect]: " CAKE_UPLOAD_BW
    read -p "Set explicit download bandwidth? (e.g., 475Mbit for 500Mbit connection) [leave blank for auto-detect]: " CAKE_DOWNLOAD_BW
    
    # Clear if empty
    if [[ -z "$CAKE_UPLOAD_BW" ]]; then
        CAKE_UPLOAD_BW=""
    fi
    if [[ -z "$CAKE_DOWNLOAD_BW" ]]; then
        CAKE_DOWNLOAD_BW=""
    fi
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

# Ask about LAN configuration mode
echo
echo "LAN Configuration Mode:"
echo "1) Simple - Single network (recommended for most users)"
echo "2) Advanced - Multiple isolated networks (HOMELAB + LAN)"
read -p "Enter mode (1 or 2) [1]: " LAN_MODE_CHOICE
case ${LAN_MODE_CHOICE:-1} in
    1) MULTI_LAN_MODE=false ;;
    2) MULTI_LAN_MODE=true ;;
    *) MULTI_LAN_MODE=false ;;
esac

if [[ "$MULTI_LAN_MODE" == "false" ]]; then
    # Simple mode - single network
    read -p "Enter LAN IP address [192.168.1.1]: " LAN_IP_INPUT
    LAN_IP="${LAN_IP_INPUT:-192.168.1.1}"

    read -p "Enter LAN subnet prefix length [24]: " LAN_PREFIX_INPUT
    LAN_PREFIX="${LAN_PREFIX_INPUT:-24}"

    # Calculate network address from IP and prefix
    IFS='.' read -r i1 i2 i3 i4 <<< "$LAN_IP"
    LAN_NETWORK="${i1}.${i2}.${i3}.0"

    read -p "Enter DHCP range start [${i1}.${i2}.${i3}.100]: " DHCP_START_INPUT
    DHCP_START="${DHCP_START_INPUT:-${i1}.${i2}.${i3}.100}"

    read -p "Enter DHCP range end [${i1}.${i2}.${i3}.200]: " DHCP_END_INPUT
    DHCP_END="${DHCP_END_INPUT:-${i1}.${i2}.${i3}.200}"

    read -p "Enter DHCP lease time [24h]: " DHCP_LEASE_INPUT
    DHCP_LEASE="${DHCP_LEASE_INPUT:-24h}"

    echo "Available interfaces for LAN bridge (space-separated):"
    read -p "Enter LAN bridge interfaces [enp4s0 enp5s0 enp6s0 enp7s0]: " LAN_INTERFACES_INPUT
    LAN_INTERFACES="${LAN_INTERFACES_INPUT:-enp4s0 enp5s0 enp6s0 enp7s0}"
else
    # Advanced mode - multiple networks
    echo
    echo "HOMELAB Network (br0):"
    read -p "Enter HOMELAB IP address [192.168.2.1]: " HOMELAB_IP_INPUT
    HOMELAB_IP="${HOMELAB_IP_INPUT:-192.168.2.1}"

    IFS='.' read -r i1 i2 i3 i4 <<< "$HOMELAB_IP"
    HOMELAB_NETWORK="${i1}.${i2}.${i3}.0"

    read -p "Enter HOMELAB DHCP start [${i1}.${i2}.${i3}.100]: " HOMELAB_DHCP_START_INPUT
    HOMELAB_DHCP_START="${HOMELAB_DHCP_START_INPUT:-${i1}.${i2}.${i3}.100}"

    read -p "Enter HOMELAB DHCP end [${i1}.${i2}.${i3}.200]: " HOMELAB_DHCP_END_INPUT
    HOMELAB_DHCP_END="${HOMELAB_DHCP_END_INPUT:-${i1}.${i2}.${i3}.200}"

    read -p "Enter HOMELAB bridge interfaces (space-separated) [enp4s0 enp5s0]: " HOMELAB_INTERFACES_INPUT
    HOMELAB_INTERFACES="${HOMELAB_INTERFACES_INPUT:-enp4s0 enp5s0}"

    echo
    echo "LAN Network (br1):"
    read -p "Enter LAN IP address [192.168.3.1]: " LAN_IP_INPUT
    LAN_IP="${LAN_IP_INPUT:-192.168.3.1}"

    IFS='.' read -r j1 j2 j3 j4 <<< "$LAN_IP"
    LAN_NETWORK="${j1}.${j2}.${j3}.0"

    read -p "Enter LAN DHCP start [${j1}.${j2}.${j3}.100]: " LAN_DHCP_START_INPUT
    LAN_DHCP_START="${LAN_DHCP_START_INPUT:-${j1}.${j2}.${j3}.100}"

    read -p "Enter LAN DHCP end [${j1}.${j2}.${j3}.200]: " LAN_DHCP_END_INPUT
    LAN_DHCP_END="${LAN_DHCP_END_INPUT:-${j1}.${j2}.${j3}.200}"

    read -p "Enter LAN bridge interfaces (space-separated) [enp6s0 enp7s0]: " LAN_INTERFACES_INPUT
    LAN_INTERFACES="${LAN_INTERFACES_INPUT:-enp6s0 enp7s0}"

    read -p "Enter DHCP lease time [24h]: " DHCP_LEASE_INPUT
    DHCP_LEASE="${DHCP_LEASE_INPUT:-24h}"

    LAN_PREFIX=24  # Fixed for multi-LAN mode
fi

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

    # Format root partition with ext4 (force overwrite any existing filesystem)
    mkfs.ext4 -F -L nixos "${DISK}2"

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

        # Ensure fsType is set to ext4 for the root filesystem
        sed -i '0,/fsType = \"ext4\"/s//fsType = \"ext4\"/' /mnt/etc/nixos/hardware-configuration.nix
    fi

    log_success "NixOS configuration generated"
}

# Clone and setup router configuration
setup_router_config() {
    log_info "Setting up router configuration"

    # Clone the router repository (using nix-shell as git isn't in minimal ISO)
    nix-shell -p git --run "git clone $REPO_URL /mnt/etc/nixos/router-config"

    # Copy configuration files
    cp -r /mnt/etc/nixos/router-config/* /mnt/etc/nixos/
    rm -rf /mnt/etc/nixos/router-config  # Remove the cloned repo, keep only contents

    # Generate router configuration file
    log_info "Generating router configuration file"

    # Convert nameservers to Nix array format
    NAMESERVERS_NIX="[ $(echo "$NAMESERVERS" | sed 's/\([^ ]*\)/"\1"/g') ]"

    if [[ "$MULTI_LAN_MODE" == "false" ]]; then
        # Simple mode - single bridge
        # Convert space-separated interfaces to Nix array format
        LAN_INTERFACES_NIX="[ $(echo "$LAN_INTERFACES" | sed 's/\([^ ]*\)/"\1"/g') ]"

        # Create router-config.nix with actual values
        cat > /mnt/etc/nixos/router-config.nix << EOF
# Router configuration variables
# This file is generated by the installation script

{
  # System settings
  hostname = "$HOSTNAME";
  domain = "$DOMAIN";
  timezone = "$TIMEZONE";
  username = "routeradmin";

  nameservers = $NAMESERVERS_NIX;

  # SSH authorized keys for the router admin user
  sshKeys = [
    # Add your SSH public keys here, one per line
    # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
  ];

  # WAN configuration
  wan = {
    type = "$WAN_TYPE";  # "dhcp" or "pppoe"
    interface = "$WAN_INTERFACE";
EOF

    # Add CAKE configuration if enabled
    if [[ "$CAKE_ENABLE" == "true" ]]; then
        cat >> /mnt/etc/nixos/router-config.nix << EOF
    
    # CAKE traffic shaping configuration
    cake = {
      enable = true;
      aggressiveness = "$CAKE_AGGRESSIVENESS";
EOF
        # Add bandwidth settings if provided
        if [[ -n "$CAKE_UPLOAD_BW" ]]; then
            echo "      uploadBandwidth = \"$CAKE_UPLOAD_BW\";" >> /mnt/etc/nixos/router-config.nix
        fi
        if [[ -n "$CAKE_DOWNLOAD_BW" ]]; then
            echo "      downloadBandwidth = \"$CAKE_DOWNLOAD_BW\";" >> /mnt/etc/nixos/router-config.nix
        fi
        echo "    };" >> /mnt/etc/nixos/router-config.nix
    fi

    cat >> /mnt/etc/nixos/router-config.nix << EOF
  };

  # LAN configuration - Single network
  lan = {
    bridges = [
      {
        name = "br0";
        interfaces = $LAN_INTERFACES_NIX;
        ipv4 = {
          address = "$LAN_IP";
          prefixLength = $LAN_PREFIX;
        };
        ipv6.enable = false;
      }
    ];
    isolation = false;  # No isolation with single bridge
  };

  # HOMELAB network configuration
  homelab = {
    # Network settings
    ipAddress = "$LAN_IP";
    subnet = "$LAN_NETWORK/$LAN_PREFIX";

    # DHCP settings
    dhcp = {
      enable = true;
      start = "$DHCP_START";
      end = "$DHCP_END";
      leaseTime = "$DHCP_LEASE";
      dnsServers = [
        "$LAN_IP"
      ];

      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.homelab.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.homelab.local"
      dynamicDomain = "";  # Set to "" to disable dynamic DNS

      reservations = [
        # Example: { hostname = "desktop"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.3.50"; }
        # Example: { hostname = "laptop"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.3.51"; }
      ];
    };

    # DNS settings for this network
    dns = {
      enable = true;  # Set to false to disable DNS server for this network
      # DNS A Records (hostname → IP address)
      a_records = {
        # Add your DNS records here
      };

      # DNS CNAME Records (alias → canonical name)
      cname_records = {
        # Add more aliases as needed:
        # "app.jeandr.net" = { target = "hera.jeandr.net"; comment = "Application"; };
        # "api.jeandr.net" = { target = "hera.jeandr.net"; comment = "API"; };
      };

      # Blocklist configuration
      blocklists = {
        enable = false;  # Master switch - set to false to disable all blocking

        stevenblack = {
          enable = false;
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          description = "Ads and malware blocking (250K+ domains)";
          updateInterval = "24h";
        };

        phishing-army = {
          enable = false;
          url = "https://phishing.army/download/phishing_army_blocklist.txt";
          description = "Phishing and scam protection";
          updateInterval = "12h";
        };
      };
      whitelist = [
      ];
    };
  };

  # Port Forwarding Rules
  portForwards = [
    # Add your port forwarding rules here
    # {
    #   proto = "both";
    #   externalPort = 443;
    #   destination = "192.168.2.33";
    #   destinationPort = 443;
    # }
  ];

  # Dynamic DNS Configuration
  dyndns = {
    enable = false;
    provider = "linode";

    # Domain and record to update
    domain = "";
    subdomain = "";  # Root domain

    # Linode API credentials (stored in sops secrets)
    domainId = 0;
    recordId = 0;

    # Update interval
    checkInterval = "5m";
  };

  # Global DNS configuration
  dns = {
    enable = true;

    # Upstream DNS servers (shared by all networks)
    upstreamServers = [
      "1.1.1.1@853#cloudflare-dns.com"  # Cloudflare DNS over TLS
      "9.9.9.9@853#dns.quad9.net"        # Quad9 DNS over TLS
    ];
  };

  # Web UI Configuration
  webui = {
    # Enable web-based monitoring dashboard
    enable = true;

    # Port for the WebUI (default: 8080)
    port = 8080;

    # Data collection interval in seconds (default: 2)
    # Lower = more frequent updates, higher CPU usage
    # Higher = less frequent updates, lower CPU usage
    collectionInterval = 2;

    # Database settings (PostgreSQL)
    database = {
      host = "localhost";
      port = 5432;
      name = "router_webui";
      user = "router_webui";
    };

    # Historical data retention in days (default: 30)
    # Older data is automatically cleaned up
    retentionDays = 30;
  };

  # Apprise API Configuration
  apprise = {
    # Enable Apprise API notification service
    enable = false;

    # Internal port for apprise-api (default: 8001, separate from webui)
    port = 8001;

    # Maximum attachment size in MB (0 = disabled)
    attachSize = 0;

    # Optional: Attachments directory path
    # attachmentsDir = "/var/lib/apprise/attachments";

    # Notification Services Configuration
    # Configure notification services that apprise-api will use
    # Secrets (passwords, tokens) are stored in secrets/secrets.yaml
    services = {
      # Email configuration
      email = {
        enable = false;
        smtpHost = "smtp.gmail.com";
        smtpPort = 587;
        username = "your-email@gmail.com";
        # Password stored in sops secrets as "apprise-email-password"
        to = "recipient@example.com";
        # Optional: from address (defaults to username)
        # from = "your-email@gmail.com";
      };

      # Home Assistant configuration
      homeAssistant = {
        enable = false;
        host = "homeassistant.local";
        port = 8123;
        # Access token stored in sops secrets as "apprise-homeassistant-token"
        # Optional: use HTTPS
        # useHttps = false;
      };

      # Discord configuration
      discord = {
        enable = false;
        # Webhook ID and token stored in sops secrets:
        # - "apprise-discord-webhook-id"
        # - "apprise-discord-webhook-token"
      };

      # Slack configuration
      slack = {
        enable = false;
        # Tokens stored in sops secrets:
        # - "apprise-slack-token-a"
        # - "apprise-slack-token-b"
        # - "apprise-slack-token-c"
      };

      # Telegram configuration
      telegram = {
        enable = false;
        # Bot token stored in sops secrets as "apprise-telegram-bot-token"
        chatId = "123456789";  # Can be stored in sops if preferred
      };

      # ntfy configuration
      ntfy = {
        enable = false;
        topic = "router-notifications";
        # Optional: custom ntfy server
        # server = "https://ntfy.sh";
        # Optional: authentication
        # Username stored in sops as "apprise-ntfy-username"
        # Password stored in sops as "apprise-ntfy-password"
      };
    };
  };
}
EOF

        log_info "Configuration file generated (Simple Mode):"
        echo "  Hostname: $HOSTNAME"
        echo "  Timezone: $TIMEZONE"
        echo "  WAN: $WAN_INTERFACE ($WAN_TYPE)"
        echo "  LAN (br0): $LAN_IP/$LAN_PREFIX"
        echo "  DHCP: $DHCP_START - $DHCP_END (lease $DHCP_LEASE)"
        echo "  Interfaces: $LAN_INTERFACES"

    else
        # Advanced mode - multiple bridges
        # Convert space-separated interfaces to Nix array format
        HOMELAB_INTERFACES_NIX="[ $(echo "$HOMELAB_INTERFACES" | sed 's/\([^ ]*\)/"\1"/g') ]"
        LAN_INTERFACES_NIX="[ $(echo "$LAN_INTERFACES" | sed 's/\([^ ]*\)/"\1"/g') ]"

        # Create router-config.nix with actual values
        cat > /mnt/etc/nixos/router-config.nix << EOF
# Router configuration variables
# This file is generated by the installation script

{
  # System settings
  hostname = "$HOSTNAME";
  domain = "$DOMAIN";
  timezone = "$TIMEZONE";
  username = "routeradmin";

  nameservers = $NAMESERVERS_NIX;

  # SSH authorized keys for the router admin user
  sshKeys = [
    # Add your SSH public keys here, one per line
    # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
  ];

  # WAN configuration
  wan = {
    type = "$WAN_TYPE";  # "dhcp" or "pppoe"
    interface = "$WAN_INTERFACE";
EOF

    # Add CAKE configuration if enabled (advanced mode)
    if [[ "$CAKE_ENABLE" == "true" ]]; then
        cat >> /mnt/etc/nixos/router-config.nix << EOF
    
    # CAKE traffic shaping configuration
    cake = {
      enable = true;
      aggressiveness = "$CAKE_AGGRESSIVENESS";
EOF
        # Add bandwidth settings if provided
        if [[ -n "$CAKE_UPLOAD_BW" ]]; then
            echo "      uploadBandwidth = \"$CAKE_UPLOAD_BW\";" >> /mnt/etc/nixos/router-config.nix
        fi
        if [[ -n "$CAKE_DOWNLOAD_BW" ]]; then
            echo "      downloadBandwidth = \"$CAKE_DOWNLOAD_BW\";" >> /mnt/etc/nixos/router-config.nix
        fi
        echo "    };" >> /mnt/etc/nixos/router-config.nix
    fi

    cat >> /mnt/etc/nixos/router-config.nix << EOF
  };

  # LAN configuration - Multiple isolated networks
  lan = {
    # Physical port mapping (for reference):
    # enp4s0, enp5s0 = HOMELAB (left two ports on 4-port card)
    # enp6s0, enp7s0 = LAN (right two ports on 4-port card)

    bridges = [
      # HOMELAB network - servers, IoT devices
      {
        name = "br0";
        interfaces = $HOMELAB_INTERFACES_NIX;
        ipv4 = {
          address = "$HOMELAB_IP";
          prefixLength = 24;
        };
        ipv6.enable = false;
      }
      # LAN network - computers, phones, tablets
      {
        name = "br1";
        interfaces = $LAN_INTERFACES_NIX;
        ipv4 = {
          address = "$LAN_IP";
          prefixLength = 24;
        };
        ipv6.enable = false;
      }
    ];

    # Block traffic between HOMELAB and LAN at the router level
    # (Hera and Triton have dual NICs and can bridge as needed)
    isolation = true;

    # Exception: Allow specific LAN devices to access HOMELAB
    # Format: { source = "LAN IP"; sourceBridge = "br1"; destBridge = "br0"; }
    isolationExceptions = [
      # Add your exceptions here, example:
      # {
      #   source = "192.168.3.50";      # Your workstation IP
      #   sourceBridge = "br1";          # From LAN
      #   destBridge = "br0";            # To HOMELAB
      #   description = "Workstation access to HOMELAB";
      # }
    ];
  };

  # HOMELAB network configuration
  homelab = {
    # Network settings
    ipAddress = "$HOMELAB_IP";
    subnet = "$HOMELAB_NETWORK/24";

    # DHCP settings
    dhcp = {
      enable = true;  # Set to false to disable DHCP for this network
      start = "$HOMELAB_DHCP_START";
      end = "$HOMELAB_DHCP_END";
      leaseTime = "$DHCP_LEASE";
      dnsServers = [
        "$HOMELAB_IP"
      ];

      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.homelab.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.homelab.local"
      dynamicDomain = "";  # Set to "" to disable dynamic DNS

      reservations = [
        # Example: { hostname = "desktop"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.3.50"; }
        # Example: { hostname = "laptop"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.3.51"; }
      ];
    };

    # DNS settings for this network
    dns = {
      enable = true;  # Set to false to disable DNS server for this network
      # DNS A Records (hostname → IP address)
      a_records = {
        # Add your DNS records here
      };

      # DNS CNAME Records (alias → canonical name)
      cname_records = {
        # Add more aliases as needed:
        # "app.jeandr.net" = { target = "hera.jeandr.net"; comment = "Application"; };
        # "api.jeandr.net" = { target = "hera.jeandr.net"; comment = "API"; };
      };

      # Blocklist configuration
      blocklists = {
        enable = false;  # Master switch - set to false to disable all blocking

        stevenblack = {
          enable = false;
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          description = "Ads and malware blocking (250K+ domains)";
          updateInterval = "24h";
        };

        phishing-army = {
          enable = false;
          url = "https://phishing.army/download/phishing_army_blocklist.txt";
          description = "Phishing and scam protection";
          updateInterval = "12h";
        };
      };
      whitelist = [
      ];
    };
  };

  # LAN network configuration
  lan = {
    # Network settings
    ipAddress = "$LAN_IP";
    subnet = "$LAN_NETWORK/24";

    # DHCP settings
    dhcp = {
      enable = true;  # Set to false to disable DHCP for this network
      start = "$LAN_DHCP_START";
      end = "$LAN_DHCP_END";
      leaseTime = "$DHCP_LEASE";
      dnsServers = [
        "$LAN_IP"
      ];

      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.lan.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.lan.local"
      dynamicDomain = "";  # Set to "" to disable dynamic DNS

      reservations = [
        # Example: { hostname = "desktop"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.3.50"; }
        # Example: { hostname = "laptop"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.3.51"; }
      ];
    };

    # DNS settings for this network
    dns = {
      enable = true;  # Set to false to disable DNS server for this network
      # DNS A Records (hostname → IP address)
      a_records = {
        # Add LAN-specific devices here:
        # "workstation.jeandr.net" = { ip = "192.168.3.101"; comment = "Main workstation"; };
        # "desktop.jeandr.net" = { ip = "192.168.3.50"; comment = "Desktop computer"; };
      };

      # DNS CNAME Records (alias → canonical name)
      cname_records = {
        # Add more aliases as needed
      };

      # Blocklist configuration (can differ from HOMELAB)
      blocklists = {
        enable = false;  # Master switch

        stevenblack = {
          enable = false;
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          description = "Ads and malware blocking (250K+ domains)";
          updateInterval = "24h";
        };

        phishing-army = {
          enable = false;
          url = "https://phishing.army/download/phishing_army_blocklist.txt";
          description = "Phishing and scam protection";
          updateInterval = "12h";
        };

        # LAN might want more aggressive blocking for family devices:

        adaway = {
          enable = false;
          url = "https://adaway.org/hosts.txt";
          description = "Mobile-focused ad blocking";
          updateInterval = "1w";
        };
      };
      whitelist = [
      ];
    };
  };

  # Port Forwarding Rules
  portForwards = [
    # Add your port forwarding rules here
    # {
    #   proto = "both";
    #   externalPort = 443;
    #   destination = "192.168.2.33";
    #   destinationPort = 443;
    # }
  ];

  # Dynamic DNS Configuration
  dyndns = {
    enable = false;
    provider = "linode";

    # Domain and record to update
    domain = "";
    subdomain = "";  # Root domain

    # Linode API credentials (stored in sops secrets)
    domainId = 0;
    recordId = 0;

    # Update interval
    checkInterval = "5m";
  };

  # Global DNS configuration
  dns = {
    enable = true;

    # Upstream DNS servers (shared by all networks)
    upstreamServers = [
      "1.1.1.1@853#cloudflare-dns.com"  # Cloudflare DNS over TLS
      "9.9.9.9@853#dns.quad9.net"        # Quad9 DNS over TLS
    ];
  };

  # Web UI Configuration
  webui = {
    # Enable web-based monitoring dashboard
    enable = true;

    # Port for the WebUI (default: 8080)
    port = 8080;

    # Data collection interval in seconds (default: 2)
    # Lower = more frequent updates, higher CPU usage
    # Higher = less frequent updates, lower CPU usage
    collectionInterval = 2;

    # Database settings (PostgreSQL)
    database = {
      host = "localhost";
      port = 5432;
      name = "router_webui";
      user = "router_webui";
    };

    # Historical data retention in days (default: 30)
    # Older data is automatically cleaned up
    retentionDays = 30;
  };

  # Apprise API Configuration
  apprise = {
    # Enable Apprise API notification service
    enable = false;

    # Internal port for apprise-api (default: 8001, separate from webui)
    port = 8001;

    # Maximum attachment size in MB (0 = disabled)
    attachSize = 0;

    # Optional: Attachments directory path
    # attachmentsDir = "/var/lib/apprise/attachments";

    # Notification Services Configuration
    # Configure notification services that apprise-api will use
    # Secrets (passwords, tokens) are stored in secrets/secrets.yaml
    services = {
      # Email configuration
      email = {
        enable = false;
        smtpHost = "smtp.gmail.com";
        smtpPort = 587;
        username = "your-email@gmail.com";
        # Password stored in sops secrets as "apprise-email-password"
        to = "recipient@example.com";
        # Optional: from address (defaults to username)
        # from = "your-email@gmail.com";
      };

      # Home Assistant configuration
      homeAssistant = {
        enable = false;
        host = "homeassistant.local";
        port = 8123;
        # Access token stored in sops secrets as "apprise-homeassistant-token"
        # Optional: use HTTPS
        # useHttps = false;
      };

      # Discord configuration
      discord = {
        enable = false;
        # Webhook ID and token stored in sops secrets:
        # - "apprise-discord-webhook-id"
        # - "apprise-discord-webhook-token"
      };

      # Slack configuration
      slack = {
        enable = false;
        # Tokens stored in sops secrets:
        # - "apprise-slack-token-a"
        # - "apprise-slack-token-b"
        # - "apprise-slack-token-c"
      };

      # Telegram configuration
      telegram = {
        enable = false;
        # Bot token stored in sops secrets as "apprise-telegram-bot-token"
        chatId = "123456789";  # Can be stored in sops if preferred
      };

      # ntfy configuration
      ntfy = {
        enable = false;
        topic = "router-notifications";
        # Optional: custom ntfy server
        # server = "https://ntfy.sh";
        # Optional: authentication
        # Username stored in sops as "apprise-ntfy-username"
        # Password stored in sops as "apprise-ntfy-password"
      };
    };
  };
}
EOF

        log_info "Configuration file generated (Advanced Mode):"
        echo "  Hostname: $HOSTNAME"
        echo "  Timezone: $TIMEZONE"
        echo "  WAN: $WAN_INTERFACE ($WAN_TYPE)"
        echo "  HOMELAB (br0): $HOMELAB_IP/24"
        echo "    DHCP: $HOMELAB_DHCP_START - $HOMELAB_DHCP_END"
        echo "    Interfaces: $HOMELAB_INTERFACES"
        echo "  LAN (br1): $LAN_IP/24"
        echo "    DHCP: $LAN_DHCP_START - $LAN_DHCP_END"
        echo "    Interfaces: $LAN_INTERFACES"
        echo "  Isolation: ENABLED"
    fi

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
    log_warning "IMPORTANT: Save your Age public key!"
    echo "Age Public Key: $AGE_PUBKEY"
    echo
    log_info "Installation Summary:"
    if [[ "$MULTI_LAN_MODE" == "false" ]]; then
        echo "  Mode: Simple (Single Network)"
        echo "  Network: $LAN_IP/$LAN_PREFIX (br0)"
    else
        echo "  Mode: Advanced (Multi-Network with Isolation)"
        echo "  HOMELAB: $HOMELAB_IP/24 (br0)"
        echo "  LAN: $LAN_IP/24 (br1)"
    fi
    echo
    log_warning "NEXT STEPS:"
    echo
    echo "1. Unmount filesystems:"
    echo "   umount -R /mnt"
    echo
    echo "2. Remove USB drive and reboot:"
    echo "   reboot"
    echo
    echo "3. After reboot:"
    echo "   - Router will auto-login on console"
    echo "   - SSH from LAN: ssh routeradmin@$LAN_IP"
    echo "   - Access Grafana: http://$LAN_IP:3000 (admin/admin)"
    echo
    if [[ "$MULTI_LAN_MODE" == "true" ]]; then
        echo "4. Configure isolation exceptions (if needed):"
        echo "   - Edit /etc/nixos/router-config.nix"
        echo "   - Add isolationExceptions for devices that need cross-network access"
        echo "   - Run: sudo nixos-rebuild switch --flake /etc/nixos#router"
        echo
    fi
    echo "For documentation, see: /etc/nixos/docs/"
    echo
    log_success "Installation complete! Enjoy your new router!"
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
