# Troubleshooting

Common issues and solutions for your NixOS router.

## Quick Diagnostics

Run these commands to quickly check router health:

```bash
# Check all critical services
systemctl status systemd-networkd blocky kea-dhcp4-server grafana prometheus

# Check network interfaces
ip addr show

# Check internet connectivity
ping -c 3 1.1.1.1

# Check DNS
dig google.com @127.0.0.1

# Check firewall
sudo iptables -L -v -n | head -30
```

---

## No Internet Access

### Symptoms

- Can't reach external websites
- Ping to `1.1.1.1` fails
- LAN devices can ping router but not Internet

### Diagnosis

#### Step 1: Check WAN Interface

```bash
ip addr show eno1
```

**Expected**: Interface has an IP address

**If no IP**:
- DHCP issue (if using DHCP WAN)
- Cable unplugged
- Modem not providing connection

#### Step 2: Test WAN Connectivity

```bash
# From router
ping -I eno1 1.1.1.1
```

**If fails**: Problem with WAN connection (ISP, modem, cable)

**If works**: Problem with routing or NAT

#### Step 3: Check Routing

```bash
ip route show
```

**Expected**:
```
default via X.X.X.X dev eno1
192.168.2.0/24 dev br0 proto kernel scope link src 192.168.2.1
192.168.3.0/24 dev br1 proto kernel scope link src 192.168.3.1
```

**If missing default route**: WAN not configured properly

#### Step 4: Check NAT

```bash
sudo iptables -t nat -L POSTROUTING -v -n
```

**Expected**: MASQUERADE rule for WAN interface

**If missing**:
```bash
# Check router configuration
cat /etc/nixos/router-config.nix | grep -A 5 "wan ="
```

### Solutions

#### DHCP WAN Not Getting IP

```bash
# Restart networkd
sudo systemctl restart systemd-networkd

# Check logs
journalctl -u systemd-networkd -n 50

# Manual DHCP test
sudo dhclient -v eno1
```

#### PPPoE Not Connecting

```bash
# Check PPPoE status
sudo systemctl status pppoe-wan

# Check secrets
sudo sops --decrypt /etc/nixos/secrets/secrets.yaml | grep pppoe

# Check logs
journalctl -u pppoe-wan -n 50
```

#### Static IP Misconfiguration

Verify `router-config.nix`:

```nix
wan = {
  type = "static";
  interface = "eno1";
  static = {
    ipv4 = {
      address = "203.0.113.2";      # Your static IP
      prefixLength = 24;             # Usually 24 or 30
      gateway = "203.0.113.1";       # ISP gateway
    };
    dnsServers = [ "1.1.1.1" "8.8.8.8" ];
  };
};
```

Apply:

```bash
curl -fsSL https://beard.click/nixos-router-config | sudo bash
```

---

## No DHCP Leases

### Symptoms

- Devices can't get IP addresses
- "Limited connectivity" on Windows
- "No IP assigned" on Linux/Mac

### Diagnosis

#### Check Kea DHCP Server

```bash
systemctl status kea-dhcp4-server
```

**If not running**:

```bash
# Check logs
journalctl -u kea-dhcp4-server -n 50

# Try to start
sudo systemctl start kea-dhcp4-server
```

#### Check DHCP Configuration

```bash
sudo cat /etc/kea/dhcp4.conf
```

Verify subnets match your network configuration.

#### Check Network Connectivity

From a device:

```bash
# Release and renew (Linux)
sudo dhclient -r eth0
sudo dhclient -v eth0

# Release and renew (Windows)
ipconfig /release
ipconfig /renew

# Release and renew (Mac)
sudo ipconfig set en0 DHCP
```

Watch Kea logs:

```bash
journalctl -u kea-dhcp4-server -f
```

You should see:

```
DHCP4_DISCOVER received from client
DHCP4_OFFER sent to client
DHCP4_REQUEST received from client
DHCP4_ACK sent to client
```

### Solutions

#### Kea Not Starting

```bash
# Check configuration syntax
sudo kea-dhcp4 -t /etc/kea/dhcp4.conf

# If config error, check your router-config.nix
cat /etc/nixos/router-config.nix | grep -A 15 "dhcp ="
```

#### DHCP Pool Exhausted

```bash
# Check active leases
sudo kea-shell --host 127.0.0.1 --port 8000 <<< '{"command": "lease4-get-all", "service": ["dhcp4"]}'
```

**Solution**: Expand DHCP range in `router-config.nix`:

```nix
dhcp = {
  homelab = {
    start = "192.168.2.100";
    end = "192.168.2.250";  # Increased from 200
    # ...
  };
};
```

#### Bridge Interface Down

```bash
# Check bridge status
ip link show br0
ip link show br1

# If down, bring up
sudo ip link set br0 up
sudo ip link set br1 up
```

---

## DNS Not Working

### Symptoms

- Can ping `1.1.1.1` but can't access `google.com`
- "DNS server not responding"
- Slow web browsing

### Diagnosis

#### Test DNS Resolution

```bash
# From router
dig google.com @127.0.0.1

# From LAN device
dig google.com @192.168.2.1
```

**Expected**: Returns IP addresses

**If timeout**: Blocky not running or misconfigured

#### Check Blocky Status

```bash
systemctl status blocky

# Check logs
journalctl -u blocky -n 50
```

#### Test Upstream DNS

```bash
# Bypass Blocky, test upstreams directly
dig google.com @1.1.1.1
dig google.com @8.8.8.8
```

**If these fail**: Internet connectivity issue (not DNS)

### Solutions

#### Blocky Not Starting

```bash
# Check configuration
sudo blocky validate --config /etc/blocky/config.yml

# Restart
sudo systemctl restart blocky
```

#### Upstream DNS Not Reachable

Check firewall allows DNS out:

```bash
sudo iptables -L OUTPUT -v -n | grep 53
```

**Solution**: Ensure WAN masquerading is working (see [No Internet Access](#no-internet-access))

#### DNS Caching Issues

```bash
# Clear Blocky cache
sudo systemctl restart blocky
```

#### Wrong DNS Server on Clients

Verify DHCP is providing correct DNS:

```bash
# On Linux client
cat /etc/resolv.conf
# Should show: nameserver 192.168.2.1 (or your router IP)

# On Windows client
ipconfig /all
# Look for "DNS Servers" - should be router IP
```

**If wrong DNS**: Check DHCP configuration in `router-config.nix`:

```nix
dhcp = {
  homelab = {
    dns = "192.168.2.1";  # Should match router IP
    # ...
  };
};
```

---

## Port Forwarding Not Working

### Symptoms

- External connections to forwarded port timeout
- Services work internally but not externally

### Diagnosis

#### Check Port Forward Rules

```bash
sudo iptables -t nat -L PREROUTING -v -n | grep <your-port>
```

**Expected**: DNAT rule for your port

#### Check Firewall Rules

```bash
sudo iptables -L FORWARD -v -n | grep <your-port>
```

**Expected**: ACCEPT rule for forwarded traffic

#### Test from WAN Side

```bash
# From external network (e.g., your phone on cellular)
curl http://your-wan-ip:port
# Or
telnet your-wan-ip port
```

#### Check Service on Internal Device

```bash
# From router or another LAN device
curl http://192.168.2.33:port
```

**If this fails**: Problem with the service itself, not port forwarding

### Solutions

#### Port Forward Not in iptables

Verify configuration in `router-config.nix`:

```nix
portForwards = [
  {
    proto = "tcp";
    externalPort = 80;
    destination = "192.168.2.33";
    destinationPort = 80;
  }
];
```

Apply:

```bash
curl -fsSL https://beard.click/nixos-router-config | sudo bash
```

Verify:

```bash
sudo iptables -t nat -L PREROUTING -v -n
```

#### ISP Blocking Port

Some ISPs block common ports (80, 443, 25, etc.).

**Test**: Use a different external port:

```nix
portForwards = [
  {
    proto = "tcp";
    externalPort = 8080;      # External port
    destination = "192.168.2.33";
    destinationPort = 80;     # Internal port
  }
];
```

#### Hairpin NAT Not Working

Can't access forwarded service from internal network using external IP.

**Workaround**: Use internal IP from internal network:
- External: `http://wan-ip:8080`
- Internal: `http://192.168.2.33:80`

**Future**: Hairpin NAT support may be added.

---

## Network Isolation Issues

### Can't Access Devices on Other Network (Expected)

This is **normal** with isolation enabled. See [Network Isolation](isolation.md) for exceptions.

### Exception Not Working

#### Check Exception Configuration

```bash
cat /etc/nixos/router-config.nix | grep -A 10 "isolationExceptions"
```

#### Check Firewall Rules

```bash
sudo iptables -L FORWARD -v -n --line-numbers
```

**Expected**: ACCEPT rules for exceptions **before** DROP rules

**Correct order**:
```
1. ACCEPT from 192.168.3.50 (exception)
2. ACCEPT return traffic to 192.168.3.50
3. DROP between br1 and br0
```

**Wrong order**:
```
1. DROP between br1 and br0
2. ACCEPT from 192.168.3.50 (never reached!)
```

**Solution**: This should be automatic. If wrong, file a bug.

#### Verify Source IP

Exception only works from **exact IP** configured:

```bash
# On device
ip addr show
# Must match source IP in exception config
```

**Solution**: Use static IP or DHCP reservation.

#### Test Exception

From exception device (e.g., 192.168.3.50):

```bash
# Should work
ping 192.168.2.1
ping 192.168.2.10

# Should still fail (isolation to other networks)
ping 192.168.4.1  # If you have br2
```

---

## High CPU Usage

### Symptoms

- Router feels sluggish
- `htop` shows high CPU
- Network throughput degraded

### Diagnosis

#### Check CPU Usage

```bash
htop
```

Identify process using CPU.

#### Check CPU Governor

```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

**Expected**: `performance`

**If `powersave`**: CPU throttled

### Solutions

#### Set Performance Governor

Already configured, but verify:

```bash
cat /etc/nixos/configuration.nix | grep cpuFreqGovernor
```

Should show:

```nix
powerManagement.cpuFreqGovernor = "performance";
```

#### Enable Hardware Offloading

See [Performance Guide](performance.md) - should already be enabled.

Verify:

```bash
sudo ethtool -k eno1 | grep offload
```

#### Reduce Firewall Rules

Complex firewall rules increase CPU usage.

Review rules:

```bash
sudo iptables -L -v -n | less
```

Remove unnecessary rules from configuration.

#### Check for Attacks

```bash
# Check connection count
sudo conntrack -L | wc -l

# Check for SYN flood
sudo netstat -an | grep SYN_RECV | wc -l
```

**If high**: You may be under attack. Enable rate limiting:

```nix
networking.firewall.extraCommands = ''
  # Rate limit new connections
  iptables -A INPUT -p tcp -m state --state NEW -m recent --set
  iptables -A INPUT -p tcp -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
'';
```

---

## Grafana Dashboard Not Working

### Can't Access Dashboard

#### Check Grafana Service

```bash
systemctl status grafana
```

#### Check Port

```bash
sudo ss -tlnp | grep 3000
```

**Expected**: Grafana listening on `0.0.0.0:3000` or `:::3000`

#### Check Firewall

Grafana should be accessible from LAN (trusted interfaces).

```bash
sudo iptables -L INPUT -v -n | grep 3000
```

#### Test from Router

```bash
curl http://127.0.0.1:3000
```

**If works**: Issue is network routing, not Grafana

### Dashboard Shows No Data

#### Check Prometheus

```bash
systemctl status prometheus

# Check metrics
curl http://127.0.0.1:9090/metrics | head
```

#### Check Node Exporter

```bash
systemctl status prometheus-node-exporter

# Check metrics
curl http://127.0.0.1:9100/metrics | head
```

#### Check Data Source in Grafana

1. Open Grafana: `http://192.168.2.1:3000`
2. Settings (gear icon) → Data Sources
3. Click "Prometheus"
4. Click "Save & Test"

**Expected**: "Data source is working"

### Solutions

#### Restart Services

```bash
sudo systemctl restart grafana prometheus prometheus-node-exporter
```

#### Reset Grafana

```bash
# Backup first
sudo cp -r /var/lib/grafana /var/lib/grafana.bak

# Reset
sudo systemctl stop grafana
sudo rm -rf /var/lib/grafana/*
sudo systemctl start grafana
```

**Note**: This will reset dashboards. Re-import from configuration.

---

## Slow Network Performance

### Symptoms

- Low throughput
- High latency
- Buffering during streaming

### Diagnosis

#### Test Throughput

```bash
# From LAN device, test to router
iperf3 -c 192.168.2.1

# From LAN device, test to Internet
curl -o /dev/null http://speedtest.tele2.net/10MB.zip
```

#### Check CPU Usage

```bash
htop
```

**If CPU >80%**: CPU bottleneck (see [High CPU Usage](#high-cpu-usage))

#### Check Hardware Offloading

```bash
sudo ethtool -k eno1 | grep offload
```

All offloads should be `on`.

#### Check MSS Clamping

```bash
sudo iptables -t mangle -L FORWARD -v -n | grep TCPMSS
```

**Expected**: `TCPMSS clamp to PMTU`

### Solutions

See [Performance Guide](performance.md) for comprehensive optimizations.

#### Quick Fixes

1. **Enable hardware offloading** (should be default)
2. **Enable BBR** (should be default)
3. **Add MSS clamping** (should be default)
4. **Set CPU governor to performance** (should be default)

Verify all optimizations:

```bash
# BBR
sysctl net.ipv4.tcp_congestion_control

# Hardware offloading
sudo ethtool -k eno1 | grep offload

# MSS clamping
sudo iptables -t mangle -L FORWARD -v -n

# CPU governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

---

## Boot Issues

### Router Won't Boot

#### Check Physical Connections

- Power cable connected
- Monitor connected (to see boot messages)
- Keyboard connected (for GRUB menu)

#### Boot from Previous Generation

1. At GRUB menu (hit Shift during boot)
2. Select "NixOS - Configuration X" (previous)
3. Boot

#### Boot from USB

1. Insert NixOS installer USB
2. Boot from USB
3. Mount and chroot (see [Updating Guide - Emergency Recovery](updating.md#emergency-recovery))
4. Roll back configuration

### Kernel Panic

**Symptoms**: System crashes during boot

**Solution**: Boot previous generation (see above)

### systemd-networkd Fails

**Symptoms**: Boot hangs waiting for network

**Solution**: Boot with `systemd.network.wait-online.enable=false` kernel parameter

---

## Secrets Not Decrypting

### Symptoms

- `error: could not decrypt secret`
- Services fail to start due to missing secrets

### Diagnosis

#### Check Age Key Exists

```bash
sudo cat /var/lib/sops-nix/key.txt
```

**If missing**: Key was deleted or not installed

#### Get Public Key

```bash
sudo grep "public key:" /var/lib/sops-nix/key.txt
```

#### Test Decryption

```bash
sops --decrypt /etc/nixos/secrets/secrets.yaml
```

**If fails**: Key doesn't match encrypted secrets

### Solutions

#### Reinstall Age Key

If you have backup of key:

```bash
sudo cp /path/to/backup/key.txt /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
```

#### Re-encrypt Secrets

If you have plaintext backup of secrets:

```bash
# Generate new key
sudo age-keygen -o /var/lib/sops-nix/key.txt

# Get public key
sudo grep "public key:" /var/lib/sops-nix/key.txt

# Re-encrypt
cd /etc/nixos
sops --encrypt --age age1yourpublickey... secrets/secrets.yaml
```

#### Lost All Keys and Secrets

You'll need to recreate secrets:

```bash
# Generate new key
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo grep "public key:" /var/lib/sops-nix/key.txt

# Create new secrets file
cat > /tmp/secrets.yaml << EOF
password: "your-new-password"
pppoe-username: "if-needed"
pppoe-password: "if-needed"
linode-api-token: "if-needed"
EOF

# Encrypt
sops --encrypt --age age1yourpublickey... /tmp/secrets.yaml > /etc/nixos/secrets/secrets.yaml
rm /tmp/secrets.yaml
```

---

## Getting Help

### Gather Information

Before asking for help, collect:

1. **System info**:
   ```bash
   nixos-version
   uname -a
   ```

2. **Relevant logs**:
   ```bash
   journalctl -xe > /tmp/logs.txt
   ```

3. **Configuration** (redact secrets!):
   ```bash
   cat /etc/nixos/router-config.nix
   ```

4. **Error messages**: Copy full error text

### Enable Debug Logging

For services:

```bash
# Blocky
journalctl -u blocky -f

# Kea
journalctl -u kea-dhcp4-server -f

# systemd-networkd
journalctl -u systemd-networkd -f
```

### Common Log Locations

```bash
# System logs
journalctl -xe

# Kernel logs
dmesg | less

# Specific service
journalctl -u <service-name>

# Boot logs
journalctl -b
```

---

## Emergency Procedures

### Complete Network Reset

If everything is broken:

```bash
# Stop all network services
sudo systemctl stop systemd-networkd blocky kea-dhcp4-server

# Reset iptables
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Restart services
sudo systemctl start systemd-networkd
sudo systemctl start blocky
sudo systemctl start kea-dhcp4-server

# Or just reboot
sudo reboot
```

### Factory Reset

To start from scratch:

```bash
# Boot from installer USB
# Mount filesystems
mount /dev/sda2 /mnt
mount /dev/sda1 /mnt/boot

# Backup config
cp -r /mnt/etc/nixos /mnt/root/nixos-backup

# Wipe and reinstall
umount -R /mnt
wipefs -a /dev/sda

# Run installer script again
curl -fsSL https://beard.click/nixos-router | sudo bash
```

---

## Still Having Issues?

If you've tried everything above and still have problems:

1. **Check GitHub Issues**: [github.com/yourusername/nixos-router/issues](https://github.com/beardedtek/nixos-router/issues)
2. **Open New Issue**: Include all info from "Getting Help" section
3. **NixOS Community**: [discourse.nixos.org](https://discourse.nixos.org)
4. **NixOS Wiki**: [nixos.wiki](https://nixos.wiki)

---

## Next Steps

- **[Performance](performance.md)** - Optimize your router
- **[Monitoring](monitoring.md)** - Use Grafana to diagnose issues
- **[Updating](updating.md)** - Keep your router up to date


