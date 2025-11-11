#!/usr/bin/env bash
# Quick Test Setup - One command to set up everything for testing
# Run this in WSL2 to quickly get a test environment

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

echo "========================================"
echo "  NixOS Router Quick Test Setup"
echo "========================================"
echo

log_info "This script will:"
echo "  1. Install QEMU (if needed)"
echo "  2. Download NixOS ISO (if needed)"
echo "  3. Create a test VM disk"
echo "  4. Show you how to proceed"
echo

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cancelled"
    exit 0
fi

# Check WSL2
log_info "Checking environment..."
if grep -qi microsoft /proc/version; then
    log_success "Running in WSL2"
else
    log_warning "Not running in WSL2 - this may work but is untested"
fi

# Install QEMU
log_info "Checking QEMU..."
if ! command -v qemu-system-x86_64 &> /dev/null; then
    log_info "Installing QEMU..."
    sudo apt-get update
    sudo apt-get install -y qemu-system-x86 qemu-utils wget curl
    log_success "QEMU installed"
else
    log_success "QEMU already installed"
fi

# Make scripts executable
log_info "Making scripts executable..."
chmod +x test-vm-qemu.sh test-client-vm.sh test-router.sh

# Download ISO
FILES_DIR="files"
mkdir -p "$FILES_DIR"
NIXOS_ISO="${FILES_DIR}/nixos-minimal.iso"
NIXOS_ISO_URL="https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso"

if [[ ! -f "$NIXOS_ISO" ]]; then
    log_info "Downloading NixOS ISO (this may take a while)..."
    wget -O "$NIXOS_ISO" "$NIXOS_ISO_URL"
    log_success "ISO downloaded"
else
    log_success "ISO already exists"
fi

# Create disk
VM_DISK="nixos-router-test.qcow2"
if [[ ! -f "$VM_DISK" ]]; then
    log_info "Creating VM disk (20GB)..."
    qemu-img create -f qcow2 "$VM_DISK" 20G
    log_success "Disk created"
else
    log_warning "Disk already exists: $VM_DISK"
fi

# Check for VNC viewer
echo
log_info "Checking for VNC viewer..."
log_warning "You'll need a VNC viewer on Windows to access the VM console"
echo "  Recommended: TightVNC or RealVNC"
echo "  Download from: https://www.tightvnc.com/"
echo

# Done
log_success "Setup complete!"
echo
echo "========================================"
echo "         Next Steps"
echo "========================================"
echo
echo "1. Start the router VM:"
echo "   ./test-vm-qemu.sh"
echo "   Select option 3 (Start VM - installer)"
echo
echo "2. Access the VM console:"
echo "   - VNC: Connect to localhost:5900 from Windows"
echo "   - Or use the serial console in this terminal"
echo
echo "3. Install the router in the VM:"
echo "   curl -fsSL https://beard.click/nixos-router > install.sh"
echo "   chmod +x install.sh"
echo "   sudo ./install.sh"
echo
echo "4. Configure the router:"
echo "   - WAN interface: ens3 (DHCP)"
echo "   - Simple mode: Bridge ens4 ens5 ens6 ens7"
echo "   - OR Advanced mode: HOMELAB (ens4 ens5) + LAN (ens6 ens7)"
echo
echo "5. After installation, reboot and boot from disk:"
echo "   In test menu, select option 4 (Boot from disk)"
echo
echo "6. Test the router:"
echo "   ./test-router.sh"
echo
echo "7. Test with client VMs (optional):"
echo "   ./test-client-vm.sh client1 8001"
echo
echo "Notes:"
echo "  - ISOs are downloaded to: tests/files/"
echo "  - VM disks are created in: tests/"
echo "  - Full documentation: docs/testing.md"
echo "========================================"
echo

log_info "Ready to start testing!"

