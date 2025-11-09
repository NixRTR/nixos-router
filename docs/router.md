# Router Configuration

## Overview

This NixOS module transforms a standard PC into a full-featured network router with:

- **WAN connectivity**: DHCP, PPPoE, static IP, or PPTP
- **LAN bridging**: Multiple Ethernet ports combined into one network
- **DHCP & DNS**: Technitium DNS Server with integrated DHCP service
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

## DNS & DHCP (Technitium)

Technitium DNS Server replaces dnsmasq and provides both DNS resolution and DHCP leases. By default the module binds to the LAN bridge address and serves the DHCP range defined in `router-config.nix`.

### Basic Configuration
```nix
router = {
  technitium = {
    enable = true;
    upstreamServers = [ "1.1.1.1" "1.0.0.1" ];
    dhcp = {
      dnsServers = [ "192.168.1.1" ];
      leaseTime = "24h";
    };
  };
};
```

### Advanced Options
```nix
router = {
  technitium = {
    enableDoT = true;
    enableDoH = true;
    enableHttps = true;
    ports = {
      web = 5380;
      webTls = 53443;
      dot = 853;
      doh = 5443;
    };
    listenAddresses = [ "192.168.1.1" "127.0.0.1" ];
    upstreamServers = [ "8.8.8.8" "9.9.9.9" ];
    dhcp = {
      interfaces = [ "br0" ];
      dnsServers = [ "192.168.1.1" "8.8.8.8" ];
      leaseTime = "12h";
    };
    extraSettings = {
      "EnableSecureDns" = true;
    };
  };
};
```

Technitium exposes a web console on `http://<router-ip>:5380` by default (HTTPS and DoH endpoints require enabling `enableHttps`/`enableDoH`). You can use the UI to manage static DHCP leases and additional DNS features.

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
journalctl -u technitium-dns-server -f

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
   - Verify Technitium is running: `systemctl status technitium-dns-server`
   - Check bridge configuration: `brctl show`
   - Review DHCP range in `router-config.nix` or in the Technitium UI

3. **Port forwarding not working**
   - Verify NAT is enabled: `iptables -t nat -L`
   - Check destination host firewall
   - Confirm external port is open in firewall config
