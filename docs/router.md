# Router Configuration

## Overview

This NixOS module transforms a standard PC into a full-featured network router with:

- **WAN connectivity**: DHCP, PPPoE, static IP, or PPTP
- **LAN bridging**: Multiple Ethernet ports combined into one network
- **DNS**: Blocky recursive/forwarding resolver with caching
- **DHCP**: ISC dhcpd4 handed out over the LAN bridge
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

## DNS (Blocky)

Blocky runs as the local DNS resolver/forwarder. The configuration is rendered to YAML automatically:

```nix
services.blocky = {
  enable = true;
  settings = {
    ports.dns = [
      "192.168.4.1:53"
      "127.0.0.1:53"
    ];
    upstreams.groups.default = [
      "tcp+udp:1.1.1.1"
      "tcp+udp:8.8.8.8"
    ];
    bootstrapDns = [
      "tcp+udp:1.1.1.1"
      "tcp+udp:8.8.8.8"
    ];
    caching = {
      minTime = "5m";
      maxTime = "30m";
    };
    log.level = "info";
  };
};
```

Adjust upstream resolvers or add features (blocking lists, conditional forwarding, metrics) by extending `settings`.

## DHCP (Kea DHCP4)

DHCP is served by ISC Kea. The configuration is rendered to JSON and written to `/etc/kea/dhcp4-server.conf` automatically:

```nix
services.kea.dhcp4 = {
  enable = true;
  settings = {
    interfaces-config.interfaces = [ "br0" ];
    lease-database = {
      type = "memfile";
      persist = true;
      name = "/var/lib/kea/dhcp4.leases";
    };
    valid-lifetime = 86400;
    renew-timer = 43200;
    rebind-timer = 64800;
    option-data = [
      { name = "routers"; data = "192.168.4.1"; }
      { name = "domain-name-servers"; data = "192.168.4.1"; }
      { name = "subnet-mask"; data = "255.255.255.0"; }
    ];
    subnet4 = [
      {
        id = 1;
        subnet = "192.168.4.0/24";
        pools = [
          { pool = "192.168.4.100 - 192.168.4.200"; }
        ];
      }
    ];
  };
};
```

If you change the LAN subnet or DHCP range, re-run the installer or update `router-config.nix` and rebuild. Static reservations can be defined by appending entries to `subnet4.[].reservations` in `services.kea.dhcp4.settings`.

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
systemctl status blocky
systemctl status kea-dhcp4-server

# Network interfaces
ip addr show
ip route show

# DNS logs
journalctl -u blocky -f

# DHCP leases
journalctl -u kea-dhcp4-server -f

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
   - Verify Kea is running: `systemctl status kea-dhcp4-server`
   - Check bridge configuration: `brctl show`
   - Review DHCP range in `router-config.nix` or inspect `/etc/kea/dhcp4-server.conf`

3. **DNS not resolving**
   - Verify Blocky is running: `systemctl status blocky`
   - Review logs: `journalctl -u blocky -f`
   - Inspect generated config: `cat /etc/blocky/config.yml`

4. **Port forwarding not working**
   - Verify NAT is enabled: `iptables -t nat -L`
   - Check destination host firewall
   - Confirm external port is open in firewall config
