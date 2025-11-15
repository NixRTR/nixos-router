# Router configuration variables
# Converted to new structure with per-network DNS configuration

{
  # System settings
  hostname = "nixos-router";
  timezone = "America/Anchorage";
  username = "routeradmin";

  # SSH authorized keys for the router admin user
  sshKeys = [
    # Add your SSH public keys here, one per line
    # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
  ];

  # WAN configuration
  wan = {
    type = "pppoe";  # "dhcp" or "pppoe"
    interface = "eno1";
  };

  # LAN configuration - Multiple isolated networks
  lan = {
    # Physical port mapping (for reference):
    # enp4s0, enp5s0 = HOMELAB (left two ports on 4-port card)
    # enp6s0, enp7s0 = LAN (right two ports on 4-port card)

    bridges = [
      # HOMELAB network - servers, IoT devices
      {
        name = "br0";
        interfaces = [ "enp4s0" "enp5s0" ];
        ipv4 = {
          address = "192.168.2.1";
          prefixLength = 24;
        };
        ipv6.enable = false;
      }
      # LAN network - computers, phones, tablets
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

    # Block traffic between HOMELAB and LAN at the router level
    # (Hera and Triton have dual NICs and can bridge as needed)
    isolation = true;

    # Exception: Allow specific LAN devices to access HOMELAB
    # Format: { source = "LAN IP"; sourceBridge = "br1"; destBridge = "br0"; }
    isolationExceptions = [
      {
        source = "192.168.3.101";  # Your workstation IP
        sourceBridge = "br1";      # LAN
        destBridge = "br0";        # HOMELAB
        description = "Workstation access to HOMELAB";
      }
    ];
  };

  # HOMELAB network configuration
  homelab = {
    # Network settings
    ipAddress = "192.168.2.1";
    subnet = "192.168.2.0/24";

    # DHCP settings
    dhcp = {
      start = "192.168.2.100";
      end = "192.168.2.200";
      leaseTime = "1h";
      dnsServers = [
        "192.168.2.1"
      ];
      
      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.homelab.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.homelab.local"
      dynamicDomain = "dhcp.homelab.local";  # Set to "" to disable dynamic DNS
      
      reservations = [
        # Example: { hostname = "desktop"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.3.50"; }
        # Example: { hostname = "laptop"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.3.51"; }
      ];
    };

    # DNS settings for this network
    dns = {
      # DNS A Records (hostname → IP address)
      a_records = {
        "jeandr.net" = {
          ip = "192.168.2.33";
          comment = "Main jeandr.net domain - points to Hera";
        };
        "router.jeandr.net" = {
          ip = "192.168.2.1";
          comment = "Router address";
        };
        "hera.jeandr.net" = {
          ip = "192.168.2.33";
          comment = "Hera - Main web/app server";
        };
        "triton.jeandr.net" = {
          ip = "192.168.2.31";
          comment = "Triton - Secondary server";
        };
        # Add more servers here as needed:
        # "nas.jeandr.net" = { ip = "192.168.2.40"; comment = "NAS storage"; };
      };

      # DNS CNAME Records (alias → canonical name)
      cname_records = {
        "*.jeandr.net" = {
          target = "jeandr.net";
          comment = "Wildcard - all subdomains point to main domain";
        };
        # Add more aliases as needed:
        # "app.jeandr.net" = { target = "hera.jeandr.net"; comment = "Application"; };
        # "api.jeandr.net" = { target = "hera.jeandr.net"; comment = "API"; };
      };

      # Blocklist configuration
      blocklists = {
        enable = true;  # Master switch - set to false to disable all blocking

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
      ];
    };
  };

  # LAN network configuration
  lan = {
    # Network settings
    ipAddress = "192.168.3.1";
    subnet = "192.168.3.0/24";

    # DHCP settings
    dhcp = {
      start = "192.168.3.100";
      end = "192.168.3.200";
      leaseTime = "1h";
      dnsServers = [
        "192.168.3.1"
      ];
      
      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.lan.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.lan.local"
      dynamicDomain = "dhcp.lan.local";  # Set to "" to disable dynamic DNS
      
      reservations = [
        # Example: { hostname = "desktop"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.3.50"; }
        # Example: { hostname = "laptop"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.3.51"; }
      ];
    };

    # DNS settings for this network
    dns = {
      # DNS A Records (hostname → IP address)
      a_records = {
        "jeandr.net" = {
          ip = "192.168.3.33";
          comment = "Main jeandr.net domain - points to Hera (HOMELAB)";
        };
        "router.jeandr.net" = {
          ip = "192.168.3.1";
          comment = "Router address (LAN side)";
        };
        "hera.jeandr.net" = {
          ip = "192.168.3.33";
          comment = "Hera - Main web/app server";
        };
        "triton.jeandr.net" = {
          ip = "192.168.3.31";
          comment = "Triton - Secondary server";
        };
        # Add LAN-specific devices here:
        # "workstation.jeandr.net" = { ip = "192.168.3.101"; comment = "Main workstation"; };
        # "desktop.jeandr.net" = { ip = "192.168.3.50"; comment = "Desktop computer"; };
      };

      # DNS CNAME Records (alias → canonical name)
      cname_records = {
        "*.jeandr.net" = {
          target = "jeandr.net";
          comment = "Wildcard for all subdomains";
        };
        # Add more aliases as needed
      };

      # Blocklist configuration (can differ from HOMELAB)
      blocklists = {
        enable = true;  # Master switch

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

        # LAN might want more aggressive blocking for family devices:

        adaway = {
          enable = true;
          url = "https://adaway.org/hosts.txt";
          description = "Mobile-focused ad blocking";
          updateInterval = "1w";
        };
      };
      whitelist = [
      ];
    };
  };

  # Port Forwarding Rules
  portForwards = [
    # HTTP/HTTPS to Hera
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
    # Syncthing to Hera
    {
      proto = "both";
      externalPort = 22000;
      destination = "192.168.2.33";
      destinationPort = 22000;
    }
    # Port 4242 to Triton
    {
      proto = "both";
      externalPort = 4242;
      destination = "192.168.2.31";
      destinationPort = 4242;
    }
  ];

  # Dynamic DNS Configuration
  dyndns = {
    enable = true;
    provider = "linode";

    # Domain and record to update
    domain = "jeandr.net";
    subdomain = "";  # Root domain

    # Linode API credentials (stored in sops secrets)
    domainId = 1730384;
    recordId = 19262732;

    # Update interval
    checkInterval = "5m";
  };

  # Global DNS configuration
  dns = {
    enable = true;

    # Upstream DNS servers (shared by all networks)
    upstreamServers = [
      "1.1.1.1@853#cloudflare-dns.com"  # Cloudflare DNS over TLS
      "9.9.9.9@853#dns.quad9.net"        # Quad9 DNS over TLS
    ];
  };
}