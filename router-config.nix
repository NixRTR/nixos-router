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
    
    # CAKE traffic shaping configuration (imported from config/cake.nix)
    # Uncomment and configure in config/cake.nix to enable
    # cake = import ./config/cake.nix;
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