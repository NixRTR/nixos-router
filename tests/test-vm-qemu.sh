#!/usr/bin/env bash
# QEMU VM Testing Script for NixOS Router
# Run this in WSL2 to test the router in a VM

set -euo pipefail

# Configuration
VM_NAME="nixos-router-test"
VM_DISK_SIZE="20G"
VM_MEMORY="4G"
VM_CPUS="4"
NIXOS_ISO_URL="https://channels.nixos.org/nixos-23.11/latest-nixos-minimal-x86_64-linux.iso"
FILES_DIR="files"
NIXOS_ISO="${FILES_DIR}/nixos-minimal.iso"
VM_DISK="${VM_NAME}.qcow2"

# Create files directory if it doesn't exist
mkdir -p "$FILES_DIR"

# Check for KVM acceleration (set early for use throughout script)
if [[ -e /dev/kvm ]]; then
    KVM_ARGS="-enable-kvm"
else
    KVM_ARGS=""
fi

# Colors
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

# Check if running in WSL2
check_wsl() {
    if ! grep -qi microsoft /proc/version; then
        log_warning "This script is designed for WSL2 but can work on native Linux"
    else
        log_info "Running in WSL2"
    fi
}

# Install dependencies
install_deps() {
    log_info "Installing dependencies..."
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        log_info "Installing QEMU..."
        sudo apt-get update
        sudo apt-get install -y qemu-system-x86 qemu-utils wget
    else
        log_success "QEMU already installed"
    fi
    
    # Report KVM status (already checked at script start)
    if [[ -n "$KVM_ARGS" ]]; then
        log_success "KVM acceleration available"
    else
        log_warning "KVM not available - VM will be slower (expected in WSL2)"
    fi
}

# Download NixOS ISO
download_iso() {
    if [[ ! -f "$NIXOS_ISO" ]]; then
        log_info "Downloading NixOS ISO..."
        wget -O "$NIXOS_ISO" "$NIXOS_ISO_URL"
        log_success "ISO downloaded"
    else
        log_info "ISO already exists: $NIXOS_ISO"
    fi
}

# Create VM disk
create_disk() {
    if [[ ! -f "$VM_DISK" ]]; then
        log_info "Creating VM disk ($VM_DISK_SIZE)..."
        qemu-img create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"
        log_success "Disk created: $VM_DISK"
    else
        log_info "Disk already exists: $VM_DISK"
        read -p "Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm "$VM_DISK"
            qemu-img create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"
            log_success "Disk recreated"
        fi
    fi
}

# Start VM with multiple network adapters
start_vm() {
    log_info "Starting VM with 5 network adapters..."
    log_info "Configuration:"
    echo "  - Memory: $VM_MEMORY"
    echo "  - CPUs: $VM_CPUS"
    echo "  - WAN: tap0 (NAT)"
    echo "  - LAN: tap1, tap2, tap3, tap4 (isolated)"
    echo
    log_warning "VM will start. To access:"
    echo "  - VNC: localhost:5900"
    echo "  - Serial console: This terminal"
    echo "  - Press Ctrl+A then X to exit QEMU"
    echo
    read -p "Press Enter to start VM..."
    
    # Note: Using user-mode networking (no root required)
    # WAN gets internet via user-mode networking
    # LAN ports are on separate VLANs for testing
    
    qemu-system-x86_64 \
        $KVM_ARGS \
        -m "$VM_MEMORY" \
        -smp "$VM_CPUS" \
        -boot d \
        -cdrom "$NIXOS_ISO" \
        -drive file="$VM_DISK",format=qcow2,if=virtio \
        -vnc :0 \
        -serial mon:stdio \
        -device virtio-net-pci,netdev=wan,mac=52:54:00:12:34:00 \
        -netdev user,id=wan,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000 \
        -device virtio-net-pci,netdev=lan1,mac=52:54:00:12:34:01 \
        -netdev socket,id=lan1,listen=:8001 \
        -device virtio-net-pci,netdev=lan2,mac=52:54:00:12:34:02 \
        -netdev socket,id=lan2,listen=:8002 \
        -device virtio-net-pci,netdev=lan3,mac=52:54:00:12:34:03 \
        -netdev socket,id=lan3,listen=:8003 \
        -device virtio-net-pci,netdev=lan4,mac=52:54:00:12:34:04 \
        -netdev socket,id=lan4,listen=:8004
}

# Main menu
show_menu() {
    echo
    echo "=================================="
    echo "  NixOS Router VM Testing (QEMU)"
    echo "=================================="
    echo
    echo "1) Setup (install deps, download ISO)"
    echo "2) Create VM disk"
    echo "3) Start VM (installer)"
    echo "4) Start VM (boot from disk)"
    echo "5) Clean up (delete disk)"
    echo "6) Exit"
    echo
    read -p "Choose option: " choice
    
    case $choice in
        1)
            install_deps
            download_iso
            show_menu
            ;;
        2)
            create_disk
            show_menu
            ;;
        3)
            start_vm
            show_menu
            ;;
        4)
            log_info "Starting VM from disk..."
            qemu-system-x86_64 \
                $KVM_ARGS \
                -m "$VM_MEMORY" \
                -smp "$VM_CPUS" \
                -drive file="$VM_DISK",format=qcow2,if=virtio \
                -vnc :0 \
                -serial mon:stdio \
                -device virtio-net-pci,netdev=wan,mac=52:54:00:12:34:00 \
                -netdev user,id=wan,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000 \
                -device virtio-net-pci,netdev=lan1,mac=52:54:00:12:34:01 \
                -netdev socket,id=lan1,listen=:8001 \
                -device virtio-net-pci,netdev=lan2,mac=52:54:00:12:34:02 \
                -netdev socket,id=lan2,listen=:8002 \
                -device virtio-net-pci,netdev=lan3,mac=52:54:00:12:34:03 \
                -netdev socket,id=lan3,listen=:8003 \
                -device virtio-net-pci,netdev=lan4,mac=52:54:00:12:34:04 \
                -netdev socket,id=lan4,listen=:8004
            show_menu
            ;;
        5)
            if [[ -f "$VM_DISK" ]]; then
                read -p "Delete $VM_DISK? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm "$VM_DISK"
                    log_success "Disk deleted"
                fi
            fi
            show_menu
            ;;
        6)
            log_info "Exiting"
            exit 0
            ;;
        *)
            log_warning "Invalid option"
            show_menu
            ;;
    esac
}

# Main
main() {
    check_wsl
    show_menu
}

main "$@"

