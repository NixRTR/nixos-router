# Documentation

This project is a NixOS router configuration. Everything is controlled through `router-config.nix`` in the repository root.

## Installation

### Using the install script *-- RECOMMENDED --*

Run from a vanilla NixOS installer shell:
Please take time to inspect this installer script.  It is ***never*** recommended to blindly run scripts from the internet.

```bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

#### What does it do?

- Downloads, makes executable and runs [/scripts/install-router.sh](../scripts/install-router.sh)
  - Clones this repository
  - Asks for user input with sane defaults to generate your router-config.nix
  - Builds the system

### Using the custom ISO

**NOTE:** This script fetches everything via Nix; expect a large download on the first run.

1. Build the ISO:

   ```bash
   cd iso
   ./build-iso.sh
   ```



2. Write `result/iso/*.iso` to a USB drive.
3. (Optional) Place your `router-config.nix` inside the USB `config/` folder for unattended installs.
4. Boot the router from USB and follow the menu. Pick install or upgrade.
5. After completion, reboot and remove the USB stick.



## Upgrading


### With the script

1. Boot any Linux shell with internet access on the router (local console or SSH).
2. Re-run the script:

   ```bash
   curl -fsSL https://beard.click/nixos-router > install.sh
   chmod +x install.sh
   sudo ./install.sh
   ```

   Choose the upgrade option when prompted. The script pulls the latest commits and rebuilds the system.

## Verify System Operation

### Basic System Verification

```bash
# Check NixOS version
sudo nixos-version

# Verify system configuration is valid
sudo nixos-rebuild dry-run --flake /etc/nixos#router

# Check for failed systemd services
sudo systemctl --failed

# Check system health
sudo systemctl status
```

### Router-Specific Services

```bash
# WebUI Backend (main service)
sudo systemctl status router-webui-backend.service

# PostgreSQL (required for WebUI)
sudo systemctl status postgresql.service

# Kea DHCP servers (check both networks if configured)
sudo systemctl status kea-dhcp4-homelab.service
sudo systemctl status kea-dhcp4-lan.service

# Unbound DNS servers (check both networks if configured)
sudo systemctl status unbound-homelab.service
sudo systemctl status unbound-lan.service

# Dynamic DNS (if enabled)
sudo systemctl status linode-dyndns.service
sudo systemctl status linode-dyndns-on-wan-up.service

# Speedtest monitoring (if enabled)
sudo systemctl status speedtest.service
sudo systemctl status speedtest-on-wan-up.service
```

### Verify Network Connectivity

```bash
# Check WAN interface is up
ip addr show eno1  # or your WAN interface
ip link show eno1

# Check PPPoE connection (if using PPPoE)
ip addr show ppp0
sudo systemctl status pppoe-connection.service

# Check bridge interfaces
ip addr show br0
ip addr show br1  # if using multi-bridge mode

# Verify routing table
ip route show

# Check NAT is working
sudo nft list ruleset | grep -A 10 "nat"

# Test internet connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com
```

### Verify DNS

```bash
# Test DNS resolution
dig @192.168.2.1 router.jeandr.net  # HOMELAB DNS
dig @192.168.3.1 router.jeandr.net  # LAN DNS

# Check DNS is listening
sudo ss -tlnp | grep :53

# Test DNS from a client
# (from a device on the network)
nslookup router.jeandr.net 192.168.2.1
```

### Verify DHCP

```bash
# Check DHCP leases file exists and has entries
sudo cat /var/lib/kea/dhcp4.leases | tail -20

# Verify DHCP is listening
sudo ss -ulnp | grep :67

# Test DHCP from a client
# (release and renew on a client device)
```

### Verify WebUI

```bash
# Check WebUI is accessible
curl -I http://localhost:8080
# or from a client:
curl -I http://192.168.2.1:8080  # or your router IP

# Check WebUI logs for errors
sudo journalctl -u router-webui-backend.service -n 50 --no-pager

# Verify database connection
sudo -u router-webui psql -h localhost -U router_webui -d router_webui -c "SELECT COUNT(*) FROM system_metrics;"
```

### Verify Firewall and Port Forwarding

```bash
# Verify nftables rules are loaded
sudo nft list ruleset

# Check port forwarding rules
sudo nft list chain inet router port_forward

# Test port forwarding (from external network)
# telnet your-public-ip 443
```

## router-config.nix format

The file is plain Nix. Adjust the attributes below and rebuild with `sudo nixos-rebuild switch --flake /etc/nixos#router`.

### System Settings

Top-level system configuration:

```nix
{
  hostname = "nixos-router";        # Router hostname
  domain = "example.com";           # Search domain for /etc/resolv.conf
  timezone = "America/Anchorage";    # Olson timezone string
  username = "routeradmin";         # Local admin account name
  
  nameservers = [ "1.1.1.1" "9.9.9.9" ];  # DNS servers for router itself
  
  sshKeys = [
    # SSH public keys for the admin user
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
  ];
}
```

### WAN Configuration

WAN (Internet) connection settings:

```nix
wan = {
  type = "dhcp" | "pppoe";  # Connection type
  interface = "eno1";        # Physical WAN interface name
};
```

- `type`: `"dhcp"` for most home networks, `"pppoe"` for DSL connections requiring authentication
- `interface`: Physical network interface connected to your ISP (use `ip link show` to find)

### LAN Bridges Configuration

First `lan` section defines bridge interfaces. This section configures the physical network bridges:

```nix
lan = {
  bridges = [
    {
      name = "br0";                    # Bridge name
      interfaces = [ "enp4s0" "enp5s0" ];  # Physical NICs in this bridge
      ipv4 = {
        address = "192.168.2.1";        # Router IP on this bridge
        prefixLength = 24;             # Subnet prefix length
      };
      ipv6.enable = false;             # Set to true to enable IPv6
    }
    # Add more bridges as needed (br1, br2, etc.)
  ];
  
  isolation = true;  # Block traffic between bridges at router level
  
  isolationExceptions = [
    # Allow specific devices to bypass isolation
    {
      source = "192.168.3.101";      # Source IP address
      sourceBridge = "br1";            # Source bridge name
      destBridge = "br0";              # Destination bridge name
      description = "Workstation access to HOMELAB";
    }
  ];
};
```

- `bridges`: Array of bridge definitions. Each bridge groups physical interfaces together.
- `isolation`: When `true`, blocks routing between bridges. Set to `false` for single-bridge setups.
- `isolationExceptions`: Array of rules allowing specific IPs to bypass isolation.

### HOMELAB Network Configuration

Per-network configuration for the HOMELAB network (typically br0):

```nix
homelab = {
  # Network settings
  ipAddress = "192.168.2.1";          # Router IP (must match bridge IP)
  subnet = "192.168.2.0/24";          # Network subnet in CIDR notation
  
  # DHCP settings
  dhcp = {
    enable = true;                     # Enable/disable DHCP server
    start = "192.168.2.100";          # DHCP pool start address
    end = "192.168.2.200";            # DHCP pool end address
    leaseTime = "1h";                  # Lease duration (e.g., "1h", "24h", "1d")
    dnsServers = [ "192.168.2.1" ];   # DNS servers provided to DHCP clients
    
    dynamicDomain = "dhcp.homelab.local";  # Domain for automatic DNS entries
                                           # Set to "" to disable
    
    reservations = [
      # Static IP reservations
      {
        hostname = "desktop";
        hwAddress = "11:22:33:44:55:66";
        ipAddress = "192.168.2.50";
      }
    ];
  };
  
  # DNS settings for this network
  dns = {
    enable = true;                     # Enable/disable DNS server (Unbound)
    
    # DNS A Records (hostname → IP address)
    a_records = {
      "server.example.com" = {
        ip = "192.168.2.33";
        comment = "Main server";
      };
    };
    
    # DNS CNAME Records (alias → canonical name)
    cname_records = {
      "*.example.com" = {
        target = "example.com";
        comment = "Wildcard subdomain";
      };
    };
    
    # Blocklist configuration
    blocklists = {
      enable = true;                   # Master switch for all blocklists
      
      stevenblack = {
        enable = false;
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Ads and malware blocking (250K+ domains)";
        updateInterval = "24h";
      };
      
      phishing-army = {
        enable = true;
        url = "https://phishing.army/download/phishing_army_blocklist.txt";
        description = "Phishing and scam protection";
        updateInterval = "12h";
      };
    };
    
    whitelist = [
      # Domains to bypass blocking
      "example.com"
    ];
  };
};
```

### LAN Network Configuration

Second `lan` section - per-network configuration for the LAN network (typically br1). **Note:** This is a separate top-level `lan` attribute (not nested under the bridges `lan`). Both sections use the same structure as `homelab`:

```nix
lan = {
  # Network settings
  ipAddress = "192.168.3.1";
  subnet = "192.168.3.0/24";
  
  # DHCP settings (same structure as homelab)
  dhcp = { ... };
  
  # DNS settings (same structure as homelab)
  dns = {
    enable = true;
    a_records = { ... };
    cname_records = { ... };
    blocklists = {
      enable = true;
      stevenblack = { ... };
      phishing-army = { ... };
      adaway = {  # Additional blocklist available for LAN
        enable = true;
        url = "https://adaway.org/hosts.txt";
        description = "Mobile-focused ad blocking";
        updateInterval = "1w";
      };
    };
    whitelist = [ ... ];
  };
};
```

The LAN network configuration supports the same fields as HOMELAB, plus the `adaway` blocklist option for more aggressive mobile device blocking.

### Port Forwarding

Forward external ports to internal services:

```nix
portForwards = [
  {
    proto = "tcp" | "udp" | "both";  # Protocol
    externalPort = 443;               # External port number
    destination = "192.168.2.33";     # Internal destination IP
    destinationPort = 443;            # Internal destination port
  }
  # Add more rules as needed
];
```

### Dynamic DNS

Automatically update DNS records when WAN IP changes:

```nix
dyndns = {
  enable = true;                      # Enable/disable Dynamic DNS
  provider = "linode";                # DNS provider (currently only "linode")
  domain = "example.com";             # Domain to update
  subdomain = "";                     # Subdomain (empty string for root domain)
  domainId = 1730384;                 # Provider-specific domain ID
  recordId = 19262732;                # Provider-specific record ID
  checkInterval = "5m";               # How often to check/update (e.g., "5m", "1h")
};
```

**Note:** API credentials for the DNS provider are stored in `secrets/secrets.yaml` (encrypted with SOPS). The `domainId` and `recordId` must match your DNS provider's API.

### Global DNS Configuration

Upstream DNS servers shared by all networks:

```nix
dns = {
  enable = true;                      # Enable/disable global DNS
  
  upstreamServers = [
    "1.1.1.1@853#cloudflare-dns.com"    # Format: IP@port#hostname
    "9.9.9.9@853#dns.quad9.net"          # Port 853 = DNS-over-TLS
  ];
};
```

- Format: `IP@port#hostname` where port 853 is DNS-over-TLS
- These servers are used by all network DNS servers (Unbound) as upstream resolvers

### Web UI Configuration

Web-based monitoring and management dashboard:

```nix
webui = {
  enable = true;                      # Enable/disable WebUI
  
  port = 8080;                        # HTTP port for WebUI
  
  collectionInterval = 2;             # Data collection interval in seconds
                                      # Lower = more frequent, higher CPU
                                      # Higher = less frequent, lower CPU
  
  database = {
    host = "localhost";               # PostgreSQL host
    port = 5432;                      # PostgreSQL port
    name = "router_webui";            # Database name
    user = "router_webui";            # Database user
  };
  
  retentionDays = 30;                 # Historical data retention (days)
                                      # Older data is automatically cleaned up
};
```

**Access Control:** The WebUI uses system user authentication (PAM). Any user with a valid system account can log in. To restrict access, use firewall rules or configure an Nginx reverse proxy with additional authentication.
