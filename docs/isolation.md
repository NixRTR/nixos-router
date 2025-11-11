# Network Isolation

Network isolation allows you to segment your network into separate security zones that cannot directly communicate with each other.

## Why Use Network Isolation?

**Security**: Keep untrusted IoT devices away from sensitive servers.

**Organization**: Separate work/home, guest/private, etc.

**Performance**: Reduce broadcast traffic by segmenting networks.

**Compliance**: Meet regulatory requirements for data segregation.

---

## Architecture Overview

```
Internet
   │
   ▼
[Router/Firewall]
   │
   ├──▶ [br0] HOMELAB (192.168.2.0/24)
   │     • Servers (Hera, Triton)
   │     • IoT devices
   │     • Smart home hub
   │
   └──▶ [br1] LAN (192.168.3.0/24)
         • Workstations
         • Phones/tablets
         • Guest devices
```

With isolation enabled:
- ✅ HOMELAB can access Internet
- ✅ LAN can access Internet
- ❌ HOMELAB cannot access LAN
- ❌ LAN cannot access HOMELAB
- ⚙️ Exceptions can be configured

---

## Basic Multi-Network Setup

### 1. Define Multiple Bridges

Edit `router-config.nix`:

```nix
lan = {
  bridges = [
    # First network (HOMELAB)
    {
      name = "br0";
      interfaces = [ "enp4s0" "enp5s0" ];  # Physical ports
      ipv4 = {
        address = "192.168.2.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
    # Second network (LAN)
    {
      name = "br1";
      interfaces = [ "enp6s0" "enp7s0" ];  # Different physical ports
      ipv4 = {
        address = "192.168.3.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
  ];
  
  # Enable isolation between bridges
  isolation = true;
};
```

### 2. Configure DHCP for Each Network

```nix
dhcp = {
  # HOMELAB DHCP
  homelab = {
    interface = "br0";
    network = "192.168.2.0";
    prefix = 24;
    start = "192.168.2.100";
    end = "192.168.2.200";
    leaseTime = "24h";
    gateway = "192.168.2.1";
    dns = "192.168.2.1";
  };
  
  # LAN DHCP
  lan = {
    interface = "br1";
    network = "192.168.3.0";
    prefix = 24;
    start = "192.168.3.100";
    end = "192.168.3.200";
    leaseTime = "24h";
    gateway = "192.168.3.1";
    dns = "192.168.3.1";
  };
};
```

### 3. Apply Configuration

```bash
curl -fsSL https://beard.click/nixos-router-config | sudo bash
```

---

## How Isolation Works

### Firewall Rules

When `isolation = true`, the router creates iptables rules:

```bash
# Block br0 → br1
iptables -A FORWARD -i br0 -o br1 -j DROP

# Block br1 → br0
iptables -A FORWARD -i br1 -o br0 -j DROP
```

### What's Still Allowed

- ✅ All networks can access the Internet (WAN)
- ✅ All networks can access the router itself (DNS, DHCP, Grafana)
- ✅ Devices within the same network can communicate
- ❌ Devices on different networks cannot communicate

### Verification

Test from a device on br1 (LAN):

```bash
# This should work (router)
ping 192.168.3.1

# This should fail (br0)
ping 192.168.2.1
timeout

# This should work (Internet)
ping 1.1.1.1
```

---

## Isolation Exceptions

Allow specific devices to bypass isolation.

### Use Cases

- **Admin workstation** needs access to servers
- **Media server** on HOMELAB serves content to LAN devices
- **Backup system** backs up devices on multiple networks
- **Printer/scanner** shared between networks

### Configuration

```nix
lan = {
  # ... bridges configuration ...
  
  isolation = true;
  
  isolationExceptions = [
    {
      source = "192.168.3.50";       # Specific IP on source network
      sourceBridge = "br1";           # From which network
      destBridge = "br0";             # To which network
      description = "Admin workstation";
    }
  ];
};
```

### How It Works

The router inserts **ACCEPT** rules **before** the DROP rules:

```bash
# Exception: Allow 192.168.3.50 → br0
iptables -I FORWARD -s 192.168.3.50 -i br1 -o br0 -j ACCEPT
# Allow return traffic
iptables -I FORWARD -d 192.168.3.50 -i br0 -o br1 -j ACCEPT

# Then apply blocking rules for everyone else
iptables -A FORWARD -i br1 -o br0 -j DROP
iptables -A FORWARD -i br0 -o br1 -j DROP
```

### Multiple Exceptions

```nix
isolationExceptions = [
  # Workstation full access to HOMELAB
  {
    source = "192.168.3.50";
    sourceBridge = "br1";
    destBridge = "br0";
    description = "Workstation → HOMELAB";
  }
  # Printer accessible from HOMELAB
  {
    source = "192.168.2.100";
    sourceBridge = "br0";
    destBridge = "br1";
    description = "Printer → LAN";
  }
];
```

### Static IP Required

Exceptions require **static IPs**. Configure on the device or use DHCP reservations.

#### DHCP Reservation (Kea)

For static-like behavior, edit `/etc/nixos/configuration.nix` and add:

```nix
services.kea.dhcp4.settings = {
  # ... existing config ...
  
  subnet4 = [
    {
      subnet = "192.168.3.0/24";
      pools = [{ pool = "192.168.3.100 - 192.168.3.200"; }];
      
      # Reservations
      reservations = [
        {
          hw-address = "aa:bb:cc:dd:ee:ff";  # Device MAC address
          ip-address = "192.168.3.50";
          hostname = "workstation";
        }
      ];
    }
  ];
};
```

Find MAC address on Linux: `ip link show`
Find MAC address on Windows: `ipconfig /all`

---

## Advanced Scenarios

### Three Network Setup

```nix
lan = {
  bridges = [
    { name = "br0"; /* HOMELAB */ }
    { name = "br1"; /* LAN */ }
    { name = "br2"; /* GUEST */ }
  ];
  isolation = true;
  
  isolationExceptions = [
    # Allow HOMELAB server to reach LAN printer
    {
      source = "192.168.2.10";
      sourceBridge = "br0";
      destBridge = "br1";
      description = "Server → LAN printer";
    }
  ];
};
```

All three networks are isolated. GUEST has no exceptions (maximum security).

### Bidirectional Access

If you need **full bidirectional** access between two devices:

```nix
isolationExceptions = [
  # Workstation → Server
  {
    source = "192.168.3.50";
    sourceBridge = "br1";
    destBridge = "br0";
    description = "Workstation can access servers";
  }
  # Server → Workstation (if server needs to initiate)
  {
    source = "192.168.2.10";
    sourceBridge = "br0";
    destBridge = "br1";
    description = "Server can access workstation";
  }
];
```

**Note**: The first exception allows return traffic automatically. The second is only needed if the server initiates connections.

### Subnet-Wide Exception (Not Recommended)

To allow an entire subnet (less secure):

You would need to use iptables CIDR notation, but this is not currently supported in the config. Instead, add manual firewall rules:

Edit `/etc/nixos/configuration.nix`:

```nix
networking.firewall.extraCommands = ''
  # Allow entire LAN subnet to access HOMELAB
  iptables -I FORWARD -s 192.168.3.0/24 -i br1 -o br0 -j ACCEPT
  iptables -I FORWARD -d 192.168.3.0/24 -i br0 -o br1 -j ACCEPT
'';
```

---

## Dual-Homed Servers

If you have servers with NICs on **both networks** (like Hera and Triton), they can bridge the networks at Layer 2.

### Configuration on Server (Example)

```bash
# On Hera/Triton - bridge both networks
ip link add name br-dual type bridge
ip link set eno1 master br-dual  # LAN interface
ip link set eno2 master br-dual  # HOMELAB interface
ip link set br-dual up
```

**Security Note**: This bypasses router isolation! Only do this on **trusted** servers.

### Router Perspective

From the router's view, Hera/Triton are two separate devices:
- `192.168.2.10` (HOMELAB side)
- `192.168.3.10` (LAN side)

The router still blocks cross-network traffic, but Hera routes traffic internally.

---

## Troubleshooting Isolation

### Test Connectivity

From a LAN device (192.168.3.x):

```bash
# Should FAIL (isolation working)
ping 192.168.2.1
timeout

# Should WORK (internet access)
ping 1.1.1.1
64 bytes from 1.1.1.1: icmp_seq=1 ttl=57
```

### Check Firewall Rules

On the router:

```bash
# View FORWARD chain
sudo iptables -L FORWARD -v -n

# Should see:
# ACCEPT  all  --  br1  br0  192.168.3.50  0.0.0.0/0  (exception)
# DROP    all  --  br1  br0  0.0.0.0/0     0.0.0.0/0  (blocking)
```

### Exception Not Working

1. **Verify static IP**:
   ```bash
   # On device
   ip addr show
   ```

2. **Check firewall rules order** (exceptions must be BEFORE drops):
   ```bash
   sudo iptables -L FORWARD -n --line-numbers
   ```

3. **Test from correct IP**:
   Exception for `192.168.3.50` won't work from `192.168.3.51`!

4. **Verify bridges**:
   ```bash
   ip link show br0
   ip link show br1
   ```

### Can't Reach Router

If you can't access the router from a network:

```bash
# Check router IPs
ip addr show br0
ip addr show br1

# Check DNS/DHCP
systemctl status pdns-recursor powerdns
systemctl status kea-dhcp4-server
```

Router should always be reachable from all networks (trusted interfaces).

---

## Best Practices

### 1. Plan Your Networks

Before configuring:
- List all devices
- Group by trust level
- Determine which need cross-network access

### 2. Use Descriptive Names

```nix
isolationExceptions = [
  {
    description = "John's laptop → NAS (Plex access)";
    # ...
  }
];
```

### 3. Document IP Assignments

Keep a spreadsheet/document of static IPs and their purposes.

### 4. Test Thoroughly

After changes:
- ✅ Can each network reach Internet?
- ✅ Can devices reach their gateway?
- ✅ Are isolation rules working?
- ✅ Do exceptions work as expected?

### 5. Monitor Traffic

Use Grafana to watch for unexpected traffic patterns:
- `http://192.168.2.1:3000` (or your router IP)

---

## Security Considerations

### Defense in Depth

Network isolation is **one layer** of security. Also use:
- Firewalls on individual devices
- VLANs for physical separation (if supported)
- Strong passwords and authentication
- Regular updates

### IoT Device Isolation

Recommended: Put all IoT devices on isolated network (e.g., br0) with **no exceptions**. Control via:
- Home Assistant on the same network
- Cloud apps from LAN (Internet → IoT)

### Guest Network

Create a separate bridge for guests:

```nix
lan = {
  bridges = [
    { name = "br0"; /* HOMELAB */ }
    { name = "br1"; /* LAN */ }
    { name = "br2"; /* GUEST */ }
  ];
  isolation = true;
  isolationExceptions = [];  # No exceptions for guests!
};
```

---

## Next Steps

- **[Configuration Guide](configuration.md)** - Full configuration reference
- **[Monitoring](monitoring.md)** - Watch network traffic in Grafana
- **[Performance](performance.md)** - Optimize for multi-network setups


