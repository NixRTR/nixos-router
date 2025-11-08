# Router Configuration

## Overview

This NixOS module transforms a standard PC into a full-featured network router with:

- **WAN connectivity**: DHCP, PPPoE, static IP, or PPTP
- **LAN bridging**: Multiple Ethernet ports combined into one network
- **DHCP & DNS**: dnsmasq for automatic IP assignment and name resolution
- **NAT & firewall**: Automatic masquerading and basic security rules
- **Port forwarding**: Configurable port forwarding rules

## WAN Configuration

### DHCP (Default)
```nix
router = {
  enable = true;
  wan = {
    type = "dhcp";
    interface = "enp1s0";  # Your WAN interface
  };
};
```

### PPPoE
```nix
router = {
  enable = true;
  wan = {
    type = "pppoe";
    interface = "enp1s0";
    pppoe = {
      user = "/run/secrets/pppoe-username";
      passwordFile = "/run/secrets/pppoe-password";
      service = null;  # Optional service name
      ipv6 = false;    # Enable IPv6 negotiation
    };
  };
};
```

### Static IP
```nix
router = {
  enable = true;
  wan = {
    type = "static";
    interface = "enp1s0";
    static = {
      ipv4 = {
        address = "203.0.113.2";
        prefixLength = 24;
        gateway = "203.0.113.1";
      };
      dnsServers = [ "8.8.8.8" "1.1.1.1" ];
    };
  };
};
```

## LAN Configuration

### Basic Bridge Setup
```nix
router = {
  lan = {
    bridge = {
      name = "br0";  # Bridge interface name
      interfaces = [ "enp2s0" "enp3s0" "enp4s0" "enp5s0" ];  # LAN ports
    };
    ipv4 = {
      address = "192.168.1.1";  # Router IP
      prefixLength = 24;       # Subnet mask
    };
  };
};
```

### DHCP Configuration
```nix
router = {
  dnsmasq = {
    enable = true;
    rangeStart = "192.168.1.100";  # First IP in DHCP pool
    rangeEnd = "192.168.1.200";    # Last IP in DHCP pool
    leaseTime = "24h";             # Lease duration
  };
};
```

## Firewall & Security

### Basic Firewall
```nix
router = {
  firewall = {
    allowPing = true;           # Allow ICMP echo requests
    allowedTCPPorts = [ 22 80 443 ];  # Open ports on LAN
    allowedUDPPorts = [ 53 67 68 ];  # DNS and DHCP
  };
};
```

### Port Forwarding
```nix
router = {
  portForwards = [
    {
      proto = "tcp";
      externalPort = 80;
      destination = "192.168.1.10";
      destinationPort = 80;
    }
    {
      proto = "both";  # TCP and UDP
      externalPort = 443;
      destination = "192.168.1.10";
      destinationPort = 443;
    }
  ];
};
```

## Advanced Features

### Static DHCP Leases
```nix
router = {
  dnsmasq = {
    staticLeases = [
      {
        mac = "aa:bb:cc:dd:ee:ff";
        ip = "192.168.1.50";
        hostname = "server";  # Optional
      }
    ];
  };
};
```

### Custom dnsmasq Settings
```nix
router = {
  dnsmasq = {
    extraSettings = {
      "log-queries" = true;
      "local" = "/local/";
    };
  };
};
```

## Interface Naming

NixOS uses predictable interface names. Common patterns:

- **Ethernet**: `enpXsY` (PCI bus)
- **USB Ethernet**: `enX` (USB bus)
- **Wireless**: `wlpXsY`

Use `ip link` or `nmcli device` to identify your interfaces.

## Monitoring

Check router status with these commands:

```bash
# Router services
systemctl status router-*

# Network interfaces
ip addr show
ip route show

# DHCP leases
journalctl -u dnsmasq -f

# PPPoE connection
systemctl status pppd
ip addr show ppp0
```

## Troubleshooting

### Common Issues

1. **No internet connectivity**
   - Check WAN interface: `ip addr show <wan-interface>`
   - Verify PPPoE credentials
   - Check routes: `ip route`

2. **Clients can't get IP addresses**
   - Verify dnsmasq is running: `systemctl status dnsmasq`
   - Check bridge configuration: `brctl show`
   - Review DHCP range in configuration

3. **Port forwarding not working**
   - Verify NAT is enabled: `iptables -t nat -L`
   - Check destination host firewall
   - Confirm external port is open in firewall config
