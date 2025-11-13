#!/usr/bin/env bash
#
# Build the NixOS Router installation ISO
#
# This script should be run from NixOS (including NixOS WSL)

set -e

# Colors
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

# Check if running on NixOS
if [ ! -f /etc/NIXOS ]; then
    log_warning "This doesn't appear to be NixOS"
    log_info "This script works best on NixOS (including NixOS WSL)"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

log_info "Building NixOS Router installation ISO..."
echo ""
echo "Build directory: $SCRIPT_DIR"
echo ""

# Check if nix flakes are enabled
if ! nix flake --version &>/dev/null; then
    log_error "Nix flakes not available"
    echo ""
    echo "Enable flakes by adding to /etc/nixos/configuration.nix:"
    echo "  nix.settings.experimental-features = [ \"nix-command\" \"flakes\" ];"
    echo ""
    echo "Then run: sudo nixos-rebuild switch"
    exit 1
fi

# Ensure we're in the iso directory
cd "$SCRIPT_DIR"

# Build the ISO
log_info "Starting ISO build (this may take a while)..."
echo ""

if nix build .#nixosConfigurations.iso.config.system.build.isoImage -L; then
    log_success "ISO build completed!"
    echo ""
    
    # Find the ISO file
    ISO_PATH=$(find result/iso -name "*.iso" -type f | head -n 1)
    
    if [ -n "$ISO_PATH" ]; then
        ISO_NAME=$(basename "$ISO_PATH")
        ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
        
        echo "═══════════════════════════════════════════════════════════"
        echo -e "${GREEN}ISO Image Ready!${NC}"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        echo "  File: $ISO_NAME"
        echo "  Size: $ISO_SIZE"
        echo "  Path: $ISO_PATH"
        echo ""
        
        # Check if we're on WSL
        if grep -qi microsoft /proc/version 2>/dev/null; then
            log_info "Running on WSL - copying ISO to Windows accessible location..."
            
            # Get Windows username
            WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
            WIN_DOWNLOADS="/mnt/c/Users/$WIN_USER/Downloads"
            
            if [ -d "$WIN_DOWNLOADS" ]; then
                cp "$ISO_PATH" "$WIN_DOWNLOADS/$ISO_NAME"
                log_success "ISO copied to: $WIN_DOWNLOADS\\$ISO_NAME"
                echo ""
                echo "You can now write this ISO to a USB drive using:"
                echo "  - Rufus (recommended for Windows)"
                echo "  - balenaEtcher"
                echo "  - Win32DiskImager"
            else
                log_warning "Could not find Windows Downloads folder"
                echo "Copy the ISO manually from: $(wslpath -w "$ISO_PATH")"
            fi
        else
            log_info "To write this ISO to a USB drive:"
            echo ""
            echo "  Linux:"
            echo "    sudo dd if=$ISO_PATH of=/dev/sdX bs=4M status=progress"
            echo ""
            echo "  Windows:"
            echo "    Use Rufus or balenaEtcher"
            echo ""
            echo "  macOS:"
            echo "    sudo dd if=$ISO_PATH of=/dev/diskX bs=1m"
        fi
        
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        
    else
        log_error "ISO file not found in result directory"
        exit 1
    fi
else
    log_error "ISO build failed"
    exit 1
fi

