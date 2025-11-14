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

### SSH Public Keys

```nix
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@laptop"
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@desktop"
];
```

Add your SSH public keys here for passwordless authentication. The router admin user will be able to login using these keys.

**How to get your SSH public key:**
- Linux/Mac: `cat ~/.ssh/id_ed25519.pub` or `cat ~/.ssh/id_rsa.pub`
- Windows: `type %USERPROFILE%\.ssh\id_ed25519.pub` or use PuTTYgen to export

**Generate a new key if needed:**
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

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

## Network Configuration (HOMELAB and LAN)

Each network has its own configuration including IP addressing, DNS domain, and DHCP settings.

### HOMELAB Network

```nix
homelab = {
  # Network settings
  ipAddress = "192.168.2.1";
  subnet = "192.168.2.0/24";
  
  # DNS settings
  domain = "homelab.local";        # Your local domain name
  primaryIP = "192.168.2.33";      # IP where *.homelab.local points to
  
  # DHCP settings
  dhcp = {
    start = "192.168.2.100";
    end = "192.168.2.200";
    leaseTime = "24h";
  };
};
```

#### DNS Entries Created

- `homelab.local` → `192.168.2.33`
- `*.homelab.local` → `192.168.2.33` (wildcard)
- `router.homelab.local` → `192.168.2.1` (router itself)

### LAN Network

```nix
lan = {
  # Network settings
  ipAddress = "192.168.3.1";
  subnet = "192.168.3.0/24";
  
  # DNS settings
  domain = "lan.local";            # Your local domain name
  primaryIP = "192.168.3.1";       # IP where *.lan.local points to
  
  # DHCP settings
  dhcp = {
    start = "192.168.3.100";
    end = "192.168.3.200";
    leaseTime = "24h";
  };
};
```

#### DNS Entries Created

- `lan.local` → `192.168.3.1`
- `*.lan.local` → `192.168.3.1` (wildcard)
- `router.lan.local` → `192.168.3.1` (router itself)

### DHCP Lease Time

Supported formats:
- `"3600"` - Seconds
- `"60m"` - Minutes
- `"24h"` - Hours
- `"7d"` - Days

---

## DNS Configuration

The router runs **Unbound** DNS resolver with ad-blocking and malware protection.

```nix
dns = {
  enable = true;
  
  # Upstream DNS servers (with DNS-over-TLS support)
  upstreamServers = [
    "1.1.1.1@853#cloudflare-dns.com"  # Cloudflare DNS over TLS
    "9.9.9.9@853#dns.quad9.net"        # Quad9 DNS over TLS
  ];
  
  # Blocklist settings
  blocklist = {
    enable = true;
    # Uses StevenBlack's unified hosts list (ads + malware)
    # Updates daily via systemd timer
  };
};
```

### Features

- **Separate DNS instances** for HOMELAB and LAN networks
- **Local domain resolution** with wildcard support
- **Ad-blocking** via daily-updated blocklists (StevenBlack hosts)
- **Privacy** via DNS-over-TLS to upstream servers
- **DNSSEC validation** for security
- **Caching** for faster responses

### Blocklist Configuration

You can enable/disable different blocklists in `router-config.nix`:

```nix
dns = {
  blocklist = {
    enable = true;
    
    lists = {
      # StevenBlack - Recommended, balanced protection
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware blocking (250K+ domains)";
      };
      
      # OISD - Low false positives
      oisd = {
        enable = false;
        url = "https://small.oisd.nl/domainswild";
        description = "Curated ads, tracking, and malware (100K+ domains)";
      };
      
      # Energized Blu - More aggressive
      energized-blu = {
        enable = false;
        url = "https://block.energized.pro/blu/formats/hosts.txt";
        description = "Balanced blocking (200K+ domains)";
      };
      
      # AdAway - Mobile-focused
      adaway = {
        enable = false;
        url = "https://adaway.org/hosts.txt";
        description = "Mobile-focused ad blocking";
      };
      
      # Phishing Army - Security
      phishing-army = {
        enable = false;
        url = "https://phishing.army/download/phishing_army_blocklist.txt";
        description = "Phishing and scam protection";
      };
    };
    
    updateInterval = "24h";  # How often to update
  };
};
```

**Popular Blocklists:**

| List | Domains | Focus | False Positives |
|------|---------|-------|-----------------|
| **StevenBlack** | ~250K | Ads + Malware | Low |
| **OISD** | ~100K | Curated | Very Low |
| **Energized Blu** | ~200K | Balanced | Medium |
| **AdAway** | ~50K | Mobile Ads | Low |
| **Phishing Army** | ~20K | Security | Very Low |

**Tips:**
- Enable multiple lists for better coverage
- Lists are combined and deduplicated automatically
- More lists = more blocking, but slightly higher chance of false positives
- Start with StevenBlack, add others as needed

### Custom Blocklists

Add your own custom blocklist:

```nix
dns = {
  blocklist = {
    lists = {
      custom = {
        enable = true;
        url = "https://example.com/my-blocklist.txt";
        description = "My custom blocklist";
      };
    };
  };
};
```

Blocklist formats supported:
- Hosts file format (`0.0.0.0 domain.com`)
- Domain list format (one domain per line)

### Upstream DNS Options

Popular options:
- `1.1.1.1@853#cloudflare-dns.com` - Cloudflare (fast, privacy-focused)
- `9.9.9.9@853#dns.quad9.net` - Quad9 (security-focused, blocks malware)
- `8.8.8.8@853#dns.google` - Google DNS (fast, reliable)
- `208.67.222.222@853#resolver1.opendns.com` - OpenDNS

The `@853#hostname` enables DNS-over-TLS for encrypted queries.

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

