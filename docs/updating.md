# Updating Your Router

Keep your router up to date with the latest features, security patches, and optimizations.

## Update Methods

### Quick Update (Recommended)

Use the convenience scripts for one-command updates.

#### Update Configuration Only

Changes to `router-config.nix` without pulling new code:

```bash
curl -fsSL https://beard.click/nixos-router-config > config.sh
chmod +x config.sh
sudo ./config.sh
```

**Use when**:
- Changing network settings
- Adding port forwards
- Modifying DHCP ranges
- Enabling/disabling optional features

**Downtime**: None (changes apply in seconds)

#### Full System Update

Updates NixOS, router code, and configuration:

```bash
curl -fsSL https://beard.click/nixos-router-update
chmod +x config.sh
sudo ./config.sh
```

**Use when**:
- Updating to new router features
- Security updates available
- Bug fixes released

**Downtime**: 30-60 seconds (network interruption during switch)

### Manual Update

For more control over the update process.

#### 1. Pull Latest Code

```bash
cd /etc/nixos
sudo git pull origin main
```

#### 2. Review Changes

```bash
git log --oneline -10
git diff HEAD~5
```

#### 3. Update Flake Inputs

```bash
sudo nix flake update
```

This updates:
- `nixpkgs` (NixOS packages)
- `sops-nix` (secrets management)

#### 4. Apply Changes

```bash
sudo nixos-rebuild switch --flake .#router
```

#### 5. Verify

Check services:

```bash
systemctl status blocky
systemctl status kea-dhcp4-server
systemctl status grafana
```

---


### Automation (Optional)

Set up automatic security updates:

Edit `/etc/nixos/configuration.nix`:

```nix
{
  # Automatic security updates
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#router";
    flags = [
      "--update-input" "nixpkgs"
      "--commit-lock-file"
    ];
    dates = "weekly";  # Or "daily", "Mon *-*-* 02:00:00"
    allowReboot = false;  # Set to true for automatic reboots if needed
  };
}
```

Apply:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

**Warning**: Automatic updates may break things. Test updates manually first.

---

## What Gets Updated

### NixOS System

- Kernel
- System libraries
- Core utilities

### Router Services

- Blocky (DNS resolver)
- Kea (DHCP server)
- Grafana (monitoring dashboard)
- Prometheus (metrics collection)
- Node Exporter (system metrics)

### Router Features

- Network configuration
- Firewall rules
- Port forwarding
- Isolation rules
- Performance optimizations

### User Configuration

Your settings in `router-config.nix` are **preserved** during updates.

---

## Rolling Back

If an update causes issues, roll back to previous configuration.

### List Available Generations

```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Output:

```
  10   2023-10-15 14:22:33
  11   2023-10-20 09:15:42
  12   2023-10-25 11:30:21   (current)
```

### Roll Back to Previous Generation

```bash
sudo nixos-rebuild switch --rollback
```

This switches to the previous generation (e.g., generation 11).

### Roll Back to Specific Generation

```bash
sudo /nix/var/nix/profiles/system-11-link/bin/switch-to-configuration switch
```

### Verify Rollback

```bash
nixos-version
systemctl status blocky
```

### Make Rollback Permanent

After rolling back, the rolled-back generation becomes current.

To prevent accidental re-update:

```bash
cd /etc/nixos
sudo git log  # Find the commit before the problematic one
sudo git reset --hard <commit-hash>
```

---

## Updating Secrets

Secrets are encrypted separately and don't auto-update.

### Edit Secrets

```bash
cd /etc/nixos
sops secrets/secrets.yaml
```

Make changes, save, exit.

### Apply Secret Changes

```bash
curl -fsSL https://beard.click/nixos-router-config | sudo bash
```

Or manually:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

### Rotating Age Keys

If you need to change encryption keys:

#### 1. Generate New Key

```bash
sudo age-keygen -o /var/lib/sops-nix/key-new.txt
```

#### 2. Get Public Key

```bash
grep "public key:" /var/lib/sops-nix/key-new.txt
# age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### 3. Re-encrypt Secrets

```bash
cd /etc/nixos
sops --rotate --age age1newpublickey... secrets/secrets.yaml
```

#### 4. Replace Old Key

```bash
sudo mv /var/lib/sops-nix/key.txt /var/lib/sops-nix/key-old.txt
sudo mv /var/lib/sops-nix/key-new.txt /var/lib/sops-nix/key.txt
```

#### 5. Apply Changes

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

---

## Updating Flake Lock

The `flake.lock` file pins specific versions of dependencies.

### Why Update Lock File?

- Get latest packages
- Security updates
- Bug fixes

### Update All Inputs

```bash
cd /etc/nixos
sudo nix flake update
```

### Update Specific Input

```bash
sudo nix flake lock --update-input nixpkgs
sudo nix flake lock --update-input sops-nix
```

### View Changes Before Applying

```bash
git diff flake.lock
```

### Apply Updated Lock File

```bash
sudo nixos-rebuild switch --flake .#router
```

---

## Migration Guides

### Migrating from Single-LAN to Multi-LAN

If you have an existing single-LAN setup:

#### Before Migration

1. **Backup configuration**:
   ```bash
   cd /etc/nixos
   sudo git add -A
   sudo git commit -m "Backup before multi-LAN migration"
   ```

2. **Document current setup**:
   - Note all static IPs
   - List all DHCP reservations
   - Save port forwarding rules

#### Migration Steps

1. **Update configuration** (see [Network Isolation](isolation.md))

2. **Plan IP ranges**:
   - br0 (HOMELAB): `192.168.2.0/24`
   - br1 (LAN): `192.168.3.0/24`

3. **Apply configuration**:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#router
   ```

4. **Reconnect devices**:
   - Physical ports changed
   - IP addresses changed
   - Devices will get new IPs via DHCP

5. **Update static IPs**:
   - Reconfigure devices with new static IPs
   - Or use DHCP reservations

6. **Test connectivity**:
   - Each network can reach Internet
   - Isolation is working
   - Exceptions working (if configured)

#### Rollback Plan

If migration fails:

```bash
cd /etc/nixos
sudo git reset --hard HEAD~1
sudo nixos-rebuild switch --flake .#router
```

---

## Troubleshooting Updates

### Update Fails to Apply

**Error**: `error: building NixOS configuration failed`

**Solution**:

1. **Check syntax**:
   ```bash
   cd /etc/nixos
   nix flake check
   ```

2. **View full error**:
   ```bash
   sudo nixos-rebuild switch --flake .#router --show-trace
   ```

3. **Roll back**:
   ```bash
   sudo nixos-rebuild switch --rollback
   ```

### Network Down After Update

**Symptoms**: No internet after update

**Solution**:

1. **Check interface status**:
   ```bash
   ip link show
   ip addr show
   ```

2. **Check services**:
   ```bash
   systemctl status systemd-networkd
   systemctl status blocky
   systemctl status kea-dhcp4-server
   ```

3. **Check configuration**:
   ```bash
   cat /etc/nixos/router-config.nix
   ```

4. **Roll back**:
   ```bash
   sudo nixos-rebuild switch --rollback
   ```

### Secrets Won't Decrypt

**Error**: `error: could not decrypt secret`

**Solution**:

1. **Check Age key exists**:
   ```bash
   sudo cat /var/lib/sops-nix/key.txt
   ```

2. **Check key matches secrets**:
   ```bash
   sops --decrypt /etc/nixos/secrets/secrets.yaml
   ```

3. **Re-encrypt if needed**:
   ```bash
   # Get public key
   grep "public key:" /var/lib/sops-nix/key.txt
   
   # Re-encrypt
   cd /etc/nixos
   sops --rotate --age age1yourpublickey... secrets/secrets.yaml
   ```

### Flake Update Breaks Build

**Error**: `error: package X not found`

**Solution**:

1. **Revert flake.lock**:
   ```bash
   cd /etc/nixos
   sudo git checkout HEAD -- flake.lock
   ```

2. **Apply old lock**:
   ```bash
   sudo nixos-rebuild switch --flake .#router
   ```

3. **Update incrementally**:
   ```bash
   # Update one input at a time
   sudo nix flake lock --update-input nixpkgs
   sudo nixos-rebuild switch --flake .#router
   # If works, continue with other inputs
   ```

---

## Best Practices

### Before Every Update

1. ✅ **Check Grafana dashboard** - Ensure router is stable
2. ✅ **Note current generation** - For easy rollback
3. ✅ **Backup configuration** - Git commit
4. ✅ **Schedule maintenance window** - Update during low-traffic time
5. ✅ **Have backup access** - Physical console or OOB management

### During Update

1. ✅ **Watch logs** - `journalctl -f`
2. ✅ **Monitor services** - Check status after update
3. ✅ **Test connectivity** - Ping test from each network
4. ✅ **Check dashboard** - Verify metrics still flowing

### After Update

1. ✅ **Document changes** - Git commit with descriptive message
2. ✅ **Test all features**:
   - Internet access from all networks
   - DNS resolution
   - DHCP assignments
   - Port forwards
   - Grafana dashboard
   - Isolation rules
3. ✅ **Monitor for 24 hours** - Watch for unexpected issues
4. ✅ **Update documentation** - If behavior changed

### Change Management

Keep a change log:

```bash
# /etc/nixos/CHANGELOG.md
## 2023-10-25

- Updated to latest nixpkgs
- Added br1 (LAN network)
- Enabled network isolation
- Added workstation isolation exception

## 2023-10-20

- Increased DHCP lease time to 24h
- Added port forward for web server
- Updated Grafana to 10.2.0
```

---

## Emergency Recovery

### Can't SSH After Update

**Solution 1: Console Access**

1. Physical access to router
2. Log in on console
3. Roll back: `sudo nixos-rebuild switch --rollback`

**Solution 2: Reboot**

Previous generation is in bootloader menu:

1. Reboot router
2. At GRUB menu, select previous generation
3. Boot into working configuration

### Bootloader Recovery

If router won't boot:

1. Boot from NixOS installer USB
2. Mount filesystems:
   ```bash
   mount /dev/sda2 /mnt
   mount /dev/sda1 /mnt/boot
   ```
3. Chroot:
   ```bash
   nixos-enter --root /mnt
   ```
4. Roll back:
   ```bash
   nixos-rebuild switch --rollback
   ```
5. Reboot:
   ```bash
   exit
   reboot
   ```

---

## Next Steps

- **[Troubleshooting](troubleshooting.md)** - Fix common issues
- **[Configuration](configuration.md)** - Customize your router
- **[Monitoring](monitoring.md)** - Watch for update issues


