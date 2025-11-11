#!/usr/bin/env bash
# Test Client VM Script
# Creates a simple Alpine Linux VM to test router LAN connectivity

set -euo pipefail

# Configuration
CLIENT_NAME="${1:-client1}"
LAN_PORT="${2:-8001}"  # Which LAN port to connect to (8001-8004)
CLIENT_DISK="${CLIENT_NAME}.qcow2"
CLIENT_MEMORY="512M"
FILES_DIR="files"
ALPINE_ISO="${FILES_DIR}/alpine-virt-3.19.0-x86_64.iso"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso"

# Create files directory if it doesn't exist
mkdir -p "$FILES_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Download Alpine ISO if needed
if [[ ! -f "$ALPINE_ISO" ]]; then
    log_info "Downloading Alpine Linux ISO..."
    wget -O "$ALPINE_ISO" "$ALPINE_URL"
    log_success "ISO downloaded"
fi

# Create disk if needed
if [[ ! -f "$CLIENT_DISK" ]]; then
    log_info "Creating client disk..."
    qemu-img create -f qcow2 "$CLIENT_DISK" 2G
    log_success "Disk created: $CLIENT_DISK"
fi

log_info "Starting test client: $CLIENT_NAME"
log_info "Connecting to router LAN port: $LAN_PORT"
log_info "Access via VNC: localhost:590${CLIENT_NAME: -1}"
echo
log_info "To test DHCP from router:"
echo "  1. Boot Alpine (press Enter at boot prompt)"
echo "  2. Login as 'root' (no password)"
echo "  3. Run: setup-interfaces"
echo "  4. Choose eth0, select DHCP"
echo "  5. Run: ip addr show"
echo "  6. Test connectivity: ping 1.1.1.1"
echo

# Start VM connected to router's LAN port
qemu-system-x86_64 \
    -m "$CLIENT_MEMORY" \
    -boot d \
    -cdrom "$ALPINE_ISO" \
    -drive file="$CLIENT_DISK",format=qcow2,if=virtio \
    -vnc :${CLIENT_NAME: -1} \
    -serial mon:stdio \
    -device virtio-net-pci,netdev=lan,mac=52:54:00:12:34:$(printf '%02x' $((10 + ${CLIENT_NAME: -1}))) \
    -netdev socket,id=lan,connect=:$LAN_PORT

