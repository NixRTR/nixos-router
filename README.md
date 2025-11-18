# NixOS Router

A NixOS-based router configuration for home networks.

## Features

- Multi-network support (isolated LAN segments)
- DHCP server (Kea)
- DNS server (Unbound with ad-blocking)
- Web dashboard for monitoring
- Dynamic DNS updates (Linode)
- Firewall and NAT

## Requirements

- NixOS-capable hardware
- Network interfaces for WAN and LAN
- Internet connection for initial setup

## Installation

### Option 1: Custom ISO

1. Build the ISO:
   ```bash
   cd iso
   ./build-iso.sh
   ```

2. Write ISO to USB and boot

3. Follow on-screen installation menu

### Option 2: Online Installer

Boot from standard NixOS ISO and run:

```bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

## Configuration

Edit `router-config.nix` to configure:

- Hostname and timezone
- WAN interface and type (DHCP or PPPoE)
- LAN networks (IP ranges, interfaces)
- DHCP ranges
- DNS settings
- Web dashboard settings

## Web Dashboard

Access at `http://router-ip:8080`

Shows:
- System metrics (CPU, memory, load)
- Network interface statistics
- Device usage and bandwidth
- Service status

## Project Structure

- `router-config.nix` - Main configuration file
- `configuration.nix` - NixOS system configuration
- `modules/` - Router modules (router, dns, dhcp, webui, etc.)
- `scripts/` - Installation and update scripts
- `webui/` - Web dashboard (FastAPI backend, React frontend)

## Updating

```bash
sudo ./scripts/update-router.sh
```

## License

MIT
