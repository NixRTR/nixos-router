#!/usr/bin/env bash

# Sync dnsmasq configuration files to WebUI database
# This script imports DNS and DHCP records from dnsmasq config files into the WebUI database

set -euo pipefail

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

show_usage() {
    cat << EOF
Sync dnsmasq configuration files to WebUI database

Usage: $0 [OPTIONS] [NETWORK]

Arguments:
  NETWORK              Network to sync ("homelab" or "lan")
                       If not specified, syncs both networks

Options:
  -h, --help           Show this help message and exit
  -s, --source SOURCE  Source to import from:
                       "dnsmasq" - Read from dnsmasq config files (default)
                       "router-config" - Read from router-config.nix
  -t, --token TOKEN    WebUI API token (JWT)
                       If not provided, will prompt for username/password
  -u, --url URL        WebUI base URL (default: http://localhost:8080)
  --dns-only           Only sync DNS configuration
  --dhcp-only          Only sync DHCP configuration

Examples:
  $0 homelab                    # Sync homelab network from dnsmasq configs
  $0 --source router-config lan  # Sync lan network from router-config.nix
  $0 --dns-only                  # Sync DNS only for both networks
  $0 -t "your-jwt-token"         # Use provided JWT token

EOF
}

# Default values
SOURCE="dnsmasq"
NETWORK=""
TOKEN=""
WEBUI_URL="http://localhost:8080"
DNS_ONLY=false
DHCP_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
        -u|--url)
            WEBUI_URL="$2"
            shift 2
            ;;
        --dns-only)
            DNS_ONLY=true
            shift
            ;;
        --dhcp-only)
            DHCP_ONLY=true
            shift
            ;;
        homelab|lan)
            NETWORK="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate source
if [[ "$SOURCE" != "dnsmasq" && "$SOURCE" != "router-config" ]]; then
    log_error "Invalid source: $SOURCE. Must be 'dnsmasq' or 'router-config'"
    exit 1
fi

# Validate network if provided
if [[ -n "$NETWORK" && "$NETWORK" != "homelab" && "$NETWORK" != "lan" ]]; then
    log_error "Invalid network: $NETWORK. Must be 'homelab' or 'lan'"
    exit 1
fi

# Determine networks to sync
if [[ -z "$NETWORK" ]]; then
    NETWORKS=("homelab" "lan")
else
    NETWORKS=("$NETWORK")
fi

# Function to get JWT token from username/password
get_token() {
    local username password response http_code
    
    if [[ -z "$TOKEN" ]]; then
        # Prompt for credentials
        echo
        read -p "WebUI username: " username
        if [[ -z "$username" ]]; then
            log_error "Username cannot be empty"
            exit 1
        fi
        
        read -sp "WebUI password: " password
        echo
        
        if [[ -z "$password" ]]; then
            log_error "Password cannot be empty"
            exit 1
        fi
        
        log_info "Authenticating with WebUI at ${WEBUI_URL}..."
        
        # Make login request
        response=$(curl -s -w "\n%{http_code}" -X POST "${WEBUI_URL}/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${username}\",\"password\":\"${password}\"}")
        
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [[ "$http_code" != "200" ]]; then
            log_error "Authentication failed (HTTP $http_code)"
            if echo "$body" | grep -q "detail"; then
                error_msg=$(echo "$body" | grep -o '"detail":"[^"]*' | cut -d'"' -f4)
                log_error "Error: ${error_msg:-$body}"
            else
                log_error "Response: $body"
            fi
            exit 1
        fi
        
        # Extract access_token from response
        # Response format: {"access_token":"...","token_type":"bearer","username":"..."}
        # Try using python json parsing first (more reliable)
        if command -v python3 &> /dev/null; then
            TOKEN=$(echo "$body" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)
        fi
        
        # Fallback to grep if python failed or not available
        if [[ -z "$TOKEN" ]]; then
            TOKEN=$(echo "$body" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
        fi
        
        if [[ -z "$TOKEN" ]]; then
            log_error "Failed to extract token from response"
            log_error "Response: $body"
            exit 1
        fi
        
        log_success "Authentication successful"
        log_info "Token obtained (length: ${#TOKEN} characters)"
    else
        log_info "Using provided JWT token"
    fi
}

# Function to sync DNS for a network
sync_dns() {
    local network=$1
    local source=$2
    
    log_info "Syncing DNS configuration for network: $network (source: $source)"
    
    if [[ "$source" == "dnsmasq" ]]; then
        URL="${WEBUI_URL}/api/dns/import-from-config/${network}?source=dnsmasq"
    else
        URL="${WEBUI_URL}/api/dns/import-from-config/${network}?source=router-config"
    fi
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        log_success "DNS sync completed for $network"
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    else
        log_error "DNS sync failed for $network (HTTP $HTTP_CODE)"
        echo "$BODY"
        return 1
    fi
}

# Function to sync DHCP for a network
sync_dhcp() {
    local network=$1
    
    log_info "Syncing DHCP configuration for network: $network"
    
    URL="${WEBUI_URL}/api/dhcp/import-from-config/${network}"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        log_success "DHCP sync completed for $network"
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    else
        log_error "DHCP sync failed for $network (HTTP $HTTP_CODE)"
        echo "$BODY"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting dnsmasq to WebUI sync..."
    log_info "Source: $SOURCE"
    log_info "Networks: ${NETWORKS[*]}"
    
    # Get authentication token
    get_token
    
    # Sync configurations
    for network in "${NETWORKS[@]}"; do
        log_info "Processing network: $network"
        
        if [[ "$DNS_ONLY" == false ]]; then
            if sync_dns "$network" "$SOURCE"; then
                log_success "DNS sync successful for $network"
            else
                log_warning "DNS sync had issues for $network"
            fi
        fi
        
        if [[ "$DHCP_ONLY" == false ]]; then
            if sync_dhcp "$network"; then
                log_success "DHCP sync successful for $network"
            else
                log_warning "DHCP sync had issues for $network"
            fi
        fi
        
        echo
    done
    
    log_success "Sync completed!"
    log_info "You can now view and manage DNS/DHCP records in the WebUI"
}

# Run main function
main
