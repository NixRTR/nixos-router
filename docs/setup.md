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
- **LAN IP address** and subnet
- **DHCP range** for clients
- **LAN bridge interfaces**
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
   pppoe-password: "your-isp-password"
   pppoe-username: "your-isp-username"
   password: "$(mkpasswd -m sha-512)"
   EOF

   # Encrypt them
   sops --encrypt --age $(age-keygen -y ~/.config/sops/age/keys.txt) \
        /tmp/secrets.yaml > secrets/secrets.yaml

   # Clean up
   shred -u /tmp/secrets.yaml
   ```

4. **Configure router**
   Edit `configuration.nix` to match your network setup:
   - Update interface names
   - Set IP ranges
   - Configure WAN type (DHCP/PPPoE/static)

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

Before deploying, update these settings in `configuration.nix`:

- **WAN interface**: Physical interface connected to your ISP
- **LAN interfaces**: Ethernet ports for your local network
- **IP ranges**: DHCP pool and router IP
- **WAN credentials**: PPPoE username/password or static IP settings

## Post-Installation

After successful deployment:

1. Check router status: `systemctl status router-*`
2. Verify secrets: `ls -la /run/secrets/`
3. Test connectivity: `ping 8.8.8.8`
4. Check DHCP leases: `journalctl -u dnsmasq`

## Development Shell

Use `nix develop` to enter an environment with all necessary tools:
- `sops` - Secret encryption
- `age` - Key generation
- `nixos-rebuild` - System deployment
- `nixfmt` - Code formatting
