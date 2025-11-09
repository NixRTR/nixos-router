# Setup Guide

## Prerequisites

- NixOS system with flakes enabled
- Age keypair for encryption
- Basic networking knowledge

## Quick Start

### Option 1: Automated Installation (Recommended)

For fresh installations, boot from NixOS installer ISO:

```bash
# Download and run the installation script
curl -fsSL https://beard.click/nixos-router | sudo bash
```

The script will interactively prompt for:
- **Target disk** (displays available disks)
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

### Option 2: Manual Setup

1. **Clone and enter the repository**
   ```bash
   git clone https://github.com/williamhCode/nixos-router.git
   cd nixos-router
   nix develop  # Enter development shell
   ```

2. **Generate Age key**
   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt
   # OR use the provided script
   sudo ./scripts/install-age-key.sh
   ```

3. **Create secrets**
   ```bash
# Create plaintext secrets
cat > /tmp/secrets.yaml << EOF
pppoe-password: "your-isp-password"   # Only if using PPPoE
pppoe-username: "your-isp-username"   # Only if using PPPoE
password: "routeradmin-password"      # Plain text; hashed at activation
EOF

   # Encrypt them
   sops --encrypt --age $(age-keygen -y ~/.config/sops/age/keys.txt) \
        /tmp/secrets.yaml > secrets/secrets.yaml

   # Clean up
   shred -u /tmp/secrets.yaml
   ```

4. **Configure router**
   Edit `router-config.nix` (or re-run the installer script to regenerate it) to match your network setup:
   - Update interface names
   - Set IP ranges
   - Configure WAN type (DHCP/PPPoE/static)
   - Adjust Blocky DNS or DHCP options in `configuration.nix` if needed

5. **Deploy**
   ```bash
   sudo nixos-rebuild switch --flake .#router
   ```

## Age Key Management

The Age key is stored at `/var/lib/sops-nix/key.txt` and used automatically by sops-nix. For manual operations, copy it to `~/.config/sops/age/keys.txt`:

```bash
sudo cp /var/lib/sops-nix/key.txt ~/.config/sops/age/keys.txt
chmod 400 ~/.config/sops/age/keys.txt
```

## Network Configuration

Before deploying, update these settings in `router-config.nix` (and adjust `configuration.nix` if you need additional customization):

- **WAN interface**: Physical interface connected to your ISP
- **LAN interfaces**: Ethernet ports for your local network
- **IP ranges**: DHCP pool, lease time, and router IP
- **WAN credentials**: PPPoE username/password or static IP settings

## Post-Installation

After successful deployment:

1. Check router status: `systemctl status router-*`
2. Verify secrets: `ls -la /run/secrets/`
3. Test connectivity: `ping 8.8.8.8`
4. Check DHCP leases: `journalctl -u dhcpd4`
5. Monitor DNS resolver: `journalctl -u blocky -f`

## Upgrading Existing Systems

To pull the latest configuration onto an installed router, use the hosted helper:

```bash
curl -fsSL https://beard.click/nixos-router-update | sudo bash
```

This fetches the current `update-router.sh`, backs up `/etc/nixos`, syncs repository updates (preserving `hardware-configuration.nix`, `router-config.nix`, and `secrets/secrets.yaml`), then runs `nixos-rebuild switch --flake /etc/nixos#router`.

Alternatively, if the script is already present on the router:

```bash
sudo /etc/nixos/scripts/update-router.sh
```

## Development Shell

Use `nix develop` to enter an environment with all necessary tools:
- `sops` - Secret encryption
- `age` - Key generation
- `nixos-rebuild` - System deployment
- `nixfmt` - Code formatting
