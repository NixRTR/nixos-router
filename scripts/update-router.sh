#!/usr/bin/env bash

# NixOS Router Update Script
# Fetches the latest configuration from the repository and applies it

set -euo pipefail

REPO_URL="https://github.com/beardedtek/nixos-router.git" # update if using a fork
BRANCH="main"
TARGET_DIR="/etc/nixos"

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
NixOS Router Update Script
Fetches the latest configuration from the repository and applies it

Usage: $0 [OPTIONS]

Options:
  -h, --help          Show this help message and exit
  -r, --repo-url URL  Override the repository URL
                      Default: https://github.com/beardedtek/nixos-router.git
  -b, --branch NAME   Override the git branch to use
                      Default: main

Examples:
  $0                          # Update using default repository and main branch
  $0 -r https://github.com/user/fork.git  # Use a different repository
  $0 -b develop              # Use develop branch from default repository
  $0 -r https://github.com/user/fork.git -b custom  # Use custom repo and branch

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--repo-url)
                if [[ -z "${2:-}" ]]; then
                    log_error "--repo-url requires a URL argument"
                    show_usage
                    exit 1
                fi
                REPO_URL="$2"
                shift 2
                ;;
            -b|--branch)
                if [[ -z "${2:-}" ]]; then
                    log_error "--branch requires a branch name argument"
                    show_usage
                    exit 1
                fi
                BRANCH="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

ensure_git() {
    if command -v git >/dev/null 2>&1; then
        return
    fi

    if [[ -n "${NIX_SHELL_ACTIVE:-}" ]]; then
        log_error "git is still unavailable inside nix shell"
        exit 1
    fi

    log_info "git not found; dropping into nix shell (nixpkgs#git)"
    export NIX_SHELL_ACTIVE=1
    # REPO_URL and BRANCH are already exported in main(), they'll be preserved
    exec nix --extra-experimental-features 'nix-command flakes' \
        shell nixpkgs#git --command "$0" "$@"
}

backup_existing_config() {
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_dir="${TARGET_DIR}.backup-${timestamp}"

    log_info "Creating backup at ${backup_dir}"
    rsync -a "${TARGET_DIR}/" "${backup_dir}/"
    log_success "Backup created: ${backup_dir}"
}

sync_repository() {
    local temp_dir
    temp_dir=$(mktemp -d)

    log_info "Cloning repository into ${temp_dir}"
    log_info "Repository: ${REPO_URL}"
    log_info "Branch: ${BRANCH}"
    git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "${temp_dir}/repo" >/dev/null

    log_info "Syncing repository into ${TARGET_DIR}"
    rsync -a \
        --delete \
        --exclude "hardware-configuration.nix" \
        --exclude "router-config.nix" \
        --exclude "secrets/secrets.yaml" \
        "${temp_dir}/repo/" "${TARGET_DIR}/"

    rm -rf "$temp_dir"
    log_success "Repository sync complete"
}

check_config_structure() {
    local config_file="${TARGET_DIR}/router-config.nix"
    
    if [[ ! -f "$config_file" ]]; then
        log_warning "router-config.nix not found, skipping structure check"
        return
    fi
    
    log_info "Checking router-config.nix structure..."
    
    local missing_sections=()
    
    # Check for required top-level sections
    if ! grep -q "^[[:space:]]*domain[[:space:]]*=" "$config_file"; then
        missing_sections+=("domain")
    fi
    
    if ! grep -q "^[[:space:]]*nameservers[[:space:]]*=" "$config_file"; then
        missing_sections+=("nameservers")
    fi
    
    if ! grep -q "^[[:space:]]*homelab[[:space:]]*=" "$config_file"; then
        missing_sections+=("homelab")
    fi
    
    # Check for second 'lan' section (network config, not bridge config)
    local lan_network_count
    lan_network_count=$(grep -c "^[[:space:]]*lan[[:space:]]*=" "$config_file" || echo "0")
    if [[ $lan_network_count -lt 2 ]]; then
        missing_sections+=("lan (network config)")
    fi
    
    if ! grep -q "^[[:space:]]*portForwards[[:space:]]*=" "$config_file"; then
        missing_sections+=("portForwards")
    fi
    
    if ! grep -q "^[[:space:]]*dyndns[[:space:]]*=" "$config_file"; then
        missing_sections+=("dyndns")
    fi
    
    if ! grep -q "^[[:space:]]*dns[[:space:]]*=" "$config_file"; then
        missing_sections+=("dns (global)")
    fi
    
    if ! grep -q "^[[:space:]]*webui[[:space:]]*=" "$config_file"; then
        missing_sections+=("webui")
    fi
    
    if [[ ${#missing_sections[@]} -eq 0 ]]; then
        log_success "router-config.nix structure is complete"
        
        # Optional: Ask about CAKE if not present
        if ! grep -q "cake = {" "$config_file"; then
            echo
            read -p "CAKE traffic shaping is not configured. Would you like to add it? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                missing_sections+=("cake")
            fi
        fi
    fi
    
    log_warning "Missing sections in router-config.nix: ${missing_sections[*]}"
    echo
    read -p "Would you like to add the missing sections now? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping structure update. You can add missing sections manually."
        return
    fi
    
    # Backup before modifying
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup="${config_file}.bak-${timestamp}"
    cp "$config_file" "$backup"
    log_info "Backup created: $backup"
    
    # Add missing sections interactively
    for section in "${missing_sections[@]}"; do
        case "$section" in
            "domain")
                read -p "Enter domain [example.com]: " domain_input
                domain="${domain_input:-example.com}"
                # Add domain after hostname
                sed -i "/^[[:space:]]*hostname[[:space:]]*=/a\  domain = \"$domain\";" "$config_file"
                ;;
            "nameservers")
                read -p "Enter nameservers (space-separated) [1.1.1.1 9.9.9.9]: " nameservers_input
                nameservers="${nameservers_input:-1.1.1.1 9.9.9.9}"
                nameservers_nix="[ $(echo "$nameservers" | sed 's/\([^ ]*\)/"\1"/g') ]"
                # Add nameservers after domain
                sed -i "/^[[:space:]]*domain[[:space:]]*=/a\  nameservers = $nameservers_nix;" "$config_file"
                ;;
            "homelab")
                log_info "Adding homelab network configuration section..."
                # This is complex, so we'll add a minimal template
                # Find where to insert (after lan bridges section closes)
                # For now, just warn the user
                log_warning "homelab section is complex - please add it manually. See docs/documentation.md for structure."
                ;;
            "lan (network config)")
                log_warning "LAN network configuration section is complex - please add it manually. See docs/documentation.md for structure."
                ;;
            "portForwards")
                # Add empty portForwards array before closing brace
                sed -i '$ i\  portForwards = [];' "$config_file"
                ;;
            "dyndns")
                # Add minimal dyndns config
                sed -i '$ i\  dyndns = { enable = false; provider = "linode"; domain = ""; subdomain = ""; domainId = 0; recordId = 0; checkInterval = "5m"; };' "$config_file"
                ;;
            "dns (global)")
                # Add minimal global DNS config
                sed -i '$ i\  dns = { enable = true; upstreamServers = [ "1.1.1.1@853#cloudflare-dns.com" "9.9.9.9@853#dns.quad9.net" ]; };' "$config_file"
                ;;
            "webui")
                # Add minimal webui config
                sed -i '$ i\  webui = { enable = true; port = 8080; collectionInterval = 2; database = { host = "localhost"; port = 5432; name = "router_webui"; user = "router_webui"; }; retentionDays = 30; };' "$config_file"
                ;;
            "cake")
                log_info "Adding CAKE traffic shaping configuration..."
                echo "CAKE aggressiveness levels:"
                echo "  1) auto (monitors bandwidth and adjusts automatically) - Recommended"
                echo "  2) conservative (minimal shaping, best for high-speed links)"
                echo "  3) moderate (balanced latency/throughput)"
                echo "  4) aggressive (maximum latency reduction, best for slower links)"
                read -p "Select aggressiveness level (1-4) [1]: " cake_choice
                case ${cake_choice:-1} in
                    1) cake_aggressiveness="auto" ;;
                    2) cake_aggressiveness="conservative" ;;
                    3) cake_aggressiveness="moderate" ;;
                    4) cake_aggressiveness="aggressive" ;;
                    *) cake_aggressiveness="auto" ;;
                esac
                # Add cake section after wan interface line
                sed -i "/^[[:space:]]*interface[[:space:]]*=/a\\
    \\
    # CAKE traffic shaping configuration\\
    cake = {\\
      enable = true;\\
      aggressiveness = \"$cake_aggressiveness\";\\
    };" "$config_file"
                ;;
        esac
    done
    
    log_success "Structure check complete. Please review $config_file and adjust as needed."
}

apply_configuration() {
    log_info "Running nixos-rebuild switch with flake ${TARGET_DIR}#router"
    nixos-rebuild switch --flake "${TARGET_DIR}#router"
    log_success "System updated successfully"
}

main() {
    # Parse command-line arguments
    parse_arguments "$@"
    
    # Export variables so they're preserved if ensure_git re-executes the script
    export REPO_URL BRANCH
    
    require_root
    ensure_git "$@"

    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Target directory ${TARGET_DIR} does not exist"
        exit 1
    fi

    backup_existing_config
    sync_repository
    check_config_structure
    apply_configuration
}

main "$@"

