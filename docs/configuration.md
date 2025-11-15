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
  
  # DHCP settings
  dhcp = {
    start = "192.168.2.100";
    end = "192.168.2.200";
    leaseTime = "24h";
    # DNS servers provided to DHCP clients (defaults to router IP if not set)
    dnsServers = [ "192.168.2.1" ];  # Unbound DNS on this network
  };
  
  # DNS settings for this network
  dns = {
    # DNS A Records
    a_records = {
      "homelab.local" = { ip = "192.168.2.33"; comment = "Main domain"; };
      "router.homelab.local" = { ip = "192.168.2.1"; comment = "Router"; };
    };
    
    # DNS CNAME Records
    cname_records = {
      "*.homelab.local" = { target = "homelab.local"; comment = "Wildcard"; };
    };
    
    # Blocklists
    blocklists = {
      enable = true;
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware blocking";
        updateInterval = "24h";
      };
    };
  };
};
```

### LAN Network

```nix
lan = {
  # Network settings
  ipAddress = "192.168.3.1";
  subnet = "192.168.3.0/24";
  
  # DHCP settings
  dhcp = {
    start = "192.168.3.100";
    end = "192.168.3.200";
    leaseTime = "24h";
    # DNS servers provided to DHCP clients (defaults to router IP if not set)
    dnsServers = [ "192.168.3.1" ];  # Unbound DNS on this network
  };
  
  # DNS settings for this network
  dns = {
    # DNS A Records
    a_records = {
      "jeandr.net" = { ip = "192.168.3.31"; comment = "Main domain"; };
      "router.jeandr.net" = { ip = "192.168.3.1"; comment = "Router"; };
    };
    
    # DNS CNAME Records
    cname_records = {
      "*.jeandr.net" = { target = "jeandr.net"; comment = "Wildcard"; };
    };
    
    # Blocklists (different from homelab)
    blocklists = {
      enable = true;
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware blocking";
      };
      energized-blu = {
        enable = true;
        url = "https://block.energized.pro/blu/formats/hosts.txt";
        description = "Balanced blocking";
        updateInterval = "48h";
      };
    };
  };
};
```

### Advanced DNS Examples

#### Using Real Domains

You can use real domains you own:

```nix
lan = {
  ipAddress = "192.168.3.1";
  subnet = "192.168.3.0/24";
  
  dns = {
    a_records = {
      "jeandr.net" = { ip = "192.168.3.31"; comment = "Main domain"; };
      "router.jeandr.net" = { ip = "192.168.3.1"; comment = "Router"; };
      "server.jeandr.net" = { ip = "192.168.3.50"; comment = "Server"; };
    };
    
    cname_records = {
      "*.jeandr.net" = { target = "jeandr.net"; comment = "Wildcard"; };
      "www.jeandr.net" = { target = "server.jeandr.net"; comment = "Web"; };
    };
  };
};
```

#### Multiple Aliases

Create multiple CNAME aliases pointing to the same host:

```nix
homelab = {
  dns = {
    a_records = {
      "server.homelab.local" = { ip = "192.168.2.50"; comment = "Main server"; };
    };
    
    cname_records = {
      "www.homelab.local" = { target = "server.homelab.local"; comment = "Web"; };
      "app.homelab.local" = { target = "server.homelab.local"; comment = "Application"; };
      "api.homelab.local" = { target = "server.homelab.local"; comment = "API"; };
    };
  };
};
```

All three aliases (`www`, `app`, `api`) will resolve to the same IP (192.168.2.50).

#### Master Blocklist Switch

Quickly disable all blocking for a network:

```nix
homelab = {
  dns = {
    blocklists = {
      enable = false;  # Disable ALL blocking
      
      # Lists remain defined and ready to re-enable
      stevenblack = { enable = true; url = "..."; };
    };
  };
};
```

#### Benefits of This Approach

✅ **Self-contained** - Each network's complete DNS config in one place  
✅ **Independent** - HOMELAB and LAN don't affect each other  
✅ **Clear structure** - Easy to see all DNS records at a glance  
✅ **Self-documenting** - Comments explain what each record is for  
✅ **Type-safe** - NixOS validates the structure  
✅ **Full domain names** - Use any domain you want, not just subdomains  
✅ **Flexible** - Mix A and CNAME records as needed  
✅ **Version controlled** - All DNS in one config file  

### DHCP DNS Servers

Configure which DNS servers are provided to DHCP clients:

```nix
homelab = {
  dhcp = {
    dnsServers = [ "192.168.2.1" ];  # Send router IP (Unbound)
  };
};
```

**Options:**
- **Router DNS (recommended)**: `[ "192.168.2.1" ]` - Clients use Unbound with ad-blocking
- **External DNS**: `[ "1.1.1.1", "8.8.8.8" ]` - Bypass router DNS entirely
- **Multiple servers**: `[ "192.168.2.1", "1.1.1.1" ]` - Primary and fallback
- **Default**: If not specified, defaults to the router's IP address for that network

**Why use router DNS?**
- ✅ Ad-blocking and malware protection (via Unbound blocklists)
- ✅ Local DNS records work (e.g., `jeandr.net`)
- ✅ Privacy via DNS-over-TLS to upstream servers

### DHCP Lease Time

Supported formats:
- `"3600"` - Seconds
- `"60m"` - Minutes
- `"24h"` - Hours
- `"7d"` - Days

### Static DHCP Reservations

Assign fixed IP addresses to specific devices based on their MAC address:

```nix
homelab = {
  dhcp = {
    start = "192.168.2.100";
    end = "192.168.2.200";
    leaseTime = "24h";
    dnsServers = [ "192.168.2.1" ];
    
    # Static reservations
    reservations = [
      {
        hostname = "hera";
        hwAddress = "00:11:22:33:44:55";
        ipAddress = "192.168.2.33";
      }
      {
        hostname = "triton";
        hwAddress = "aa:bb:cc:dd:ee:ff";
        ipAddress = "192.168.2.31";
      }
    ];
  };
};
```

#### 🎉 Automatic DNS Integration

**DHCP reservations automatically create DNS A records in Unbound!**

The router automatically generates DNS entries for all DHCP reservations. For example, the reservation above automatically creates:

```
hera.jeandr.net → 192.168.2.33
triton.jeandr.net → 192.168.2.31
```

**How it works:**
1. Router extracts the base domain from your existing DNS A records (e.g., `jeandr.net` from `router.jeandr.net`)
2. For each DHCP reservation, creates: `hostname.domain → IP`
3. Merges with manually defined A records (manual overrides DHCP if same hostname)

**Benefits:**
- ✅ **No duplication** - Define hostname and IP once
- ✅ **Automatic sync** - Change IP in DHCP, DNS updates automatically  
- ✅ **Consistent naming** - DHCP and DNS always match
- ✅ **Still flexible** - Manual A records can override if needed

**Example:**

```nix
homelab = {
  dns = {
    a_records = {
      "jeandr.net" = { ip = "192.168.2.33"; comment = "Main domain"; };
      "router.jeandr.net" = { ip = "192.168.2.1"; comment = "Router"; };
    };
    cname_records = {
      "*.jeandr.net" = { target = "jeandr.net"; comment = "Wildcard"; };
    };
  };
  
  dhcp = {
    reservations = [
      { hostname = "hera"; hwAddress = "..."; ipAddress = "192.168.2.33"; }
      { hostname = "triton"; hwAddress = "..."; ipAddress = "192.168.2.31"; }
      { hostname = "nas"; hwAddress = "..."; ipAddress = "192.168.2.40"; }
    ];
  };
};
```

**Automatic DNS entries created:**
- `hera.jeandr.net` → 192.168.2.33 (DHCP reservation)
- `triton.jeandr.net` → 192.168.2.31 (DHCP reservation)
- `nas.jeandr.net` → 192.168.2.40 (DHCP reservation)

**Combined with manual A records, you get:**
- `jeandr.net` → 192.168.2.33 (manual A record)
- `router.jeandr.net` → 192.168.2.1 (manual A record)
- `hera.jeandr.net` → 192.168.2.33 (auto-generated from DHCP)
- `triton.jeandr.net` → 192.168.2.31 (auto-generated from DHCP)
- `nas.jeandr.net` → 192.168.2.40 (auto-generated from DHCP)
- `anything-else.jeandr.net` → 192.168.2.33 (wildcard CNAME)

**Override behavior:**

If you need a different DNS entry for the same hostname, manual A records take precedence:

```nix
dns = {
  a_records = {
    "hera.jeandr.net" = { ip = "192.168.2.100"; comment = "Different IP for DNS"; };
  };
};

dhcp = {
  reservations = [
    { hostname = "hera"; hwAddress = "..."; ipAddress = "192.168.2.33"; }  # DHCP gets .33
  ];
};
```

Result:
- DHCP: hera gets IP 192.168.2.33
- DNS: hera.jeandr.net resolves to 192.168.2.100 (manual override)

**How to find MAC addresses:**
- **Linux**: `ip link show` or `ifconfig`
- **Windows**: `ipconfig /all`
- **Router**: Check DHCP leases at `http://router-ip:3000` (Grafana dashboard)

**Best practices:**
- ✅ Reserve IPs **outside** the DHCP pool range
- ✅ Use descriptive hostnames
- ✅ Keep a backup list of MAC addresses
- ⚠️ Make sure reserved IPs are in the subnet (e.g., 192.168.2.x for HOMELAB)

**Example configuration:**
```nix
# HOMELAB: Servers with static IPs (192.168.2.10-50)
homelab = {
  dhcp = {
    start = "192.168.2.100";  # Dynamic range starts at 100
    end = "192.168.2.200";
    
    reservations = [
      { hostname = "server1"; hwAddress = "00:11:22:33:44:55"; ipAddress = "192.168.2.10"; }
      { hostname = "server2"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.2.11"; }
      { hostname = "nas"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.2.20"; }
    ];
  };
};

# LAN: Workstations with static IPs
lan = {
  dhcp = {
    start = "192.168.3.100";
    end = "192.168.3.200";
    
    reservations = [
      { hostname = "workstation"; hwAddress = "aa:11:bb:22:cc:33"; ipAddress = "192.168.3.50"; }
      { hostname = "laptop"; hwAddress = "bb:22:cc:33:dd:44"; ipAddress = "192.168.3.51"; }
    ];
  };
};
```

---

## DNS Configuration

The router runs **Unbound** DNS resolver with ad-blocking and malware protection.

DNS configuration is **per-network** - each network (HOMELAB and LAN) has its own DNS settings, allowing complete independence:

```nix
# Global DNS settings
dns = {
  enable = true;
  upstreamServers = [
    "1.1.1.1@853#cloudflare-dns.com"
    "9.9.9.9@853#dns.quad9.net"
  ];
};

# HOMELAB DNS configuration
homelab = {
  ipAddress = "192.168.2.1";
  subnet = "192.168.2.0/24";
  
  dns = {
    a_records = {
      "homelab.local" = { ip = "192.168.2.33"; comment = "Main domain"; };
      "router.homelab.local" = { ip = "192.168.2.1"; comment = "Router"; };
      "server.homelab.local" = { ip = "192.168.2.50"; comment = "Server"; };
    };
    
    cname_records = {
      "*.homelab.local" = { target = "homelab.local"; comment = "Wildcard"; };
      "www.homelab.local" = { target = "server.homelab.local"; comment = "Web"; };
    };
    
    blocklists = {
      enable = true;
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware";
        updateInterval = "24h";
      };
    };
  };
};

# LAN DNS configuration
lan = {
  ipAddress = "192.168.3.1";
  subnet = "192.168.3.0/24";
  
  dns = {
    a_records = {
      "lan.local" = { ip = "192.168.3.1"; comment = "Main domain"; };
      "router.lan.local" = { ip = "192.168.3.1"; comment = "Router"; };
    };
    
    cname_records = {
      "*.lan.local" = { target = "lan.local"; comment = "Wildcard"; };
    };
    
    blocklists = {
      enable = true;
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware";
      };
      energized-blu = {
        enable = true;
        url = "https://block.energized.pro/blu/formats/hosts.txt";
        description = "Balanced blocking";
        updateInterval = "48h";
      };
    };
  };
};
```

### DNS Record Types

**A Records** - Map hostnames to IP addresses:
- Use the full domain name as the key
- Specify the IP address
- Add comments for documentation

**CNAME Records** - Create aliases:
- Point one domain to another
- Use for wildcards (e.g., `*.homelab.local`)
- Use for convenient aliases (e.g., `www` → `server`)

### Example DNS Resolution

From the config above:
- `homelab.local` → `192.168.2.33` (A record)
- `server.homelab.local` → `192.168.2.50` (A record)
- `www.homelab.local` → `server.homelab.local` → `192.168.2.50` (CNAME → A)
- `anything.homelab.local` → `homelab.local` → `192.168.2.33` (wildcard CNAME → A)

### Features

- **Per-network DNS configuration** - Each network has its own independent DNS settings
- **Separate DNS instances** - HOMELAB and LAN run isolated Unbound resolvers
- **Local domain resolution** - Full support for A and CNAME records with wildcards
- **Independent blocklists** - Each network can have different ad-blocking lists
- **Per-blocklist update intervals** - Control how often each list updates
- **Master enable switch** - Disable all blocking for a network with one flag
- **Privacy** - DNS-over-TLS to upstream servers (Cloudflare, Quad9)
- **DNSSEC validation** - Built-in security
- **Caching** - Faster DNS responses

### Blocklist Configuration

Each network has its own blocklist configuration:

```nix
homelab = {
  dns = {
    blocklists = {
      enable = true;  # Master switch
      
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware blocking (250K+ domains)";
        updateInterval = "24h";  # Optional: defaults to 24h
      };
      
      phishing-army = {
        enable = true;
        url = "https://phishing.army/download/phishing_army_blocklist.txt";
        description = "Phishing and scam protection";
        updateInterval = "12h";  # More frequent for security
      };
    };
  };
};

lan = {
  dns = {
    blocklists = {
      enable = true;  # Master switch
      
      stevenblack = {
        enable = true;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware blocking";
      };
      
      energized-blu = {
        enable = true;
        url = "https://block.energized.pro/blu/formats/hosts.txt";
        description = "Balanced blocking (200K+ domains)";
        updateInterval = "48h";  # Less frequent
      };
      
      adaway = {
        enable = true;
        url = "https://adaway.org/hosts.txt";
        description = "Mobile ad blocking";
        updateInterval = "1w";  # Weekly
      };
    };
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

### Whitelist (Unblocking Domains)

Sometimes legitimate domains get caught by blocklists (false positives). Use the whitelist to override blocklists:

```nix
homelab = {
  dns = {
    blocklists = {
      enable = true;
      stevenblack.enable = true;
    };
    
    # Whitelist - these domains will NEVER be blocked
    whitelist = [
      "example.com"
      "cdn.example.com"
      "tracking.legitimateservice.com"
    ];
  };
};
```

**How it works:**
- Whitelist is checked **before** blocklists
- Uses Unbound's `transparent` zone type - resolves normally
- Applies per-network (HOMELAB and LAN can have different whitelists)

**Common use cases:**
- CDNs that serve both ads and content
- Analytics services you need to work
- Domains incorrectly categorized by blocklists
- Testing - temporarily whitelist to see if blocking is causing issues

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

