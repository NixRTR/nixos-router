#!/usr/bin/env bash

# NixOS Router Update Script
# Fetches the latest configuration from the repository and applies it

set -euo pipefail

REPO_URL="https://github.com/beardedtek/nixos-router.git" # update if using a fork
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

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

check_dependencies() {
    local -a missing=()
    declare -A packages=(
        [git]="git"
        [rsync]="rsync"
        [nixos-rebuild]="nixos-rebuild"
    )

    for cmd in "${!packages[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("nixpkgs#${packages[$cmd]}")
        fi
    done

    if ((${#missing[@]} > 0)); then
        if [[ -n "${NIX_SHELL_ACTIVE:-}" ]]; then
            log_error "Required tools still missing inside nix shell: ${missing[*]}"
            exit 1
        fi

        log_info "Fetching missing tools with nix shell: ${missing[*]}"
        export NIX_SHELL_ACTIVE=1
        exec nix --extra-experimental-features 'nix-command flakes' \
            shell "${missing[@]}" --command "$0" "$@"
    fi
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
    git clone --depth=1 "$REPO_URL" "${temp_dir}/repo" >/dev/null

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

apply_configuration() {
    log_info "Running nixos-rebuild switch with flake ${TARGET_DIR}#router"
    nixos-rebuild switch --flake "${TARGET_DIR}#router"
    log_success "System updated successfully"
}

main() {
    require_root
    check_dependencies "$@"

    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Target directory ${TARGET_DIR} does not exist"
        exit 1
    fi

    backup_existing_config
    sync_repository
    apply_configuration
}

main "$@"

