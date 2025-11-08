# Troubleshooting Guide

## Common Issues

### Build Fails: "infinite recursion encountered"

**Symptoms:**
```
error: infinite recursion encountered
```

**Causes:**
- Incorrect sops-nix module import
- Circular dependencies in configuration

**Solutions:**
1. Check sops-nix import in `configuration.nix`:
   ```nix
   imports = [
     <nixpkgs/nixos/modules/security/sops/default.nix>
     ./hardware-configuration.nix
     ./router.nix
   ];
   ```

2. Avoid using `pkgs.sops-nix` in imports - use the nixpkgs module path

### Secrets Not Decrypted

**Symptoms:**
```
ls: cannot access '/run/secrets/': No such file or directory
```

**Solutions:**
1. Check sops-nix service status:
   ```bash
   systemctl status sops-nix
   journalctl -u sops-nix
   ```

2. Verify Age key exists:
   ```bash
   ls -la /var/lib/sops-nix/key.txt
   ```

3. Test manual decryption:
   ```bash
   SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops --decrypt secrets/secrets.yaml
   ```

### PPPoE Connection Fails

**Symptoms:**
- No internet connectivity
- `ip addr show ppp0` shows no interface

**Checks:**
1. Verify PPPoE credentials:
   ```bash
   cat /run/secrets/pppoe-username
   cat /run/secrets/pppoe-password
   ```

2. Check PPP logs:
   ```bash
   journalctl -u pppd
   ```

3. Verify WAN interface:
   ```bash
   ip link show <wan-interface>
   ```

4. Test PPPoE manually:
   ```bash
   sudo pon <wan-interface>
   ```

### DHCP Not Working

**Symptoms:**
- Clients can't get IP addresses
- Router shows no DHCP leases

**Checks:**
1. Verify dnsmasq is running:
   ```bash
   systemctl status dnsmasq
   ```

2. Check dnsmasq logs:
   ```bash
   journalctl -u dnsmasq -f
   ```

3. Verify bridge configuration:
   ```bash
   brctl show br0
   ip addr show br0
   ```

4. Test DHCP manually:
   ```bash
   dhcpcd -T br0  # Test DHCP on bridge
   ```

### Firewall Blocking Traffic

**Symptoms:**
- Services accessible locally but not from LAN
- Port forwarding not working

**Checks:**
1. Check firewall rules:
   ```bash
   iptables -L -n
   iptables -t nat -L -n
   ```

2. Verify interface zones:
   ```bash
   firewall-cmd --get-zones  # If using firewalld
   # OR
   nft list ruleset          # If using nftables
   ```

3. Test port forwarding:
   ```bash
   # From LAN client
   telnet <router-ip> <port>
   ```

### NAT Not Working

**Symptoms:**
- LAN clients can't access internet
- Outbound traffic blocked

**Checks:**
1. Verify NAT rules:
   ```bash
   iptables -t nat -L POSTROUTING
   ```

2. Check forwarding is enabled:
   ```bash
   sysctl net.ipv4.ip_forward
   cat /proc/sys/net/ipv4/ip_forward
   ```

3. Test from LAN client:
   ```bash
   ping 8.8.8.8
   traceroute 8.8.8.8
   ```

## Debugging Commands

### Network Diagnostics
```bash
# Show all interfaces and IPs
ip addr show

# Show routing table
ip route show

# Show ARP table
ip neigh show

# Test connectivity
ping -c 4 8.8.8.8
traceroute 8.8.8.8

# Check DNS resolution
nslookup google.com
dig @8.8.8.8 google.com
```

### Service Status
```bash
# Router services
systemctl status router-*
systemctl status dnsmasq
systemctl status pppd

# System services
systemctl status systemd-networkd
systemctl status sops-nix

# Logs
journalctl -u dnsmasq -f
journalctl -u pppd -f
journalctl -u systemd-networkd -f
```

### Firewall Debugging
```bash
# Show all rules
iptables -L -n -v
iptables -t nat -L -n -v
iptables -t mangle -L -n -v

# Check specific chains
iptables -L INPUT -n -v
iptables -L FORWARD -n -v
iptables -L OUTPUT -n -v

# Test rule matching
iptables -C INPUT -i br0 -p tcp --dport 80 -j ACCEPT 2>/dev/null && echo "Rule exists" || echo "Rule missing"
```

### Bridge Debugging
```bash
# Show bridge status
brctl show br0
brctl showmacs br0
brctl showstp br0

# Show bridge interface
ip link show br0
ip addr show br0

# Check bridge ports
for port in $(brctl show br0 | awk 'NR>1 {print $4}'); do
  echo "Port $port:"
  ip link show "$port"
done
```

## Recovery Procedures

### Reset Network Configuration
```bash
# Stop all network services
systemctl stop systemd-networkd dnsmasq pppd

# Reset interfaces
ip link set br0 down
ip link set enp1s0 down  # Adjust interface names
ip link delete br0

# Restart networking
systemctl restart systemd-networkd
```

### Rebuild Without Router Module
Temporarily disable the router to isolate issues:
```nix
# In configuration.nix
# router.enable = false;

# Rebuild and test basic connectivity
sudo nixos-rebuild switch --flake .#router
```

### Emergency Console Access
If SSH is broken, use console access:
```bash
# At system console or IPMI
# Check network status
ip addr show
ip route show

# Manually start services
systemctl start dnsmasq
systemctl start systemd-networkd
```

## Configuration Validation

### Test Configuration Syntax
```bash
# Check Nix syntax
nix-instantiate --parse configuration.nix

# Evaluate configuration (dry run)
nixos-rebuild dry-build --flake .#router
```

### Validate Secrets
```bash
# Check secrets file syntax
sops --decrypt secrets/secrets.yaml > /dev/null

# Verify required secrets exist
for secret in pppoe-username pppoe-password password; do
  if ! grep -q "^$secret:" secrets/secrets.yaml; then
    echo "Missing secret: $secret"
  fi
done
```

## Getting Help

### Information to Provide
When asking for help, include:

1. **System details:**
   ```bash
   nixos-version
   uname -a
   ```

2. **Configuration excerpts** (redact secrets)

3. **Error messages** (full output)

4. **Network topology** (interfaces, IPs, ISP type)

5. **Service status:**
   ```bash
   systemctl status --all | grep -E "(router|dnsmasq|pppd|networkd|sops)"
   ```

### Community Resources
- [NixOS Discourse](https://discourse.nixos.org/)
- [sops-nix Issues](https://github.com/Mic92/sops-nix/issues)
- [NixOS Wiki](https://nixos.wiki/)
