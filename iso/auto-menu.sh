#!/usr/bin/env bash
#
# NixOS Router - Automated Installation Menu
# This script runs automatically when the ISO boots

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║          NixOS Router Installation System                ║
║                                                           ║
║     Declarative, High-Performance Network Router         ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# Logging functions
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

# Detect USB drives and look for router-config.nix
find_router_config() {
    local config_path=""
    
    log_info "Scanning for USB drives with router-config.nix..."
    
    # Look for mounted drives
    for mount_point in /media/* /mnt/* /run/media/*; do
        if [ -f "$mount_point/router-config.nix" ]; then
            config_path="$mount_point/router-config.nix"
            log_success "Found router-config.nix at: $config_path"
            echo "$config_path"
            return 0
        fi
    done
    
    # Try to find and mount USB devices
    for device in /dev/sd[b-z]1 /dev/nvme[1-9]n1p1; do
        if [ -b "$device" ]; then
            local temp_mount="/tmp/usb_check_$$"
            mkdir -p "$temp_mount"
            if mount -o ro "$device" "$temp_mount" 2>/dev/null; then
                if [ -f "$temp_mount/router-config.nix" ]; then
                    config_path="$temp_mount/router-config.nix"
                    log_success "Found router-config.nix on $device"
                    echo "$config_path"
                    return 0
                fi
                umount "$temp_mount"
                rmdir "$temp_mount"
            fi
        fi
    done
    
    return 1
}

# Download and run script from URL
download_and_run() {
    local url="$1"
    local script_name="$2"
    
    log_info "Downloading $script_name..."
    
    if curl -fsSL "$url" -o "/tmp/$script_name"; then
        chmod +x "/tmp/$script_name"
        log_success "Downloaded $script_name"
        
        echo ""
        echo -e "${GREEN}Starting $script_name...${NC}"
        echo ""
        sleep 2
        
        bash "/tmp/$script_name"
    else
        log_error "Failed to download $script_name from $url"
        echo ""
        read -p "Press Enter to return to menu..."
    fi
}

# Run local script
run_local_script() {
    local script_path="$1"
    local script_name="$2"
    
    if [ -f "$script_path" ]; then
        log_success "Found $script_name"
        chmod +x "$script_path"
        
        echo ""
        echo -e "${GREEN}Starting $script_name...${NC}"
        echo ""
        sleep 2
        
        bash "$script_path"
    else
        log_error "Script not found: $script_path"
        echo ""
        read -p "Press Enter to return to menu..."
    fi
}

# Automated installation with existing router-config.nix
automated_install() {
    local config_path="$1"
    
    show_banner
    echo -e "${GREEN}═══ Automated Installation Mode ═══${NC}"
    echo ""
    echo "Found configuration file:"
    echo -e "  ${CYAN}$config_path${NC}"
    echo ""
    echo "This will:"
    echo "  1. Run the installation script"
    echo "  2. Automatically use your router-config.nix"
    echo "  3. Skip interactive configuration steps"
    echo ""
    
    read -p "Continue with automated installation? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Export the config path for the installer to use
    export ROUTER_CONFIG_PATH="$config_path"
    export AUTOMATED_MODE="true"
    
    # Download and run the installer
    download_and_run "https://beard.click/nixos-router" "install-router.sh"
}

# Main menu
show_menu() {
    local router_config_path=""
    
    while true; do
        # Check for router-config.nix on USB
        router_config_path=$(find_router_config) || true
        
        show_banner
        
        if [ -n "$router_config_path" ]; then
            echo -e "${GREEN}✓ Detected router-config.nix on USB drive${NC}"
            echo ""
        fi
        
        echo -e "${MAGENTA}═══ Installation Options ═══${NC}"
        echo ""
        
        if [ -n "$router_config_path" ]; then
            echo -e "  ${GREEN}1)${NC} Automated Installation (using USB config)"
            echo ""
        fi
        
        echo -e "  ${GREEN}2)${NC} Guided Installation (install-router.sh)"
        echo -e "  ${GREEN}3)${NC} Update Router Software (update-router.sh)"
        echo -e "  ${GREEN}4)${NC} Update Router Config (update-router-config.sh)"
        echo ""
        echo -e "  ${CYAN}5)${NC} Rescan for USB drives"
        echo -e "  ${CYAN}6)${NC} Open Shell (advanced users)"
        echo ""
        echo -e "  ${RED}0)${NC} Exit to shell"
        echo ""
        
        read -p "Select an option: " choice
        
        case $choice in
            1)
                if [ -n "$router_config_path" ]; then
                    automated_install "$router_config_path"
                else
                    log_error "No router-config.nix found. Please insert USB drive."
                    sleep 2
                fi
                ;;
            2)
                download_and_run "https://beard.click/nixos-router" "install-router.sh"
                ;;
            3)
                download_and_run "https://beard.click/nixos-router-update" "update-router.sh"
                ;;
            4)
                download_and_run "https://beard.click/nixos-router-config" "update-router-config.sh"
                ;;
            5)
                log_info "Rescanning..."
                sleep 1
                ;;
            6)
                clear
                echo -e "${CYAN}Opening shell...${NC}"
                echo ""
                echo "Type 'exit' to return to the menu."
                echo ""
                bash
                ;;
            0)
                clear
                echo -e "${GREEN}Exiting to shell...${NC}"
                echo ""
                echo "Run 'router-menu' to return to this menu."
                echo ""
                exit 0
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Note: Some operations require root privileges.${NC}"
    echo "Run: sudo router-menu"
    echo ""
    read -p "Press Enter to continue anyway..."
fi

# Show menu
show_menu

