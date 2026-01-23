# Router configuration variables
# Converted to new structure with per-network DNS configuration

{
  # System settings
  hostname = "nixos-router";
  domain = "example.com";  # Domain for DNS search (used in /etc/resolv.conf)
  timezone = "America/Anchorage";
  username = "routeradmin";

  # Nameservers for /etc/resolv.conf (used by the router itself)
  nameservers = [ "1.1.1.1" "9.9.9.9" "192.168.3.33" ];

  # SSH authorized keys for the router admin user
  sshKeys = [
    # Add your SSH public keys here, one per line
    # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
  ];

  # WAN configuration
  wan = {
    type = "pppoe";  # "dhcp" or "pppoe"
    interface = "eno1";
    
    # CAKE traffic shaping configuration (optional)
    # CAKE (Common Applications Kept Enhanced) is a comprehensive queue management system
    # that reduces bufferbloat and improves latency under load
    # cake = {
    #   enable = true;  # Set to true to enable CAKE traffic shaping
    #   aggressiveness = "auto";  # Options: "auto", "conservative", "moderate", "aggressive"
    #   # auto: Monitors bandwidth and adjusts automatically (recommended)
    #   # conservative: Minimal shaping, best for high-speed links
    #   # moderate: Balanced latency/throughput
    #   # aggressive: Maximum latency reduction, best for slower links
    #   
    #   # Optional: Set explicit bandwidth limits (recommended for better performance)
    #   # If not set, CAKE will use autorate-ingress to automatically detect bandwidth
    #   # Format: "200Mbit", "500Mbit", "1000mbit", etc.
    #   # Set to ~95% of your actual speeds to account for overhead
    #   # uploadBandwidth = "190Mbit";    # Your upload speed (egress shaping) - 200Mbit * 0.95
    #   # downloadBandwidth = "475Mbit";  # Your download speed (for reference) - 500Mbit * 0.95
    #   
    #   # Note: CAKE on root qdisc shapes egress (upload). When uploadBandwidth is set,
    #   # autorate-ingress is disabled and explicit bandwidth is used instead.
    # };
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

    # DHCP settings (imported from dnsmasq/dhcp-homelab.nix)
    dhcp = (import ./dnsmasq/dhcp-homelab.nix) // {
      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.homelab.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.homelab.local"
      dynamicDomain = "dhcp.homelab.local";  # Set to "" to disable dynamic DNS
    };

    # DNS settings for this network (imported from dnsmasq/dns-homelab.nix)
    dns = (import ./dnsmasq/dns-homelab.nix) // {
      enable = true;  # Set to false to disable DNS server for this network

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

    # DHCP settings (imported from dnsmasq/dhcp-lan.nix)
    dhcp = (import ./dnsmasq/dhcp-lan.nix) // {
      # Dynamic DNS domain for DHCP clients (optional)
      # If set, ALL DHCP clients get automatic DNS entries
      # Example: client with hostname "phone" gets "phone.dhcp.lan.local"
      # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.lan.local"
      dynamicDomain = "dhcp.lan.local";  # Set to "" to disable dynamic DNS
    };

    # DNS settings for this network (imported from dnsmasq/dns-lan.nix)
    dns = (import ./dnsmasq/dns-lan.nix) // {
      enable = true;  # Set to false to disable DNS server for this network

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
    # Plain DNS format for dnsmasq (no DoT support)
    upstreamServers = [
      "1.1.1.1"  # Cloudflare DNS
      "9.9.9.9"  # Quad9 DNS
    ];
  };

  # Web UI Configuration
  webui = {
    # Enable web-based monitoring dashboard
    enable = true;

    # Port for the WebUI (default: 8080)
    port = 8080;

    # Data collection interval in seconds (default: 2)
    # Lower = more frequent updates, higher CPU usage
    # Higher = less frequent updates, lower CPU usage
    collectionInterval = 2;

    # Database settings (PostgreSQL)
    database = {
      host = "localhost";
      port = 5432;
      name = "router_webui";
      user = "router_webui";
    };

    # Historical data retention in days (default: 30)
    # Older data is automatically cleaned up
    retentionDays = 30;

    # Access control
    # The WebUI uses system user authentication (PAM)
    # Any user with a valid system account can login
    # To restrict access to specific users, use firewall rules
    # or configure Nginx reverse proxy with additional auth
  };

  # Apprise API Configuration
  apprise = {
    # Enable Apprise API notification service
    enable = true;

    # Internal port for apprise-api (default: 8001, separate from webui)
    port = 8001;

    # Maximum attachment size in MB (0 = disabled)
    attachSize = 0;

    # Optional: Attachments directory path
    # attachmentsDir = "/var/lib/apprise/attachments";

    # Notification Services Configuration
    # Configure notification services that apprise-api will use
    # Secrets (passwords, tokens) are stored in secrets/secrets.yaml
    services = {
      # Email configuration
      email = {
        enable = false;
        smtpHost = "smtp.gmail.com";
        smtpPort = 587;
        username = "your-email@gmail.com";
        # Password stored in sops secrets as "apprise-email-password"
        to = "recipient@example.com";
        # Optional: from address (defaults to username)
        # from = "your-email@gmail.com";
      };

      # Home Assistant configuration
      homeAssistant = {
        enable = false;
        host = "homeassistant.local";
        port = 8123;
        # Access token stored in sops secrets as "apprise-homeassistant-token"
        # Optional: use HTTPS
        # useHttps = false;
      };

      # Discord configuration
      discord = {
        enable = false;
        # Webhook ID and token stored in sops secrets:
        # - "apprise-discord-webhook-id"
        # - "apprise-discord-webhook-token"
      };

      # Slack configuration
      slack = {
        enable = false;
        # Tokens stored in sops secrets:
        # - "apprise-slack-token-a"
        # - "apprise-slack-token-b"
        # - "apprise-slack-token-c"
      };

      # Telegram configuration
      telegram = {
        enable = false;
        # Bot token stored in sops secrets as "apprise-telegram-bot-token"
        chatId = "123456789";  # Can be stored in sops if preferred
      };

      # ntfy configuration
      ntfy = {
        enable = false;
        topic = "router-notifications";
        # Optional: custom ntfy server
        # server = "https://ntfy.sh";
        # Optional: authentication
        # Username stored in sops as "apprise-ntfy-username"
        # Password stored in sops as "apprise-ntfy-password"
      };
    };
  };
}