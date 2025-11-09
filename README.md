# NixOS Router

A declarative NixOS configuration that transforms a standard PC into a full-featured network router with integrated secrets management.

## Features

- **Multiple WAN types**: DHCP, PPPoE, static IP, and PPTP support
- **LAN bridging**: Combine multiple Ethernet ports into one network
- **DNS**: Blocky resolver with upstream forwarding and caching
- **DHCP**: ISC dhcpd4 serving the bridged LAN
- **NAT & firewall**: Automatic network address translation and basic security
- **Port forwarding**: Configurable forwarding rules for internal services
- **Secrets management**: Encrypted secrets with sops-nix and Age

## Quick Start

### Automated Installation (Recommended)

Boot from NixOS installer ISO and run:
```bash
curl -fsSL https://beard.click/nixos-router | sudo bash
```

This script will interactively ask for:
- **Target disk** (shows available disks)
- **Hostname** (default: nixos-router)
- **Timezone** (default: America/Anchorage)
- **WAN interface** (shows available interfaces)
- **WAN connection type** (DHCP or PPPoE)
- **PPPoE credentials** (only if PPPoE selected)
- **LAN IP address** and subnet
- **DHCP range** and lease time for clients
- **LAN bridge interfaces**
- **Router admin password** (for system access)
- **Age key** (use existing or generate new)

Then it will:
- Partition and format your selected disk
- Install NixOS with the router configuration
- Set up Age keys (generate new or use existing)
- Set up the basic router system

### Manual Installation

1. **Install NixOS** with flakes enabled
2. **Clone this repository**
3. **Generate Age key** for encryption:
   ```bash
   sudo ./scripts/install-age-key.sh
   ```
4. **Create secrets** (see [docs/secrets.md](docs/secrets.md))
5. **Configure router** in `router-config.nix` (and adjust `configuration.nix` if you need additional tweaks)
6. **Deploy**:
   ```bash
   sudo nixos-rebuild switch --flake .#router
   ```

## Upgrading Existing Installations

For a quick refresh, run the hosted update helper:

```bash
curl -fsSL https://beard.click/nixos-router-update | sudo bash
```

This downloads the latest `scripts/update-router.sh`, backs up `/etc/nixos`, syncs the repository (preserving `hardware-configuration.nix`, `router-config.nix`, and `secrets/secrets.yaml`), then executes `nixos-rebuild switch --flake /etc/nixos#router`.

If you already have the repository checked out locally, you can invoke the script directly:

```bash
sudo /etc/nixos/scripts/update-router.sh
```

## Documentation

- **[Setup Guide](docs/setup.md)** - Installation, upgrades, and initial configuration
- **[Router Config](docs/router.md)** - WAN/LAN setup, Blocky DNS, dhcpd4, firewall, port forwarding
- **[Secrets Management](docs/secrets.md)** - sops-nix usage and key management
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions
- **[Development](docs/development.md)** - Contributing and development guide

## Requirements

- NixOS 25.05 or later with flakes enabled
- Age keypair for secret encryption
- Compatible network hardware

## Repository Structure

```
├── configuration.nix      # Main system config
├── router.nix            # Router module
├── flake.nix             # Nix flake
├── secrets/secrets.yaml  # Encrypted secrets
├── scripts/              # Helper scripts
└── docs/                 # Detailed documentation
```

## Security

- Secrets are encrypted at rest using Age public-key encryption
- Runtime secrets are accessible only to root with restrictive permissions
- No sensitive data is stored in plain text in the repository

## License

MIT License - see LICENSE file for details.

## Contributing

See [docs/development.md](docs/development.md) for development setup and contribution guidelines.