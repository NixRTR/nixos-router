{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  
  # Get enabled blocklists
  enabledBlocklists = lib.filterAttrs (name: cfg: cfg.enable or false) (routerConfig.dns.blocklist.lists or {});
  blocklistUrls = lib.mapAttrsToList (name: cfg: cfg.url) enabledBlocklists;
  
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
    systemd.services = let
      homelabCfg = routerConfig.homelab;
      lanCfg = routerConfig.lan;
    in {
      
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
          '') blocklistUrls}
          
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
            
            # Local domain
            private-domain: "${homelabCfg.domain}"
            local-zone: "${homelabCfg.domain}." static
            
            # DNS entries
            local-data: "${homelabCfg.domain}. IN A ${homelabCfg.primaryIP}"
            local-data: "*.${homelabCfg.domain}. IN A ${homelabCfg.primaryIP}"
            local-data: "router.${homelabCfg.domain}. IN A ${homelabCfg.ipAddress}"
            
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
          
          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/var/lib/unbound/homelab" ];
          
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
          '') blocklistUrls}
          
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
            
            # Local domain
            private-domain: "${lanCfg.domain}"
            local-zone: "${lanCfg.domain}." static
            
            # DNS entries
            local-data: "${lanCfg.domain}. IN A ${lanCfg.primaryIP}"
            local-data: "*.${lanCfg.domain}. IN A ${lanCfg.primaryIP}"
            local-data: "router.${lanCfg.domain}. IN A ${lanCfg.ipAddress}"
            
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
          
          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/var/lib/unbound/lan" ];
          
          # Run as dedicated user
          User = "unbound";
          Group = "unbound";
        };
      };
      
      # Timer to update blocklists
      unbound-blocklist-update = {
        description = "Update Unbound Blocklists";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "update-blocklists" ''
            #!/usr/bin/env bash
            set -e
            
            echo "=== Updating Unbound Blocklists ==="
            
            # Update HOMELAB blocklist
            echo "Updating HOMELAB blocklist..."
            > /tmp/blocklist-homelab-combined.txt
            
            ${concatMapStringsSep "\n" (url: ''
              echo "  - Downloading: ${url}"
              ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-homelab-combined.txt || echo "Warning: Failed to download ${url}"
            '') blocklistUrls}
            
            if [ -s /tmp/blocklist-homelab-combined.txt ]; then
              ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
                if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                  print "local-zone: \"" $2 ".\" always_nxdomain"
                }
              }' /tmp/blocklist-homelab-combined.txt | sort -u > /var/lib/unbound/homelab/blocklist.conf.new
              
              BLOCKED_COUNT=$(wc -l < /var/lib/unbound/homelab/blocklist.conf.new)
              echo "HOMELAB: Now blocking $BLOCKED_COUNT domains"
              
              mv /var/lib/unbound/homelab/blocklist.conf.new /var/lib/unbound/homelab/blocklist.conf
              rm /tmp/blocklist-homelab-combined.txt
              systemctl reload-or-restart unbound-homelab
            fi
            
            # Update LAN blocklist
            echo "Updating LAN blocklist..."
            > /tmp/blocklist-lan-combined.txt
            
            ${concatMapStringsSep "\n" (url: ''
              echo "  - Downloading: ${url}"
              ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-lan-combined.txt || echo "Warning: Failed to download ${url}"
            '') blocklistUrls}
            
            if [ -s /tmp/blocklist-lan-combined.txt ]; then
              ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
                if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                  print "local-zone: \"" $2 ".\" always_nxdomain"
                }
              }' /tmp/blocklist-lan-combined.txt | sort -u > /var/lib/unbound/lan/blocklist.conf.new
              
              BLOCKED_COUNT=$(wc -l < /var/lib/unbound/lan/blocklist.conf.new)
              echo "LAN: Now blocking $BLOCKED_COUNT domains"
              
              mv /var/lib/unbound/lan/blocklist.conf.new /var/lib/unbound/lan/blocklist.conf
              rm /tmp/blocklist-lan-combined.txt
              systemctl reload-or-restart unbound-lan
            fi
            
            echo "=== Blocklist update completed ==="
          ''}";
        };
      };
    };
    
    # Timer for blocklist updates
    systemd.timers.unbound-blocklist-update = {
      description = "Update Unbound Blocklists";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = routerConfig.dns.blocklist.updateInterval or "24h";
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

