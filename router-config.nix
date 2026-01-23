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

    # DHCP settings (imported from config/dnsmasq/dhcp-homelab.nix)
    dhcp = import ./config/dnsmasq/dhcp-homelab.nix;

    # DNS settings for this network (imported from config/dnsmasq/dns-homelab.nix)
    dns = (import ./config/dnsmasq/dns-homelab.nix) // {
      enable = true;  # Set to false to disable DNS server for this network

      # Blocklist configuration (imported from config/dnsmasq/blocklists-homelab.nix)
      blocklists = import ./config/dnsmasq/blocklists-homelab.nix;
      # Whitelist configuration (imported from config/dnsmasq/whitelist-homelab.nix)
      whitelist = import ./config/dnsmasq/whitelist-homelab.nix;
    };
  };

  # LAN network configuration
  lan = {
    # Network settings
    ipAddress = "192.168.3.1";
    subnet = "192.168.3.0/24";

    # DHCP settings (imported from config/dnsmasq/dhcp-lan.nix)
    dhcp = import ./config/dnsmasq/dhcp-lan.nix;

    # DNS settings for this network (imported from config/dnsmasq/dns-lan.nix)
    dns = (import ./config/dnsmasq/dns-lan.nix) // {
      enable = true;  # Set to false to disable DNS server for this network

      # Blocklist configuration (imported from config/dnsmasq/blocklists-lan.nix)
      blocklists = import ./config/dnsmasq/blocklists-lan.nix;
      # Whitelist configuration (imported from config/dnsmasq/whitelist-lan.nix)
      whitelist = import ./config/dnsmasq/whitelist-lan.nix;
    };
  };

  # Port Forwarding Rules (imported from config/port-forwarding.nix)
  portForwards = import ./config/port-forwarding.nix;

  # Dynamic DNS Configuration (imported from config/dyndns.nix)
  dyndns = import ./config/dyndns.nix;

  # Global DNS configuration (imported from config/dnsmasq/global-dns.nix)
  dns = import ./config/dnsmasq/global-dns.nix;

  # Web UI Configuration (imported from config/webui.nix)
  webui = import ./config/webui.nix;

  # Apprise API Configuration (imported from config/apprise.nix)
  apprise = import ./config/apprise.nix;
}