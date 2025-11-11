# Configuration Guide

All router configuration is done through `router-config.nix`. This file is your single source of truth for router settings.

## File Location

```
/etc/nixos/router-config.nix
```

## Basic Structure

```nix
{
  # System settings
  hostname = "nixos-router";
  timezone = "America/Anchorage";
  username = "routeradmin";

  # WAN configuration
  wan = { ... };

  # LAN configuration
  lan = { ... };

  # DHCP configuration
  dhcp = { ... };

  # Port forwarding
  portForwards = [ ... ];

  # Optional features
  dyndns = { ... };
}
```

---

## System Settings

### Hostname

```nix
hostname = "my-router";
```

Sets the system hostname. Shows up in Grafana, SSH prompts, etc.

### Timezone

```nix
timezone = "America/New_York";
```

Find your timezone: [List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)

### Username

```nix
username = "admin";
```

The admin user for SSH and console access. Has passwordless sudo.

---

## WAN Configuration

### DHCP (Most Home Networks)

```nix
wan = {
  type = "dhcp";
  interface = "eno1";
};
```

Router gets IP automatically from your ISP/modem.

### PPPoE (Some ISPs)

```nix
wan = {
  type = "pppoe";
  interface = "eno1";
};
```

Requires PPPoE username/password in secrets (see [Secrets](#secrets)).

### Static IP

```nix
wan = {
  type = "static";
  interface = "eno1";
  static = {
    ipv4 = {
      address = "203.0.113.2";
      prefixLength = 24;
      gateway = "203.0.113.1";
    };
    dnsServers = [ "1.1.1.1" "8.8.8.8" ];
  };
};
```

---

## LAN Configuration

### Single Network (Simple)

```nix
lan = {
  bridges = [
    {
      name = "br0";
      interfaces = [ "enp4s0" "enp5s0" "enp6s0" "enp7s0" ];
      ipv4 = {
        address = "192.168.1.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
  ];
  isolation = false;  # No isolation with single bridge
};
```

### Multiple Networks (Advanced)

**Note**: If you installed with Simple mode, you can migrate to Advanced mode later. See [Updating Guide - Migration](updating.md#migrating-from-single-lan-to-multi-lan).

```nix
lan = {
  bridges = [
    # HOMELAB network
    {
      name = "br0";
      interfaces = [ "enp4s0" "enp5s0" ];
      ipv4 = {
        address = "192.168.2.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
    # LAN network
    {
      name = "br1";
      interfaces = [ "enp6s0" "enp7s0" ];
      ipv4 = {
        address = "192.168.3.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
  ];
  
  # Block traffic between bridges
  isolation = true;
  
  # Allow specific devices through isolation
  isolationExceptions = [
    {
      source = "192.168.3.50";  # Workstation IP
      sourceBridge = "br1";      # From LAN
      destBridge = "br0";        # To HOMELAB
      description = "Workstation access";
    }
  ];
};
```

See [Network Isolation](isolation.md) for detailed multi-LAN setup.

---

## DHCP Configuration

### Single Network

```nix
dhcp = {
  homelab = {
    interface = "br0";
    network = "192.168.1.0";
    prefix = 24;
    start = "192.168.1.100";
    end = "192.168.1.200";
    leaseTime = "24h";
    gateway = "192.168.1.1";
    dns = "192.168.1.1";
  };
};
```

### Multiple Networks

```nix
dhcp = {
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
  
  lan = {
    interface = "br1";
    network = "192.168.3.0";
    prefix = 24;
    start = "192.168.3.100";
    end = "192.168.3.200";
    leaseTime = "12h";
    gateway = "192.168.3.1";
    dns = "192.168.3.1";
  };
};
```

### DHCP Lease Time

Supported formats:
- `"3600"` - Seconds
- `"60m"` - Minutes
- `"24h"` - Hours
- `"7d"` - Days

---

## Port Forwarding

### Single Port

```nix
portForwards = [
  {
    proto = "tcp";
    externalPort = 80;
    destination = "192.168.2.10";
    destinationPort = 8080;
  }
];
```

### Port Range

```nix
portForwards = [
  {
    proto = "tcp";
    externalPort = { from = 8000; to = 8010; };
    destination = "192.168.2.10";
    destinationPort = { from = 8000; to = 8010; };
  }
];
```

### Both TCP and UDP

```nix
portForwards = [
  {
    proto = "both";
    externalPort = 443;
    destination = "192.168.2.33";
    destinationPort = 443;
  }
];
```

### Multiple Rules

```nix
portForwards = [
  # Web server
  {
    proto = "both";
    externalPort = 80;
    destination = "192.168.2.33";
    destinationPort = 80;
  }
  {
    proto = "both";
    externalPort = 443;
    destination = "192.168.2.33";
    destinationPort = 443;
  }
  # Syncthing
  {
    proto = "both";
    externalPort = 22000;
    destination = "192.168.2.33";
    destinationPort = 22000;
  }
];
```

---

## Secrets

Sensitive data (passwords, API keys) are encrypted using Age.

### Secrets File

```
/etc/nixos/secrets/secrets.yaml
```

### Editing Secrets

```bash
# Edit encrypted secrets
cd /etc/nixos
sops secrets/secrets.yaml
```

### Available Secrets

#### User Password (Required)

```yaml
password: "your-secure-password"
```

Plain text password - will be hashed automatically.

#### PPPoE Credentials (If using PPPoE)

```yaml
pppoe-username: "your-isp-username"
pppoe-password: "your-isp-password"
```

#### Linode API Token (If using DynDNS)

```yaml
linode-api-token: "your-linode-api-token"
```

---

## Applying Changes

After editing `router-config.nix`:

### Quick Update

```bash
curl -fsSL https://beard.click/nixos-router-config | sudo bash
```

### Manual Update

```bash
cd /etc/nixos
sudo nixos-rebuild switch --flake .#router
```

Changes take effect immediately (no reboot required).

---

## Configuration Examples

### Home Router (Simple)

```nix
{
  hostname = "home-router";
  timezone = "America/New_York";
  username = "admin";

  wan = {
    type = "dhcp";
    interface = "eno1";
  };

  lan = {
    bridges = [{
      name = "br0";
      interfaces = [ "enp2s0" "enp3s0" ];
      ipv4 = {
        address = "192.168.1.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }];
    isolation = false;
  };

  dhcp = {
    homelab = {
      interface = "br0";
      network = "192.168.1.0";
      prefix = 24;
      start = "192.168.1.100";
      end = "192.168.1.250";
      leaseTime = "24h";
      gateway = "192.168.1.1";
      dns = "192.168.1.1";
    };
  };

  portForwards = [];
  dyndns.enable = false;
}
```

### Advanced Multi-Network Router

See the example in the repository: `/etc/nixos/router-config.nix`

---

## Network Interface Names

To find your interface names:

```bash
# List all interfaces
ip link show

# Or just network interfaces
ls /sys/class/net/
```

Common patterns:
- `eno1`, `eno2` - Onboard ethernet
- `enp1s0`, `enp2s0` - PCI ethernet
- `wlp3s0` - Wireless (not recommended for router)

### Identifying Physical Ports

Blink the LED to identify which port is which:

```bash
# Blink enp4s0 for 10 seconds
sudo ethtool --identify enp4s0 10
```

---

## Next Steps

- **[Network Isolation](isolation.md)** - Set up isolated network segments
- **[Optional Features](optional-features.md)** - Enable DynDNS, VPN, etc.
- **[Updating](updating.md)** - Keep your configuration up to date

