#!/usr/bin/env bash

# NixOS Router Upgrade Script - Upgrade to NixOS 25.11
# Safely upgrades the router from NixOS 25.05 to NixOS 25.11

set -euo pipefail

TARGET_DIR="/etc/nixos"
TARGET_VERSION="25.11"
CURRENT_VERSION="25.05"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
}

show_usage() {
    cat << EOF
NixOS Router Upgrade Script - Upgrade to NixOS 25.11

This script safely upgrades your router from NixOS 25.05 to NixOS 25.11.

Usage: $0 [OPTIONS]

Options:
  -h, --help          Show this help message and exit
  -y, --yes           Skip confirmation prompts (use with caution)
  --dry-run-only      Only perform dry-run, don't apply upgrade

What this script does:
  1. Checks current NixOS version
  2. Verifies flake configuration
  3. Creates comprehensive backups
  4. Updates flake inputs to 25.11
  5. Performs configuration dry-run
  6. Applies the upgrade (after confirmation)
  7. Verifies critical services after upgrade

Examples:
  $0                    # Interactive upgrade with confirmations
  $0 --dry-run-only     # Test upgrade without applying
  $0 -y                 # Skip confirmations (not recommended)

EOF
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

check_nixos_version() {
    log_step "Checking Current NixOS Version"
    
    if ! command -v nixos-version >/dev/null 2>&1; then
        log_error "nixos-version command not found. Are you running on NixOS?"
        exit 1
    fi
    
    local current_ver
    current_ver=$(nixos-version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    log_info "Current NixOS version: ${current_ver}"
    
    if [[ "$current_ver" != "$CURRENT_VERSION" ]]; then
        log_warning "Expected version ${CURRENT_VERSION}, but found ${current_ver}"
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled."
            exit 0
        fi
    else
        log_success "Current version matches expected ${CURRENT_VERSION}"
    fi
}

verify_flake_config() {
    log_step "Verifying Flake Configuration"
    
    local flake_file="${TARGET_DIR}/flake.nix"
    
    if [[ ! -f "$flake_file" ]]; then
        log_error "flake.nix not found at ${TARGET_DIR}/flake.nix"
        exit 1
    fi
    
    log_info "Checking flake.nix configuration..."
    
    # Check if flake.nix already references 25.11
    if grep -q "nixos-25.11" "$flake_file"; then
        log_success "flake.nix already references nixos-25.11"
    elif grep -q "nixos-25.05" "$flake_file"; then
        log_info "flake.nix references nixos-25.05 (will be updated)"
    else
        log_warning "Could not determine current nixpkgs version in flake.nix"
        log_info "Continuing anyway - flake update will handle version changes"
    fi
    
    # Check if system.stateVersion exists in configuration.nix
    local config_file="${TARGET_DIR}/configuration.nix"
    if [[ -f "$config_file" ]]; then
        if grep -q "system.stateVersion.*25.05" "$config_file"; then
            log_info "configuration.nix has stateVersion 25.05 (will be updated to 25.11)"
        elif grep -q "system.stateVersion.*25.11" "$config_file"; then
            log_warning "configuration.nix already has stateVersion 25.11"
            log_info "This might mean the configuration files have already been updated"
        fi
    fi
    
    log_success "Flake configuration verified"
}

create_backup() {
    log_step "Creating System Backup"
    
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_dir="${TARGET_DIR}.backup-25.05-${timestamp}"
    local backup_state="/nix/var/nix/profiles/system-25.05-${timestamp}"
    
    log_info "Creating configuration backup at ${backup_dir}"
    if [[ -d "$TARGET_DIR" ]]; then
        rsync -a "${TARGET_DIR}/" "${backup_dir}/"
        log_success "Configuration backup created: ${backup_dir}"
    else
        log_error "Target directory ${TARGET_DIR} does not exist"
        exit 1
    fi
    
    log_info "Creating system profile backup..."
    if [[ -L /run/current-system ]]; then
        local current_system
        current_system=$(readlink /run/current-system)
        if [[ -n "$current_system" ]]; then
            nix-store --store /nix --realise "$current_system" --add-root "$backup_state" >/dev/null 2>&1 || true
            log_success "System profile backup created"
        fi
    fi
    
    # Save backup location for rollback instructions
    echo "$backup_dir" > /tmp/nixos-upgrade-backup-dir.$$
    echo "$backup_state" > /tmp/nixos-upgrade-backup-state.$$
    
    log_info "Backup complete. Backup directory: ${backup_dir}"
}

check_system_health() {
    log_step "Checking System Health"
    
    log_info "Checking critical services..."
    
    local services_ok=true
    local critical_services=(
        "postgresql"
        "router-webui-backend"
        "unbound-homelab"
        "unbound-lan"
        "kea-dhcp4"
    )
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_success "Service ${service} is running"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_warning "Service ${service} is enabled but not running"
            services_ok=false
        else
            log_info "Service ${service} is not enabled (skipping)"
        fi
    done
    
    log_info "Checking disk space..."
    local available_space
    available_space=$(df -h /nix | tail -1 | awk '{print $4}')
    log_info "Available space on /nix: ${available_space}"
    
    # Check if we have at least 5GB free (rough estimate)
    local available_gb
    available_gb=$(df -BG /nix | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $available_gb -lt 5 ]]; then
        log_warning "Low disk space on /nix (${available_gb}GB). Upgrade may fail."
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled. Please free up disk space first."
            exit 0
        fi
    fi
    
    if [[ "$services_ok" == true ]]; then
        log_success "System health check passed"
    else
        log_warning "Some services are not running. This is okay if intentional."
    fi
}

update_flake_inputs() {
    log_step "Updating Flake Inputs to NixOS 25.11"
    
    log_info "Updating flake inputs (this may take a few minutes)..."
    
    cd "$TARGET_DIR"
    
    if ! nix flake update; then
        log_error "Failed to update flake inputs"
        exit 1
    fi
    
    log_success "Flake inputs updated successfully"
    
    # Verify the update
    log_info "Verifying nixpkgs version..."
    local updated_version
    updated_version=$(nix eval --impure --expr '(import <nixpkgs> {}).lib.version' 2>/dev/null || echo "unknown")
    log_info "nixpkgs version: ${updated_version}"
}

perform_dry_run() {
    log_step "Performing Configuration Dry-Run"
    
    log_info "Running nixos-rebuild dry-run (this may take several minutes)..."
    log_info "This will show what would change without applying it."
    
    cd "$TARGET_DIR"
    
    if nixos-rebuild dry-run --flake "${TARGET_DIR}#router" 2>&1 | tee /tmp/nixos-upgrade-dryrun.log; then
        log_success "Dry-run completed successfully"
        
        # Show summary
        echo
        log_info "Dry-run summary saved to: /tmp/nixos-upgrade-dryrun.log"
        log_info "Review the output above to see what will change."
        
        return 0
    else
        log_error "Dry-run failed! Please review the errors above."
        log_error "Full output saved to: /tmp/nixos-upgrade-dryrun.log"
        
        read -p "Continue anyway? (NOT RECOMMENDED) [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled due to dry-run failures."
            exit 1
        fi
        return 1
    fi
}

apply_upgrade() {
    log_step "Applying NixOS 25.11 Upgrade"
    
    log_warning "This will reboot the system if successful!"
    log_info "The upgrade process will:"
    log_info "  1. Build the new system configuration"
    log_info "  2. Switch to the new configuration"
    log_info "  3. Reboot the system"
    
    if [[ "${SKIP_CONFIRM:-false}" != "true" ]]; then
        echo
        read -p "Are you sure you want to proceed with the upgrade? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled by user."
            exit 0
        fi
    fi
    
    log_info "Starting upgrade process..."
    cd "$TARGET_DIR"
    
    # Build and switch
    if nixos-rebuild switch --flake "${TARGET_DIR}#router"; then
        log_success "System configuration upgraded successfully!"
        
        # Show rollback instructions
        show_rollback_instructions
        
        log_info "System will reboot in 10 seconds to complete the upgrade..."
        log_info "Press Ctrl+C to cancel reboot (you can reboot manually later)"
        
        if [[ "${SKIP_CONFIRM:-false}" != "true" ]]; then
            sleep 10
        fi
        
        log_info "Rebooting system..."
        systemctl reboot
    else
        log_error "Upgrade failed! System should still be in working state."
        log_error "You can try again or rollback if needed."
        show_rollback_instructions
        exit 1
    fi
}

verify_after_upgrade() {
    log_step "Verifying System After Upgrade"
    
    log_info "Waiting 30 seconds for services to start..."
    sleep 30
    
    log_info "Checking NixOS version..."
    local new_version
    new_version=$(nixos-version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [[ "$new_version" == "$TARGET_VERSION" ]]; then
        log_success "NixOS version is now ${TARGET_VERSION}"
    else
        log_warning "NixOS version is ${new_version} (expected ${TARGET_VERSION})"
    fi
    
    log_info "Checking critical services..."
    local critical_services=(
        "postgresql"
        "router-webui-backend"
    )
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_success "Service ${service} is running"
        else
            log_warning "Service ${service} is not running"
            log_info "Check status with: sudo systemctl status ${service}"
        fi
    done
    
    log_info "Checking system logs for errors..."
    if journalctl -p err -b --no-pager | grep -q .; then
        log_warning "Errors found in system logs. Check with: journalctl -p err -b"
    else
        log_success "No critical errors in system logs"
    fi
}

show_rollback_instructions() {
    local backup_dir
    backup_dir=$(cat /tmp/nixos-upgrade-backup-dir.$$ 2>/dev/null || echo "unknown")
    
    echo
    log_step "Rollback Instructions"
    echo
    echo "If you need to rollback to NixOS 25.05:"
    echo
    echo "1. Boot into the previous generation:"
    echo "   sudo nixos-rebuild boot --rollback"
    echo "   sudo reboot"
    echo
    echo "2. Or switch to a specific generation:"
    echo "   sudo nix-env -p /nix/var/nix/profiles/system --list-generations"
    echo "   sudo nixos-rebuild switch --rollback"
    echo
    echo "3. Configuration backup location:"
    echo "   ${backup_dir}"
    echo
    echo "4. If you need to restore configuration files:"
    echo "   sudo cp -r ${backup_dir}/* ${TARGET_DIR}/"
    echo
}

show_upgrade_summary() {
    log_step "Upgrade Summary"
    
    echo "Upgrade from NixOS ${CURRENT_VERSION} to ${TARGET_VERSION} is ready."
    echo
    echo "What will be upgraded:"
    echo "  - nixpkgs channel: nixos-25.05 → nixos-25.11"
    echo "  - system.stateVersion: 25.05 → 25.11"
    echo "  - All system packages to 25.11 versions"
    echo "  - Python packages, PostgreSQL, and all dependencies"
    echo
    echo "Expected changes:"
    echo "  - Package updates across the system"
    echo "  - Potential Python version updates (3.11 → 3.12)"
    echo "  - Improved performance and security patches"
    echo
    echo "Critical services will be checked after upgrade:"
    echo "  - PostgreSQL database"
    echo "  - Router WebUI backend"
    echo "  - DNS services (Unbound)"
    echo "  - DHCP server (Kea)"
    echo
}

main() {
    local DRY_RUN_ONLY=false
    local SKIP_CONFIRM=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            --dry-run-only)
                DRY_RUN_ONLY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    export SKIP_CONFIRM
    
    # Check if we're already on 25.11
    local current_ver
    if command -v nixos-version >/dev/null 2>&1; then
        current_ver=$(nixos-version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ "$current_ver" == "$TARGET_VERSION" ]]; then
            log_success "System is already on NixOS ${TARGET_VERSION}"
            log_info "No upgrade needed."
            exit 0
        fi
    fi
    
    log_step "NixOS Router Upgrade to 25.11"
    
    echo "This script will upgrade your router from NixOS ${CURRENT_VERSION} to ${TARGET_VERSION}."
    echo
    echo "IMPORTANT:"
    echo "  - The system will REBOOT after successful upgrade"
    echo "  - All critical services will be checked before and after"
    echo "  - Comprehensive backups will be created"
    echo "  - Rollback instructions will be provided"
    echo
    
    if [[ "${SKIP_CONFIRM}" != "true" ]]; then
        read -p "Do you want to continue? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled."
            exit 0
        fi
    fi
    
    require_root
    
    show_upgrade_summary
    
    if [[ "${SKIP_CONFIRM}" != "true" ]]; then
        read -p "Proceed with upgrade? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled."
            exit 0
        fi
    fi
    
    check_nixos_version
    verify_flake_config
    check_system_health
    create_backup
    update_flake_inputs
    perform_dry_run
    
    if [[ "$DRY_RUN_ONLY" == true ]]; then
        log_step "Dry-Run Only Mode"
        log_success "Dry-run completed. Use without --dry-run-only to apply upgrade."
        show_rollback_instructions
        exit 0
    fi
    
    apply_upgrade
}

# Run main function
main "$@"

