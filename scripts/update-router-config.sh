#!/usr/bin/env bash

# Interactive helper to update router-config.nix with menu-driven interface
# Supports all configuration sections

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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Utility functions for extracting values
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

# Backup function
backup_config() {
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup="${CONFIG_PATH}.bak-${timestamp}"
    cp "$CONFIG_PATH" "$backup"
    echo "$backup"
}

# Menu functions
edit_system_settings() {
    echo
    echo "=== System Settings ==="
    
    current_hostname=$(extract_simple 'hostname' 'nixos-router')
    current_domain=$(extract_simple 'domain' 'example.com')
    current_timezone=$(extract_simple 'timezone' 'America/Anchorage')
    current_username=$(extract_simple 'username' 'routeradmin')
    
    read -p "Hostname [$current_hostname]: " hostname_input
    hostname="${hostname_input:-$current_hostname}"
    
    read -p "Domain [$current_domain]: " domain_input
    domain="${domain_input:-$current_domain}"
    
    read -p "Timezone [$current_timezone]: " timezone_input
    timezone="${timezone_input:-$current_timezone}"
    
    read -p "Username [$current_username]: " username_input
    username="${username_input:-$current_username}"
    
    # Nameservers
    current_nameservers=$(grep -A1 "^[[:space:]]*nameservers[[:space:]]*=" "$CONFIG_PATH" | grep -E '"[^"]+"' | sed 's/.*"\([^"]*\)".*/\1/' | tr '\n' ' ' | xargs)
    if [[ -z "$current_nameservers" ]]; then
        current_nameservers="1.1.1.1 9.9.9.9"
    fi
    read -p "Nameservers (space-separated) [$current_nameservers]: " nameservers_input
    nameservers="${nameservers_input:-$current_nameservers}"
    
    # Store for later use
    SYSTEM_HOSTNAME="$hostname"
    SYSTEM_DOMAIN="$domain"
    SYSTEM_TIMEZONE="$timezone"
    SYSTEM_USERNAME="$username"
    SYSTEM_NAMESERVERS="$nameservers"
    
    log_success "System settings updated"
}

edit_wan_settings() {
    echo
    echo "=== WAN Configuration ==="
    
    current_wan_type=$(extract_block_value 'wan' 'type' 'dhcp')
    current_wan_iface=$(extract_block_value 'wan' 'interface' 'eno1')
    
    echo "WAN connection types:"
    echo "  1) DHCP"
    echo "  2) PPPoE"
    default_choice=$( [[ $current_wan_type == "pppoe" ]] && echo 2 || echo 1 )
    read -p "Select WAN type (1/2) [$default_choice]: " wan_type_choice
    case ${wan_type_choice:-$default_choice} in
        1) wan_type="dhcp" ;;
        2) wan_type="pppoe" ;;
        *) wan_type="dhcp" ;;
    esac
    
    read -p "WAN interface [$current_wan_iface]: " wan_iface_input
    wan_interface="${wan_iface_input:-$current_wan_iface}"
    
    WAN_TYPE="$wan_type"
    WAN_INTERFACE="$wan_interface"
    
    log_success "WAN settings updated"
}

edit_cake_settings() {
    echo
    echo "=== CAKE Traffic Shaping Configuration ==="
    echo "CAKE (Common Applications Kept Enhanced) reduces bufferbloat and improves latency"
    
    current_cake_enable=$(extract_block_value 'wan.cake' 'enable' 'false')
    current_cake_aggressiveness=$(extract_block_value 'wan.cake' 'aggressiveness' 'auto')
    current_cake_upload_bw=$(extract_block_value 'wan.cake' 'uploadBandwidth' '')
    current_cake_download_bw=$(extract_block_value 'wan.cake' 'downloadBandwidth' '')
    
    read -p "Enable CAKE traffic shaping? (y/N) [$( [[ $current_cake_enable == "true" ]] && echo Y || echo N )]: " cake_enable_input
    cake_enable=$( [[ ${cake_enable_input:-$( [[ $current_cake_enable == "true" ]] && echo y || echo n )} =~ ^[Yy]$ ]] && echo "true" || echo "false" )
    
    if [[ "$cake_enable" == "true" ]]; then
        echo
        echo "CAKE aggressiveness levels:"
        echo "  1) auto - Monitors bandwidth and adjusts automatically (Recommended)"
        echo "  2) conservative - Minimal shaping, best for high-speed links"
        echo "  3) moderate - Balanced latency/throughput"
        echo "  4) aggressive - Maximum latency reduction, best for slower links"
        
        default_aggressive=1
        case "$current_cake_aggressiveness" in
            "auto") default_aggressive=1 ;;
            "conservative") default_aggressive=2 ;;
            "moderate") default_aggressive=3 ;;
            "aggressive") default_aggressive=4 ;;
        esac
        
        read -p "Select aggressiveness level (1-4) [$default_aggressive]: " cake_aggressive_choice
        case ${cake_aggressive_choice:-$default_aggressive} in
            1) cake_aggressiveness="auto" ;;
            2) cake_aggressiveness="conservative" ;;
            3) cake_aggressiveness="moderate" ;;
            4) cake_aggressiveness="aggressive" ;;
            *) cake_aggressiveness="auto" ;;
        esac
        
        echo
        echo "Bandwidth Configuration (optional):"
        echo "Set explicit bandwidth limits to improve CAKE performance."
        echo "Recommend setting to ~95% of your actual speeds to account for overhead."
        echo "Leave blank to use automatic bandwidth detection (autorate-ingress)."
        echo
        
        read -p "Upload bandwidth (e.g., 190Mbit for 200Mbit connection) [$current_cake_upload_bw]: " cake_upload_bw_input
        cake_upload_bw="${cake_upload_bw_input:-$current_cake_upload_bw}"
        
        read -p "Download bandwidth (e.g., 475Mbit for 500Mbit connection) [$current_cake_download_bw]: " cake_download_bw_input
        cake_download_bw="${cake_download_bw_input:-$current_cake_download_bw}"
        
        # Clear if empty
        if [[ -z "$cake_upload_bw" ]]; then
            cake_upload_bw=""
        fi
        if [[ -z "$cake_download_bw" ]]; then
            cake_download_bw=""
        fi
    else
        cake_aggressiveness="$current_cake_aggressiveness"
        cake_upload_bw=""
        cake_download_bw=""
    fi
    
    CAKE_ENABLE="$cake_enable"
    CAKE_AGGRESSIVENESS="$cake_aggressiveness"
    CAKE_UPLOAD_BW="$cake_upload_bw"
    CAKE_DOWNLOAD_BW="$cake_download_bw"
    
    log_success "CAKE settings updated"
}

edit_lan_bridges() {
    echo
    echo "=== LAN Bridge Configuration ==="
    log_warning "Bridge editing is complex. Please edit router-config.nix manually for bridge changes."
    log_info "Current bridges can be found in the 'lan.bridges' section"
    read -p "Press Enter to continue..."
}

edit_network_config() {
    echo
    echo "=== Network Configuration ==="
    echo "Which network would you like to configure?"
    echo "  1) HOMELAB (br0)"
    echo "  2) LAN (br1)"
    read -p "Select (1/2): " network_choice
    
    case ${network_choice:-1} in
        1) network_name="homelab" ;;
        2) network_name="lan" ;;
        *) network_name="homelab" ;;
    esac
    
    echo
    echo "=== ${network_name^^} Network Configuration ==="
    
    current_ip=$(extract_block_value "$network_name" 'ipAddress' '192.168.2.1')
    current_subnet=$(extract_block_value "$network_name" 'subnet' '192.168.2.0/24')
    
    read -p "IP Address [$current_ip]: " ip_input
    ip_address="${ip_input:-$current_ip}"
    
    read -p "Subnet [$current_subnet]: " subnet_input
    subnet="${subnet_input:-$current_subnet}"
    
    # DHCP settings
    echo
    echo "DHCP Settings:"
    current_dhcp_enable=$(extract_block_value "$network_name.dhcp" 'enable' 'true')
    current_dhcp_start=$(extract_block_value "$network_name.dhcp" 'start' '192.168.2.100')
    current_dhcp_end=$(extract_block_value "$network_name.dhcp" 'end' '192.168.2.200')
    current_dhcp_lease=$(extract_block_value "$network_name.dhcp" 'leaseTime' '1h')
    
    read -p "Enable DHCP? (y/N) [$( [[ $current_dhcp_enable == "true" ]] && echo y || echo N )]: " dhcp_enable_input
    dhcp_enable=$( [[ ${dhcp_enable_input:-$( [[ $current_dhcp_enable == "true" ]] && echo y || echo n )} =~ ^[Yy]$ ]] && echo "true" || echo "false" )
    
    read -p "DHCP start [$current_dhcp_start]: " dhcp_start_input
    dhcp_start="${dhcp_start_input:-$current_dhcp_start}"
    
    read -p "DHCP end [$current_dhcp_end]: " dhcp_end_input
    dhcp_end="${dhcp_end_input:-$current_dhcp_end}"
    
    read -p "DHCP lease time [$current_dhcp_lease]: " dhcp_lease_input
    dhcp_lease="${dhcp_lease_input:-$current_dhcp_lease}"
    
    # Store for later
    eval "${network_name^^}_IP=\"$ip_address\""
    eval "${network_name^^}_SUBNET=\"$subnet\""
    eval "${network_name^^}_DHCP_ENABLE=\"$dhcp_enable\""
    eval "${network_name^^}_DHCP_START=\"$dhcp_start\""
    eval "${network_name^^}_DHCP_END=\"$dhcp_end\""
    eval "${network_name^^}_DHCP_LEASE=\"$dhcp_lease\""
    
    log_success "${network_name^^} network settings updated"
}

edit_port_forwards() {
    echo
    echo "=== Port Forwarding ==="
    log_warning "Port forwarding editing is complex. Please edit router-config.nix manually."
    log_info "Current port forwards can be found in the 'portForwards' array"
    read -p "Press Enter to continue..."
}

edit_dyndns() {
    echo
    echo "=== Dynamic DNS Configuration ==="
    
    current_dyndns_enable=$(extract_block_value 'dyndns' 'enable' 'false')
    current_dyndns_provider=$(extract_block_value 'dyndns' 'provider' 'linode')
    current_dyndns_domain=$(extract_block_value 'dyndns' 'domain' '')
    current_dyndns_subdomain=$(extract_block_value 'dyndns' 'subdomain' '')
    current_dyndns_domainid=$(extract_block_value 'dyndns' 'domainId' '0')
    current_dyndns_recordid=$(extract_block_value 'dyndns' 'recordId' '0')
    current_dyndns_interval=$(extract_block_value 'dyndns' 'checkInterval' '5m')
    
    read -p "Enable Dynamic DNS? (y/N) [$( [[ $current_dyndns_enable == "true" ]] && echo y || echo N )]: " dyndns_enable_input
    dyndns_enable=$( [[ ${dyndns_enable_input:-$( [[ $current_dyndns_enable == "true" ]] && echo y || echo n )} =~ ^[Yy]$ ]] && echo "true" || echo "false" )
    
    if [[ "$dyndns_enable" == "true" ]]; then
        read -p "Provider [$current_dyndns_provider]: " dyndns_provider_input
        dyndns_provider="${dyndns_provider_input:-$current_dyndns_provider}"
        
        read -p "Domain [$current_dyndns_domain]: " dyndns_domain_input
        dyndns_domain="${dyndns_domain_input:-$current_dyndns_domain}"
        
        read -p "Subdomain [$current_dyndns_subdomain]: " dyndns_subdomain_input
        dyndns_subdomain="${dyndns_subdomain_input:-$current_dyndns_subdomain}"
        
        read -p "Domain ID [$current_dyndns_domainid]: " dyndns_domainid_input
        dyndns_domainid="${dyndns_domainid_input:-$current_dyndns_domainid}"
        
        read -p "Record ID [$current_dyndns_recordid]: " dyndns_recordid_input
        dyndns_recordid="${dyndns_recordid_input:-$current_dyndns_recordid}"
        
        read -p "Check interval [$current_dyndns_interval]: " dyndns_interval_input
        dyndns_interval="${dyndns_interval_input:-$current_dyndns_interval}"
    else
        dyndns_provider="$current_dyndns_provider"
        dyndns_domain="$current_dyndns_domain"
        dyndns_subdomain="$current_dyndns_subdomain"
        dyndns_domainid="$current_dyndns_domainid"
        dyndns_recordid="$current_dyndns_recordid"
        dyndns_interval="$current_dyndns_interval"
    fi
    
    DYNDNS_ENABLE="$dyndns_enable"
    DYNDNS_PROVIDER="$dyndns_provider"
    DYNDNS_DOMAIN="$dyndns_domain"
    DYNDNS_SUBDOMAIN="$dyndns_subdomain"
    DYNDNS_DOMAINID="$dyndns_domainid"
    DYNDNS_RECORDID="$dyndns_recordid"
    DYNDNS_INTERVAL="$dyndns_interval"
    
    log_success "Dynamic DNS settings updated"
}

edit_webui() {
    echo
    echo "=== Web UI Configuration ==="
    
    current_webui_enable=$(extract_block_value 'webui' 'enable' 'true')
    current_webui_port=$(extract_block_value 'webui' 'port' '8080')
    current_webui_interval=$(extract_block_value 'webui' 'collectionInterval' '2')
    current_webui_retention=$(extract_block_value 'webui' 'retentionDays' '30')
    
    read -p "Enable Web UI? (Y/n) [$( [[ $current_webui_enable == "true" ]] && echo Y || echo n )]: " webui_enable_input
    webui_enable=$( [[ ${webui_enable_input:-$( [[ $current_webui_enable == "true" ]] && echo y || echo n )} =~ ^[Nn]$ ]] && echo "false" || echo "true" )
    
    read -p "Port [$current_webui_port]: " webui_port_input
    webui_port="${webui_port_input:-$current_webui_port}"
    
    read -p "Collection interval (seconds) [$current_webui_interval]: " webui_interval_input
    webui_interval="${webui_interval_input:-$current_webui_interval}"
    
    read -p "Retention days [$current_webui_retention]: " webui_retention_input
    webui_retention="${webui_retention_input:-$current_webui_retention}"
    
    WEBUI_ENABLE="$webui_enable"
    WEBUI_PORT="$webui_port"
    WEBUI_INTERVAL="$webui_interval"
    WEBUI_RETENTION="$webui_retention"
    
    log_success "Web UI settings updated"
}

# Main menu
show_main_menu() {
    echo
    echo "=========================================="
    echo "  Router Configuration Editor"
    echo "=========================================="
    echo
    echo "1) System Settings (hostname, domain, timezone, nameservers)"
    echo "2) WAN Configuration"
    echo "3) CAKE Traffic Shaping Configuration"
    echo "4) LAN Bridges (view only - edit manually)"
    echo "5) Network Configuration (HOMELAB/LAN DHCP/DNS)"
    echo "6) Port Forwarding (view only - edit manually)"
    echo "7) Dynamic DNS"
    echo "8) Web UI Configuration"
    echo "9) View/Edit Secrets"
    echo "a) Save and Rebuild"
    echo "0) Exit without saving"
    echo
}

# Main loop
main() {
    # Initialize variables (will be set by menu functions)
    SYSTEM_HOSTNAME=""
    SYSTEM_DOMAIN=""
    SYSTEM_TIMEZONE=""
    SYSTEM_USERNAME=""
    SYSTEM_NAMESERVERS=""
    WAN_TYPE=""
    WAN_INTERFACE=""
    CAKE_ENABLE=""
    CAKE_AGGRESSIVENESS=""
    CAKE_UPLOAD_BW=""
    CAKE_DOWNLOAD_BW=""
    HOMELAB_IP=""
    HOMELAB_SUBNET=""
    HOMELAB_DHCP_ENABLE=""
    HOMELAB_DHCP_START=""
    HOMELAB_DHCP_END=""
    HOMELAB_DHCP_LEASE=""
    LAN_IP=""
    LAN_SUBNET=""
    LAN_DHCP_ENABLE=""
    LAN_DHCP_START=""
    LAN_DHCP_END=""
    LAN_DHCP_LEASE=""
    DYNDNS_ENABLE=""
    DYNDNS_PROVIDER=""
    DYNDNS_DOMAIN=""
    DYNDNS_SUBDOMAIN=""
    DYNDNS_DOMAINID=""
    DYNDNS_RECORDID=""
    DYNDNS_INTERVAL=""
    WEBUI_ENABLE=""
    WEBUI_PORT=""
    WEBUI_INTERVAL=""
    WEBUI_RETENTION=""
    
    CHANGES_MADE=false
    
    while true; do
        show_main_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                edit_system_settings
                CHANGES_MADE=true
                ;;
            2)
                edit_wan_settings
                CHANGES_MADE=true
                ;;
            3)
                edit_cake_settings
                CHANGES_MADE=true
                ;;
            4)
                edit_lan_bridges
                ;;
            5)
                edit_network_config
                CHANGES_MADE=true
                ;;
            6)
                edit_port_forwards
                ;;
            7)
                edit_dyndns
                CHANGES_MADE=true
                ;;
            8)
                edit_webui
                CHANGES_MADE=true
                ;;
            9)
                if [[ -f "$SECRETS_PATH" ]]; then
                    echo
                    read -p "View decrypted secrets? [y/N]: " view_secrets
                    if [[ $view_secrets =~ ^[Yy]$ ]]; then
                        nix shell --extra-experimental-features "nix-command flakes" nixpkgs#sops --command sops -d "$SECRETS_PATH"
                    fi
                    echo
                    read -p "Edit secrets with sops? [y/N]: " edit_secrets
                    if [[ $edit_secrets =~ ^[Yy]$ ]]; then
                        nix shell --extra-experimental-features "nix-command flakes" nixpkgs#sops --command sops "$SECRETS_PATH"
                    fi
                else
                    log_warning "Secrets file not found at $SECRETS_PATH"
                fi
                ;;
            a|A|9)
                if [[ "$CHANGES_MADE" == "false" ]]; then
                    log_info "No changes to save"
                    continue
                fi
                
                log_warning "Saving configuration requires manual editing of router-config.nix"
                log_info "The script has collected your changes, but complex structures"
                log_info "like bridges, DNS records, and port forwards must be edited manually."
                log_info "Please review the current values and update router-config.nix accordingly."
                
                # If CAKE settings were changed, add or update the cake section
                if [[ -n "$CAKE_ENABLE" ]]; then
                    log_info "Updating CAKE configuration in router-config.nix..."
                    # This would need actual file editing logic - for now, just note it
                    log_warning "CAKE settings need to be manually updated in router-config.nix:"
                    echo "  cake = {"
                    echo "    enable = $CAKE_ENABLE;"
                    if [[ "$CAKE_ENABLE" == "true" ]]; then
                        echo "    aggressiveness = \"$CAKE_AGGRESSIVENESS\";"
                        if [[ -n "$CAKE_UPLOAD_BW" ]]; then
                            echo "    uploadBandwidth = \"$CAKE_UPLOAD_BW\";"
                        fi
                        if [[ -n "$CAKE_DOWNLOAD_BW" ]]; then
                            echo "    downloadBandwidth = \"$CAKE_DOWNLOAD_BW\";"
                        fi
                    fi
                    echo "  };"
                fi
                
                echo
                read -p "Would you like to rebuild now? [y/N]: " rebuild_now
                if [[ $rebuild_now =~ ^[Yy]$ ]]; then
                    nixos-rebuild switch --flake "${FLAKE_PATH}#router"
                    log_success "System rebuilt successfully"
                fi
                exit 0
                ;;
            0)
                if [[ "$CHANGES_MADE" == "true" ]]; then
                    read -p "You have unsaved changes. Exit anyway? [y/N]: " confirm_exit
                    if [[ ! $confirm_exit =~ ^[Yy]$ ]]; then
                        continue
                    fi
                fi
                log_info "Exiting without saving"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

main "$@"
