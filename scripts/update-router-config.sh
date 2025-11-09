#!/usr/bin/env bash

# Interactive helper to update router-config.nix, optionally edit secrets, and rebuild.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: this script must be run as root" >&2
    exit 1
fi

DEFAULT_CONFIG_PATH="/etc/nixos/router-config.nix"
DEFAULT_SECRETS_PATH="/etc/nixos/secrets/secrets.yaml"
DEFAULT_FLAKE_PATH="/etc/nixos"

CONFIG_PATH="${1:-$DEFAULT_CONFIG_PATH}"
SECRETS_PATH="${2:-$DEFAULT_SECRETS_PATH}"
FLAKE_PATH="${3:-$DEFAULT_FLAKE_PATH}"

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "error: router-config file not found at $CONFIG_PATH" >&2
    echo "Usage: $0 [router-config.nix] [secrets.yaml] [flake-directory]" >&2
    exit 1
fi

strip_value() {
    local value=$1
    value=${value%%;*}
    value=${value//\"/}
    value=${value//,/ }
    value=$(echo "$value" | xargs)
    echo "$value"
}

extract_simple() {
    local key=$1
    local default=$2
    local value
    value=$(grep -E "^[[:space:]]*$key[[:space:]]*=" "$CONFIG_PATH" | head -n1 | cut -d= -f2-)
    value=$(strip_value "${value:-}")
    echo "${value:-$default}"
}

extract_block_value() {
    local block=$1
    local key=$2
    local default=$3
    local value
    value=$(awk -v blk="$block" -v attr="$key" '
        $0 ~ blk" =" {inside=1}
        inside && $0 ~ attr" =" {
            sub(/.*= */, "", $0)
            print $0
            exit
        }
        inside && $0 ~ /^}/ {inside=0}
    ' "$CONFIG_PATH")
    value=$(strip_value "${value:-}")
    echo "${value:-$default}"
}

extract_block_list() {
    local block=$1
    local key=$2
    local default=$3
    local value
    value=$(awk -v blk="$block" -v attr="$key" '
        $0 ~ blk" =" {inside=1}
        inside && $0 ~ attr" =" {
            sub(/.*\[/, "", $0)
            gsub(/\].*/, "", $0)
            print $0
            exit
        }
        inside && $0 ~ /^}/ {inside=0}
    ' "$CONFIG_PATH")
    value=$(strip_value "${value:-}")
    echo "${value:-$default}"
}

echo "Updating router configuration at $CONFIG_PATH"
echo

current_hostname=$(extract_simple 'hostname' 'nixos-router')
current_timezone=$(extract_simple 'timezone' 'America/Anchorage')
current_username=$(extract_simple 'username' 'routeradmin')
current_wan_type=$(extract_block_value 'wan' 'type' 'dhcp')
current_wan_iface=$(extract_block_value 'wan' 'interface' 'eno1')
current_lan_interfaces=$(extract_block_list 'lan' 'interfaces' '')
current_lan_ip=$(extract_block_value 'lan' 'ip' '192.168.4.1')
current_lan_prefix=$(extract_block_value 'lan' 'prefix' '24')
current_dhcp_start=$(extract_block_value 'dhcp' 'start' '192.168.4.100')
current_dhcp_end=$(extract_block_value 'dhcp' 'end' '192.168.4.200')
current_dhcp_lease=$(extract_block_value 'dhcp' 'leaseTime' '24h')

read -p "Hostname [$current_hostname]: " HOSTNAME_INPUT
hostname=${HOSTNAME_INPUT:-$current_hostname}

read -p "Timezone [$current_timezone]: " TIMEZONE_INPUT
timezone=${TIMEZONE_INPUT:-$current_timezone}

echo "WAN connection types:"
echo "  1) DHCP"
echo "  2) PPPoE"
default_choice=$( [[ $current_wan_type == "pppoe" ]] && echo 2 || echo 1 )
read -p "Select WAN type (1/2) [$default_choice]: " WAN_TYPE_CHOICE
case ${WAN_TYPE_CHOICE:-$default_choice} in
    1) wan_type="dhcp" ;;
    2) wan_type="pppoe" ;;
    *) wan_type="dhcp" ;;
esac

read -p "WAN interface [$current_wan_iface]: " WAN_IFACE_INPUT
wan_interface=${WAN_IFACE_INPUT:-$current_wan_iface}

read -p "LAN bridge interfaces (space separated) [$current_lan_interfaces]: " LAN_IFACES_INPUT
lan_interfaces="${LAN_IFACES_INPUT:-$current_lan_interfaces}"

read -p "LAN IP address [$current_lan_ip]: " LAN_IP_INPUT
lan_ip=${LAN_IP_INPUT:-$current_lan_ip}

read -p "LAN subnet prefix length [$current_lan_prefix]: " LAN_PREFIX_INPUT
lan_prefix=${LAN_PREFIX_INPUT:-$current_lan_prefix}

read -p "DHCP range start [$current_dhcp_start]: " DHCP_START_INPUT
dhcp_start=${DHCP_START_INPUT:-$current_dhcp_start}

read -p "DHCP range end [$current_dhcp_end]: " DHCP_END_INPUT
dhcp_end=${DHCP_END_INPUT:-$current_dhcp_end}

read -p "DHCP lease time [$current_dhcp_lease]: " DHCP_LEASE_INPUT
dhcp_lease=${DHCP_LEASE_INPUT:-$current_dhcp_lease}

echo
echo "Summary of changes:"
echo "  Hostname: $hostname"
echo "  Timezone: $timezone"
echo "  WAN type: $wan_type"
echo "  WAN interface: $wan_interface"
echo "  LAN interfaces: $lan_interfaces"
echo "  LAN IP/prefix: $lan_ip/$lan_prefix"
echo "  DHCP range: $dhcp_start - $dhcp_end (lease $dhcp_lease)"
echo

read -p "Apply changes to $CONFIG_PATH? [y/N]: " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

timestamp=$(date +"%Y%m%d-%H%M%S")
backup="${CONFIG_PATH}.bak-${timestamp}"
cp "$CONFIG_PATH" "$backup"
echo "Backup written to $backup"

lan_interfaces_array=()
if [[ -n "$lan_interfaces" ]]; then
    read -ra lan_interfaces_array <<<"$lan_interfaces"
fi
if [[ ${#lan_interfaces_array[@]} -eq 0 ]]; then
    lan_interfaces_nix="[ ]"
else
    lan_interfaces_nix="[ $(printf '"%s" ' "${lan_interfaces_array[@]}") ]"
    lan_interfaces_nix="${lan_interfaces_nix% }"
fi

cat >"$CONFIG_PATH" <<EOF
# Router configuration variables
# This file is generated by scripts/update-router-config.sh

{
  # System settings
  hostname = "$hostname";
  timezone = "$timezone";
  username = "$current_username";

  # WAN configuration
  wan = {
    type = "$wan_type";  # "dhcp" or "pppoe"
    interface = "$wan_interface";
  };

  # LAN configuration
  lan = {
    interfaces = $lan_interfaces_nix;
    ip = "$lan_ip";
    prefix = $lan_prefix;
  };

  # DHCP configuration
  dhcp = {
    start = "$dhcp_start";
    end = "$dhcp_end";
    leaseTime = "$dhcp_lease";
  };
}
EOF

echo
echo "router-config.nix updated."

if command -v sops >/dev/null 2>&1; then
    if [[ -f "$SECRETS_PATH" ]]; then
        echo
        read -p "View decrypted secrets from $(realpath "$SECRETS_PATH")? [y/N]: " VIEW_SECRETS
        if [[ $VIEW_SECRETS =~ ^[Yy]$ ]]; then
            echo
            nix shell --extra-experimental-features "nix-command flakes" nixpkgs#sops --command sops -d "$SECRETS_PATH"
            echo
        fi

        read -p "Edit secrets with sops now? [y/N]: " EDIT_SECRETS
        if [[ $EDIT_SECRETS =~ ^[Yy]$ ]]; then
            nix shell --extra-experimental-features "nix-command flakes" nixpkgs#sops --command sops "$SECRETS_PATH"
        fi
    else
        echo "warning: secrets file not found at $SECRETS_PATH"
    fi
else
    echo "warning: 'sops' command not found; skipping secrets update."
fi

if [[ $wan_type == "pppoe" ]]; then
    echo "Reminder: ensure PPPoE credentials in your SOPS secrets are up to date."
fi

echo
read -p "Run 'nixos-rebuild switch --flake ${FLAKE_PATH}#router' now? [y/N]: " RUN_REBUILD
if [[ $RUN_REBUILD =~ ^[Yy]$ ]]; then
    echo
    nixos-rebuild switch --flake "${FLAKE_PATH}#router"
fi

echo "Done."

