{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  
  # Get network configs
  homelabCfg = routerConfig.homelab;
  lanCfg = routerConfig.lan;
  
  # Get DNS configs from each network
  homelabDns = homelabCfg.dns or {};
  lanDns = lanCfg.dns or {};
  
  # Get enabled blocklists for HOMELAB
  homelabBlocklistsEnabled = homelabDns.blocklists.enable or false;
  homelabBlocklistsRaw = homelabDns.blocklists or {};
  homelabBlocklists = if homelabBlocklistsEnabled then
    lib.filterAttrs (name: cfg: (name != "enable") && (cfg.enable or false)) homelabBlocklistsRaw
  else {};
  homelabBlocklistUrls = lib.mapAttrsToList (name: cfg: cfg.url) homelabBlocklists;
  
  # Get enabled blocklists for LAN
  lanBlocklistsEnabled = lanDns.blocklists.enable or false;
  lanBlocklistsRaw = lanDns.blocklists or {};
  lanBlocklists = if lanBlocklistsEnabled then
    lib.filterAttrs (name: cfg: (name != "enable") && (cfg.enable or false)) lanBlocklistsRaw
  else {};
  lanBlocklistUrls = lib.mapAttrsToList (name: cfg: cfg.url) lanBlocklists;
  
  # Helper to generate unbound configuration for a bridge
  mkUnboundInstance = bridgeName: bridgeCfg: {
    enable = true;
    
    settings = {
      server = {
        # Bind to the bridge IP
        interface = [ bridgeCfg.ipAddress ];
        
        # Allow queries from this bridge's subnet
        access-control = [ "${bridgeCfg.subnet} allow" ];
        
        # Performance tuning
        port = 53;
        do-ip4 = "yes";
        do-ip6 = "yes";
        do-udp = "yes";
        do-tcp = "yes";
        
        # Cache settings
        cache-min-ttl = 3600;
        cache-max-ttl = 86400;
        prefetch = "yes";
        
        # Privacy
        hide-identity = "yes";
        hide-version = "yes";
        
        # Local domain configuration
        private-domain = [ "\"${bridgeCfg.domain}\"" ];
        local-zone = [ "\"${bridgeCfg.domain}.\" static" ];
        
        # Main domain entry
        local-data = [
          # Main domain -> primary IP
          "\"${bridgeCfg.domain}. IN A ${bridgeCfg.primaryIP}\""
          
          # Wildcard -> primary IP
          "\"*.${bridgeCfg.domain}. IN A ${bridgeCfg.primaryIP}\""
          
          # Router subdomain -> router IP
          "\"router.${bridgeCfg.domain}. IN A ${bridgeCfg.ipAddress}\""
        ];
        
        # Include blocklists
        include = [ "/var/lib/unbound/${bridgeName}/blocklist.conf" ];
        
        # DNSSEC
        auto-trust-anchor-file = "/var/lib/unbound/${bridgeName}/root.key";
      };
      
      # Forward to upstream DNS
      forward-zone = [{
        name = ".";
        forward-addr = routerConfig.dns.upstreamServers or [
          "1.1.1.1@853#cloudflare-dns.com"  # Cloudflare DNS over TLS
          "9.9.9.9@853#dns.quad9.net"        # Quad9 DNS over TLS
        ];
        forward-tls-upstream = "yes";  # Use DNS over TLS for privacy
      }];
    };
  };

in

{
  config = mkIf (routerConfig.dns.enable or true) {
    
    # Create unbound instances for each bridge
    systemd.services = {
      
      # Unbound for HOMELAB (br0)
      unbound-homelab = {
        description = "Unbound DNS Resolver for HOMELAB";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        
        preStart = ''
          # Create state directory
          mkdir -p /var/lib/unbound/homelab
          
          # Initialize trust anchor if needed
          if [ ! -f /var/lib/unbound/homelab/root.key ]; then
            ${pkgs.unbound}/bin/unbound-anchor -a /var/lib/unbound/homelab/root.key || true
          fi
          
          # Download and process blocklists
          echo "Downloading blocklists for HOMELAB..."
          > /tmp/blocklist-homelab-combined.txt  # Clear combined file
          
          ${concatMapStringsSep "\n" (url: ''
            echo "  - Downloading: ${url}"
            ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-homelab-combined.txt || echo "Warning: Failed to download ${url}"
          '') homelabBlocklistUrls}
          
          # Convert hosts file to unbound format
          if [ -s /tmp/blocklist-homelab-combined.txt ]; then
            echo "Processing blocklists..."
            ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
              if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                print "local-zone: \"" $2 ".\" always_nxdomain"
              }
            }' /tmp/blocklist-homelab-combined.txt | sort -u > /var/lib/unbound/homelab/blocklist.conf
            
            # Count blocked domains
            BLOCKED_COUNT=$(wc -l < /var/lib/unbound/homelab/blocklist.conf)
            echo "HOMELAB: Blocking $BLOCKED_COUNT domains"
            
            rm /tmp/blocklist-homelab-combined.txt
          else
            echo "Warning: No blocklists downloaded, creating empty blocklist"
            touch /var/lib/unbound/homelab/blocklist.conf
          fi
          
          # Generate unbound config
          cat > /var/lib/unbound/homelab/unbound.conf << 'EOF'
          server:
            interface: ${homelabCfg.ipAddress}
            access-control: ${homelabCfg.subnet} allow
            port: 53
            do-ip4: yes
            do-ip6: yes
            do-udp: yes
            do-tcp: yes
            
            # Cache settings
            cache-min-ttl: 3600
            cache-max-ttl: 86400
            prefetch: yes
            
            # Privacy
            hide-identity: yes
            hide-version: yes
            qname-minimisation: yes
            
            # DNS A Records
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN A ${record.ip}\"  # ${record.comment or ""}") 
              (homelabDns.a_records or {})
            )}
            
            # DNS CNAME Records
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN CNAME ${record.target}.\"  # ${record.comment or ""}") 
              (homelabDns.cname_records or {})
            )}
            
            # Blocklist
            include: /var/lib/unbound/homelab/blocklist.conf
            
            # Trust anchor
            auto-trust-anchor-file: /var/lib/unbound/homelab/root.key
          
          forward-zone:
            name: "."
            ${concatMapStringsSep "\n    " (s: "forward-addr: ${s}") (routerConfig.dns.upstreamServers or [
              "1.1.1.1@853#cloudflare-dns.com"
              "9.9.9.9@853#dns.quad9.net"
            ])}
            forward-tls-upstream: yes
          EOF
        '';
        
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.unbound}/bin/unbound -d -c /var/lib/unbound/homelab/unbound.conf";
          Restart = "on-failure";
          RestartSec = "5s";
          
          # Automatically create /var/lib/unbound/homelab with proper permissions
          StateDirectory = "unbound/homelab";
          
          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          
          # Run as dedicated user
          User = "unbound";
          Group = "unbound";
        };
      };
      
      # Unbound for LAN (br1)
      unbound-lan = {
        description = "Unbound DNS Resolver for LAN";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        
        preStart = ''
          # Create state directory
          mkdir -p /var/lib/unbound/lan
          
          # Initialize trust anchor if needed
          if [ ! -f /var/lib/unbound/lan/root.key ]; then
            ${pkgs.unbound}/bin/unbound-anchor -a /var/lib/unbound/lan/root.key || true
          fi
          
          # Download and process blocklists
          echo "Downloading blocklists for LAN..."
          > /tmp/blocklist-lan-combined.txt  # Clear combined file
          
          ${concatMapStringsSep "\n" (url: ''
            echo "  - Downloading: ${url}"
            ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-lan-combined.txt || echo "Warning: Failed to download ${url}"
          '') lanBlocklistUrls}
          
          # Convert hosts file to unbound format
          if [ -s /tmp/blocklist-lan-combined.txt ]; then
            echo "Processing blocklists..."
            ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
              if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                print "local-zone: \"" $2 ".\" always_nxdomain"
              }
            }' /tmp/blocklist-lan-combined.txt | sort -u > /var/lib/unbound/lan/blocklist.conf
            
            # Count blocked domains
            BLOCKED_COUNT=$(wc -l < /var/lib/unbound/lan/blocklist.conf)
            echo "LAN: Blocking $BLOCKED_COUNT domains"
            
            rm /tmp/blocklist-lan-combined.txt
          else
            echo "Warning: No blocklists downloaded, creating empty blocklist"
            touch /var/lib/unbound/lan/blocklist.conf
          fi
          
          # Generate unbound config
          cat > /var/lib/unbound/lan/unbound.conf << 'EOF'
          server:
            interface: ${lanCfg.ipAddress}
            access-control: ${lanCfg.subnet} allow
            port: 53
            do-ip4: yes
            do-ip6: yes
            do-udp: yes
            do-tcp: yes
            
            # Cache settings
            cache-min-ttl: 3600
            cache-max-ttl: 86400
            prefetch: yes
            
            # Privacy
            hide-identity: yes
            hide-version: yes
            qname-minimisation: yes
            
            # DNS A Records
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN A ${record.ip}\"  # ${record.comment or ""}") 
              (lanDns.a_records or {})
            )}
            
            # DNS CNAME Records
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN CNAME ${record.target}.\"  # ${record.comment or ""}") 
              (lanDns.cname_records or {})
            )}
            
            # Blocklist
            include: /var/lib/unbound/lan/blocklist.conf
            
            # Trust anchor
            auto-trust-anchor-file: /var/lib/unbound/lan/root.key
          
          forward-zone:
            name: "."
            ${concatMapStringsSep "\n    " (s: "forward-addr: ${s}") (routerConfig.dns.upstreamServers or [
              "1.1.1.1@853#cloudflare-dns.com"
              "9.9.9.9@853#dns.quad9.net"
            ])}
            forward-tls-upstream: yes
          EOF
        '';
        
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.unbound}/bin/unbound -d -c /var/lib/unbound/lan/unbound.conf";
          Restart = "on-failure";
          RestartSec = "5s";
          
          # Automatically create /var/lib/unbound/lan with proper permissions
          StateDirectory = "unbound/lan";
          
          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          
          # Run as dedicated user
          User = "unbound";
          Group = "unbound";
        };
      };
      
      # Blocklist update service for HOMELAB
      unbound-blocklist-update-homelab = {
        description = "Update Unbound Blocklists for HOMELAB";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "unbound/homelab";
          User = "unbound";
          Group = "unbound";
          ExecStart = "${pkgs.writeShellScript "update-blocklists-homelab" ''
            #!/usr/bin/env bash
            set -e
            
            echo "=== Updating HOMELAB Blocklists ==="
            > /tmp/blocklist-homelab-combined.txt
            
            ${concatMapStringsSep "\n" (url: ''
              echo "  - Downloading: ${url}"
              ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-homelab-combined.txt || echo "Warning: Failed to download ${url}"
            '') homelabBlocklistUrls}
            
            if [ -s /tmp/blocklist-homelab-combined.txt ]; then
              echo "Processing blocklists..."
              ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
                if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                  print "local-zone: \"" $2 ".\" always_nxdomain"
                }
              }' /tmp/blocklist-homelab-combined.txt | sort -u > /var/lib/unbound/homelab/blocklist.conf.new
              
              BLOCKED_COUNT=$(wc -l < /var/lib/unbound/homelab/blocklist.conf.new)
              echo "HOMELAB: Now blocking $BLOCKED_COUNT domains"
              
              mv /var/lib/unbound/homelab/blocklist.conf.new /var/lib/unbound/homelab/blocklist.conf
              rm /tmp/blocklist-homelab-combined.txt
              systemctl reload-or-restart unbound-homelab || true
            else
              echo "No blocklists downloaded for HOMELAB"
            fi
            
            echo "=== HOMELAB blocklist update completed ==="
          ''}";
        };
      };
      
      # Blocklist update service for LAN
      unbound-blocklist-update-lan = {
        description = "Update Unbound Blocklists for LAN";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "unbound/lan";
          User = "unbound";
          Group = "unbound";
          ExecStart = "${pkgs.writeShellScript "update-blocklists-lan" ''
            #!/usr/bin/env bash
            set -e
            
            echo "=== Updating LAN Blocklists ==="
            > /tmp/blocklist-lan-combined.txt
            
            ${concatMapStringsSep "\n" (url: ''
              echo "  - Downloading: ${url}"
              ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-lan-combined.txt || echo "Warning: Failed to download ${url}"
            '') lanBlocklistUrls}
            
            if [ -s /tmp/blocklist-lan-combined.txt ]; then
              echo "Processing blocklists..."
              ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
                if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                  print "local-zone: \"" $2 ".\" always_nxdomain"
                }
              }' /tmp/blocklist-lan-combined.txt | sort -u > /var/lib/unbound/lan/blocklist.conf.new
              
              BLOCKED_COUNT=$(wc -l < /var/lib/unbound/lan/blocklist.conf.new)
              echo "LAN: Now blocking $BLOCKED_COUNT domains"
              
              mv /var/lib/unbound/lan/blocklist.conf.new /var/lib/unbound/lan/blocklist.conf
              rm /tmp/blocklist-lan-combined.txt
              systemctl reload-or-restart unbound-lan || true
            else
              echo "No blocklists downloaded for LAN"
            fi
            
            echo "=== LAN blocklist update completed ==="
          ''}";
        };
      };
    };
    
    # Timer for HOMELAB blocklist updates
    systemd.timers.unbound-blocklist-update-homelab = mkIf homelabBlocklistsEnabled {
      description = "Update Unbound Blocklists for HOMELAB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";  # TODO: Use minimum of all blocklist intervals
        Persistent = true;
      };
    };
    
    # Timer for LAN blocklist updates
    systemd.timers.unbound-blocklist-update-lan = mkIf lanBlocklistsEnabled {
      description = "Update Unbound Blocklists for LAN";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";  # TODO: Use minimum of all blocklist intervals
        Persistent = true;
      };
    };
    
    # Create unbound user and group
    users.users.unbound = {
      isSystemUser = true;
      group = "unbound";
      description = "Unbound DNS resolver user";
    };
    
    users.groups.unbound = {};
    
    # Install unbound package
    environment.systemPackages = with pkgs; [
      unbound
    ];
    
    # Open firewall for DNS
    networking.firewall.interfaces = {
      br0.allowedUDPPorts = [ 53 ];
      br0.allowedTCPPorts = [ 53 ];
      br1.allowedUDPPorts = [ 53 ];
      br1.allowedTCPPorts = [ 53 ];
    };
  };
}

