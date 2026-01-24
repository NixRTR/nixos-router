#!/usr/bin/env bash

# Setup GitHub authentication for Nix flake updates
# This helps avoid GitHub API rate limiting

set -euo pipefail

NIX_CONF_DIR="/etc/nix"
NIX_CONF_FILE="${NIX_CONF_DIR}/nix.conf"

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
Setup GitHub authentication for Nix flake updates

Usage: $0 [OPTIONS]

Options:
  -h, --help          Show this help message
  -t, --token TOKEN   GitHub Personal Access Token (will prompt if not provided)
  -c, --check         Check current authentication status
  -r, --remove        Remove GitHub token from nix.conf

Examples:
  $0                  # Interactive setup (will prompt for token)
  $0 -t ghp_xxxxx     # Use provided token
  $0 -c               # Check if authentication is configured
  $0 -r               # Remove authentication

To create a GitHub Personal Access Token:
1. Go to https://github.com/settings/tokens
2. Click "Generate new token" -> "Generate new token (classic)"
3. Give it a name (e.g., "NixOS Router Flake Updates")
4. Select scopes: "public_repo" (or "repo" for private repos)
5. Click "Generate token"
6. Copy the token (starts with ghp_)

EOF
}

check_auth() {
    log_info "Checking GitHub authentication status..."
    
    if [ ! -f "$NIX_CONF_FILE" ]; then
        log_warning "nix.conf not found at $NIX_CONF_FILE"
        return 1
    fi
    
    if grep -q "access-tokens = github.com=" "$NIX_CONF_FILE" 2>/dev/null; then
        log_success "GitHub authentication is configured"
        # Don't show the actual token, just confirm it exists
        if grep -q "access-tokens = github.com=ghp_" "$NIX_CONF_FILE" 2>/dev/null; then
            log_info "Token format appears valid (starts with ghp_)"
        fi
        return 0
    else
        log_warning "GitHub authentication is not configured"
        return 1
    fi
}

setup_auth() {
    local token="${1:-}"
    
    if [ -z "$token" ]; then
        echo ""
        log_info "GitHub Personal Access Token required"
        echo "To create a token:"
        echo "  1. Visit: https://github.com/settings/tokens"
        echo "  2. Generate new token (classic)"
        echo "  3. Select scope: public_repo (or repo for private)"
        echo "  4. Copy the token (starts with ghp_)"
        echo ""
        read -sp "Enter your GitHub token: " token
        echo ""
        
        if [ -z "$token" ]; then
            log_error "Token cannot be empty"
            exit 1
        fi
    fi
    
    # Validate token format
    if [[ ! "$token" =~ ^ghp_[A-Za-z0-9]{36,}$ ]] && [[ ! "$token" =~ ^github_pat_[A-Za-z0-9_]{82,}$ ]]; then
        log_warning "Token format doesn't match expected pattern (ghp_... or github_pat_...)"
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_error "Aborted"
            exit 1
        fi
    fi
    
    # Ensure nix.conf directory exists
    if [ ! -d "$NIX_CONF_DIR" ]; then
        log_info "Creating $NIX_CONF_DIR"
        mkdir -p "$NIX_CONF_DIR"
    fi
    
    # Backup existing nix.conf if it exists
    if [ -f "$NIX_CONF_FILE" ]; then
        log_info "Backing up existing nix.conf"
        cp "$NIX_CONF_FILE" "${NIX_CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Remove existing GitHub token line if present
    if [ -f "$NIX_CONF_FILE" ]; then
        sed -i '/access-tokens = github.com=/d' "$NIX_CONF_FILE" 2>/dev/null || true
    fi
    
    # Add GitHub token to nix.conf
    log_info "Adding GitHub token to nix.conf"
    
    # Check if file exists and has content
    if [ -f "$NIX_CONF_FILE" ] && [ -s "$NIX_CONF_FILE" ]; then
        # File exists and has content, append
        # Check if file ends with newline
        if [ "$(tail -c 1 "$NIX_CONF_FILE" 2>/dev/null | wc -l)" -eq 0 ]; then
            echo "" >> "$NIX_CONF_FILE"
        fi
        echo "access-tokens = github.com=$token" >> "$NIX_CONF_FILE"
    else
        # Create new file
        echo "access-tokens = github.com=$token" > "$NIX_CONF_FILE"
    fi
    
    # Set proper permissions
    chmod 644 "$NIX_CONF_FILE"
    
    log_success "GitHub authentication configured successfully"
    log_info "Token added to: $NIX_CONF_FILE"
    log_info "You may need to restart the Nix daemon for changes to take effect"
    echo ""
    log_info "To restart Nix daemon, run: sudo systemctl restart nix-daemon"
}

remove_auth() {
    if [ ! -f "$NIX_CONF_FILE" ]; then
        log_warning "nix.conf not found at $NIX_CONF_FILE"
        return 1
    fi
    
    if ! grep -q "access-tokens = github.com=" "$NIX_CONF_FILE" 2>/dev/null; then
        log_warning "No GitHub token found in nix.conf"
        return 1
    fi
    
    log_info "Removing GitHub token from nix.conf"
    sed -i '/access-tokens = github.com=/d' "$NIX_CONF_FILE"
    log_success "GitHub token removed"
    log_info "You may need to restart the Nix daemon for changes to take effect"
}

# Parse arguments
ACTION="setup"
TOKEN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
        -c|--check)
            ACTION="check"
            shift
            ;;
        -r|--remove)
            ACTION="remove"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Execute action
case $ACTION in
    check)
        check_auth
        exit $?
        ;;
    remove)
        remove_auth
        exit $?
        ;;
    setup)
        setup_auth "$TOKEN"
        log_info "Testing authentication..."
        if check_auth; then
            log_success "Setup complete!"
        fi
        ;;
esac
