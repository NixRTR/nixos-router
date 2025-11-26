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
  
  # Check if DNS is enabled for each network (defaults to true for backward compatibility)
  homelabDnsEnabled = (routerConfig.dns.enable or true) && (homelabDns.enable or true);
  lanDnsEnabled = (routerConfig.dns.enable or true) && (lanDns.enable or true);
  
  # Helper to extract unique base domains from A records
  extractBaseDomains = aRecords:
    let
      domains = lib.attrNames aRecords;
      baseDomains = lib.unique (map (name:
        let
          parts = lib.splitString "." name;
          numParts = builtins.length parts;
        in
          if numParts >= 2 then
            "${builtins.elemAt parts (numParts - 2)}.${builtins.elemAt parts (numParts - 1)}"
          else name
      ) domains);
    in baseDomains;
  
  # Helper to extract the primary domain (most common base domain) from A records
  extractPrimaryDomain = aRecords:
    let
      domains = lib.attrNames aRecords;
    in
      if domains == [] then "local"
      else
        let
          firstRecord = builtins.head domains;
          parts = lib.splitString "." firstRecord;
          numParts = builtins.length parts;
        in
          if numParts >= 2 then
            "${builtins.elemAt parts (numParts - 2)}.${builtins.elemAt parts (numParts - 1)}"
          else firstRecord;
  
  # Helper to convert DHCP reservations to DNS A records
  dhcpReservationsToARecords = reservations: domain:
    lib.listToAttrs (map (res: {
      name = "${res.hostname}.${domain}";
      value = {
        ip = res.ipAddress;
        comment = "DHCP reservation for ${res.hostname}";
      };
    }) reservations);
  
  # Get primary domains for each network
  homelabPrimaryDomain = extractPrimaryDomain (homelabDns.a_records or {});
  lanPrimaryDomain = extractPrimaryDomain (lanDns.a_records or {});
  
  # Convert DHCP reservations to DNS A records
  homelabDhcpARecords = dhcpReservationsToARecords (homelabCfg.dhcp.reservations or []) homelabPrimaryDomain;
  lanDhcpARecords = dhcpReservationsToARecords (lanCfg.dhcp.reservations or []) lanPrimaryDomain;
  
  # Merge DHCP-generated A records with manual A records (manual takes precedence if specified)
  homelabAllARecords = homelabDhcpARecords // (homelabDns.a_records or {});
  lanAllARecords = lanDhcpARecords // (lanDns.a_records or {});
  
  # Extract base domains from merged A records (for local-zone declarations)
  homelabBaseDomains = lib.unique (
    (extractBaseDomains homelabAllARecords) ++
    (lib.optional ((homelabCfg.dhcp.dynamicDomain or "") != "") homelabCfg.dhcp.dynamicDomain)
  );
  lanBaseDomains = lib.unique (
    (extractBaseDomains lanAllARecords) ++
    (lib.optional ((lanCfg.dhcp.dynamicDomain or "") != "") lanCfg.dhcp.dynamicDomain)
  );
  
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
    # Always create the services, but only enable/start them if DNS is enabled
    systemd.services = mkMerge [
      
      # Unbound for HOMELAB (br0)
      {
        unbound-homelab = {
        description = "Unbound DNS Resolver for HOMELAB";
        after = [ "network.target" ];
        wantedBy = if homelabDnsEnabled then [ "multi-user.target" ] else [];
        
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
          
          # Generate dynamic DNS entries from DHCP leases
          echo "Generating dynamic DNS entries from DHCP leases..."
          > /var/lib/unbound/homelab/dynamic-dns.conf
          
          ${if (homelabCfg.dhcp.dynamicDomain or "") != "" then ''
            if [ -f /var/lib/kea/dhcp4.leases ]; then
              ${pkgs.gawk}/bin/awk -v domain="${homelabCfg.dhcp.dynamicDomain}" -v subnet="${homelabCfg.subnet}" '
                BEGIN {
                  split(subnet, parts, "/");
                  network_prefix = parts[1];
                  split(network_prefix, octets, ".");
                  base = octets[1] "." octets[2] "." octets[3];
                }
                
                # Parse JSON lease file
                /"ip-address":/ {
                  gsub(/[",]/, "");
                  ip = $2;
                  if (index(ip, base) == 1) {
                    split(ip, ip_parts, ".");
                    last_octet = ip_parts[4];
                    hostname = "dhcp-" last_octet;
                    
                    getline; # Read next line
                    while ($0 !~ /}/) {
                      if ($0 ~ /"hostname":/) {
                        gsub(/[",]/, "");
                        if ($2 != "") hostname = $2;
                        break;
                      }
                      getline;
                    }
                    
                    print "local-data: \"" hostname "." domain ". IN A " ip "\"  # Dynamic DHCP";
                  }
                }
              ' /var/lib/kea/dhcp4.leases >> /var/lib/unbound/homelab/dynamic-dns.conf
              
              DYNAMIC_COUNT=$(wc -l < /var/lib/unbound/homelab/dynamic-dns.conf)
              echo "HOMELAB: $DYNAMIC_COUNT dynamic DNS entries"
            else
              echo "No DHCP leases found for HOMELAB"
            fi
          '' else ''
            echo "Dynamic DNS disabled for HOMELAB"
          ''}
          
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
            
            # Disable chroot (we use systemd sandboxing instead)
            chroot: ""
            directory: "/var/lib/unbound/homelab"
            pidfile: "/var/lib/unbound/homelab/unbound.pid"
            
            # SSL/TLS settings for DNS-over-TLS
            tls-cert-bundle: "/etc/ssl/certs/ca-bundle.crt"
            
            # Cache settings
            cache-min-ttl: 3600
            cache-max-ttl: 86400
            prefetch: yes
            
            # Privacy
            hide-identity: yes
            hide-version: yes
            qname-minimisation: yes
            
            # Local zones - declare these domains as locally served
            # Use 'transparent' instead of 'static' to allow wildcard matching
            ${concatMapStringsSep "\n    " (domain: "local-zone: \"${domain}.\" transparent") homelabBaseDomains}
            
            # DNS A Records (manual + DHCP reservations)
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN A ${record.ip}\"  # ${record.comment or ""}") 
              homelabAllARecords
            )}
            
            # DNS CNAME Records
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN CNAME ${record.target}.\"  # ${record.comment or ""}") 
              (homelabDns.cname_records or {})
            )}
            
            # Whitelist - domains that should never be blocked
            ${concatMapStringsSep "\n    " (domain: "local-zone: \"${domain}.\" transparent  # Whitelisted") (homelabDns.whitelist or [])}
            
            # Blocklist
            include: /var/lib/unbound/homelab/blocklist.conf
            
            # Dynamic DNS (from DHCP leases)
            include: /var/lib/unbound/homelab/dynamic-dns.conf
            
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
          
          # Run as dedicated user (not root)
          User = "unbound";
          Group = "unbound";
          
          # Allow binding to privileged port 53 without running as root
          AmbientCapabilities = "CAP_NET_BIND_SERVICE";
          
          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
        };
      }
      
      # Unbound for LAN (br1)
      {
        unbound-lan = {
        description = "Unbound DNS Resolver for LAN";
        after = [ "network.target" ];
        wantedBy = if lanDnsEnabled then [ "multi-user.target" ] else [];
        
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
          
          # Generate dynamic DNS entries from DHCP leases
          echo "Generating dynamic DNS entries from DHCP leases..."
          > /var/lib/unbound/lan/dynamic-dns.conf
          
          ${if (lanCfg.dhcp.dynamicDomain or "") != "" then ''
            if [ -f /var/lib/kea/dhcp4.leases ]; then
              ${pkgs.gawk}/bin/awk -v domain="${lanCfg.dhcp.dynamicDomain}" -v subnet="${lanCfg.subnet}" '
                BEGIN {
                  split(subnet, parts, "/");
                  network_prefix = parts[1];
                  split(network_prefix, octets, ".");
                  base = octets[1] "." octets[2] "." octets[3];
                }
                
                # Parse JSON lease file
                /"ip-address":/ {
                  gsub(/[",]/, "");
                  ip = $2;
                  if (index(ip, base) == 1) {
                    split(ip, ip_parts, ".");
                    last_octet = ip_parts[4];
                    hostname = "dhcp-" last_octet;
                    
                    getline; # Read next line
                    while ($0 !~ /}/) {
                      if ($0 ~ /"hostname":/) {
                        gsub(/[",]/, "");
                        if ($2 != "") hostname = $2;
                        break;
                      }
                      getline;
                    }
                    
                    print "local-data: \"" hostname "." domain ". IN A " ip "\"  # Dynamic DHCP";
                  }
                }
              ' /var/lib/kea/dhcp4.leases >> /var/lib/unbound/lan/dynamic-dns.conf
              
              DYNAMIC_COUNT=$(wc -l < /var/lib/unbound/lan/dynamic-dns.conf)
              echo "LAN: $DYNAMIC_COUNT dynamic DNS entries"
            else
              echo "No DHCP leases found for LAN"
            fi
          '' else ''
            echo "Dynamic DNS disabled for LAN"
          ''}
          
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
            
            # Disable chroot (we use systemd sandboxing instead)
            chroot: ""
            directory: "/var/lib/unbound/lan"
            pidfile: "/var/lib/unbound/lan/unbound.pid"
            
            # SSL/TLS settings for DNS-over-TLS
            tls-cert-bundle: "/etc/ssl/certs/ca-bundle.crt"
            
            # Cache settings
            cache-min-ttl: 3600
            cache-max-ttl: 86400
            prefetch: yes
            
            # Privacy
            hide-identity: yes
            hide-version: yes
            qname-minimisation: yes
            
            # Local zones - declare these domains as locally served
            # Use 'transparent' instead of 'static' to allow wildcard matching
            ${concatMapStringsSep "\n    " (domain: "local-zone: \"${domain}.\" transparent") lanBaseDomains}
            
            # DNS A Records (manual + DHCP reservations)
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN A ${record.ip}\"  # ${record.comment or ""}") 
              lanAllARecords
            )}
            
            # DNS CNAME Records
            ${concatStringsSep "\n    " (lib.mapAttrsToList 
              (name: record: "local-data: \"${name}. IN CNAME ${record.target}.\"  # ${record.comment or ""}") 
              (lanDns.cname_records or {})
            )}
            
            # Whitelist - domains that should never be blocked
            ${concatMapStringsSep "\n    " (domain: "local-zone: \"${domain}.\" transparent  # Whitelisted") (lanDns.whitelist or [])}
            
            # Blocklist
            include: /var/lib/unbound/lan/blocklist.conf
            
            # Dynamic DNS (from DHCP leases)
            include: /var/lib/unbound/lan/dynamic-dns.conf
            
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
          
          # Run as dedicated user (not root)
          User = "unbound";
          Group = "unbound";
          
          # Allow binding to privileged port 53 without running as root
          AmbientCapabilities = "CAP_NET_BIND_SERVICE";
          
          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
        };
      }
      
      # Blocklist update service for HOMELAB
      (mkIf homelabDnsEnabled {
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
      })
      
      # Blocklist update service for LAN
      (mkIf lanDnsEnabled {
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
      })
      
      # Dynamic DNS updater services
      (mkIf homelabDnsEnabled {
        unbound-dynamic-dns-homelab = {
          description = "Update Unbound Dynamic DNS for HOMELAB";
          serviceConfig = {
            Type = "oneshot";
            User = "unbound";
            Group = "unbound";
          };
          script = ''
            echo "Updating dynamic DNS for HOMELAB..."
            
            # Regenerate dynamic DNS entries
            > /var/lib/unbound/homelab/dynamic-dns.conf
            
            ${if (homelabCfg.dhcp.dynamicDomain or "") != "" then ''
              if [ -f /var/lib/kea/dhcp4.leases ]; then
                ${pkgs.gawk}/bin/awk -v domain="${homelabCfg.dhcp.dynamicDomain}" -v subnet="${homelabCfg.subnet}" '
                  BEGIN {
                    split(subnet, parts, "/");
                    network_prefix = parts[1];
                    split(network_prefix, octets, ".");
                    base = octets[1] "." octets[2] "." octets[3];
                  }
                  
                  /"ip-address":/ {
                    gsub(/[",]/, "");
                    ip = $2;
                    if (index(ip, base) == 1) {
                      split(ip, ip_parts, ".");
                      last_octet = ip_parts[4];
                      hostname = "dhcp-" last_octet;
                      
                      getline;
                      while ($0 !~ /}/) {
                        if ($0 ~ /"hostname":/) {
                          gsub(/[",]/, "");
                          if ($2 != "") hostname = $2;
                          break;
                        }
                        getline;
                      }
                      
                      print "local-data: \"" hostname "." domain ". IN A " ip "\"  # Dynamic DHCP";
                    }
                  }
                ' /var/lib/kea/dhcp4.leases > /var/lib/unbound/homelab/dynamic-dns.conf
                
                # Reload Unbound
                ${pkgs.unbound}/bin/unbound-control -c /var/lib/unbound/homelab/unbound.conf reload || true
                
                DYNAMIC_COUNT=$(wc -l < /var/lib/unbound/homelab/dynamic-dns.conf)
                echo "HOMELAB: $DYNAMIC_COUNT dynamic DNS entries"
              fi
            '' else ""}
          '';
        };
      })
      
      (mkIf lanDnsEnabled {
        unbound-dynamic-dns-lan = {
          description = "Update Unbound Dynamic DNS for LAN";
          serviceConfig = {
            Type = "oneshot";
            User = "unbound";
            Group = "unbound";
          };
          script = ''
            echo "Updating dynamic DNS for LAN..."
            
            # Regenerate dynamic DNS entries
            > /var/lib/unbound/lan/dynamic-dns.conf
            
            ${if (lanCfg.dhcp.dynamicDomain or "") != "" then ''
              if [ -f /var/lib/kea/dhcp4.leases ]; then
                ${pkgs.gawk}/bin/awk -v domain="${lanCfg.dhcp.dynamicDomain}" -v subnet="${lanCfg.subnet}" '
                  BEGIN {
                    split(subnet, parts, "/");
                    network_prefix = parts[1];
                    split(network_prefix, octets, ".");
                    base = octets[1] "." octets[2] "." octets[3];
                  }
                  
                  /"ip-address":/ {
                    gsub(/[",]/, "");
                    ip = $2;
                    if (index(ip, base) == 1) {
                      split(ip, ip_parts, ".");
                      last_octet = ip_parts[4];
                      hostname = "dhcp-" last_octet;
                      
                      getline;
                      while ($0 !~ /}/) {
                        if ($0 ~ /"hostname":/) {
                          gsub(/[",]/, "");
                          if ($2 != "") hostname = $2;
                          break;
                        }
                        getline;
                      }
                      
                      print "local-data: \"" hostname "." domain ". IN A " ip "\"  # Dynamic DHCP";
                    }
                  }
                ' /var/lib/kea/dhcp4.leases > /var/lib/unbound/lan/dynamic-dns.conf
                
                # Reload Unbound
                ${pkgs.unbound}/bin/unbound-control -c /var/lib/unbound/lan/unbound.conf reload || true
                
                DYNAMIC_COUNT=$(wc -l < /var/lib/unbound/lan/dynamic-dns.conf)
                echo "LAN: $DYNAMIC_COUNT dynamic DNS entries"
              fi
            '' else ""}
          '';
        };
      })
    ];
    
    # Timer for HOMELAB blocklist updates
    systemd.timers.unbound-blocklist-update-homelab = mkIf (homelabDnsEnabled && homelabBlocklistsEnabled) {
      description = "Update Unbound Blocklists for HOMELAB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";  # TODO: Use minimum of all blocklist intervals
        Persistent = true;
      };
    };
    
    # Timer for LAN blocklist updates
    systemd.timers.unbound-blocklist-update-lan = mkIf (lanDnsEnabled && lanBlocklistsEnabled) {
      description = "Update Unbound Blocklists for LAN";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";  # TODO: Use minimum of all blocklist intervals
        Persistent = true;
      };
    };
    
    # Timers to periodically update dynamic DNS
    systemd.timers.unbound-dynamic-dns-homelab = mkIf (homelabDnsEnabled && ((homelabCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Periodically update Unbound Dynamic DNS for HOMELAB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "5m";  # Update every 5 minutes
      };
    };
    
    systemd.timers.unbound-dynamic-dns-lan = mkIf (lanDnsEnabled && ((lanCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Periodically update Unbound Dynamic DNS for LAN";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "5m";  # Update every 5 minutes
      };
    };
    
    # Watch DHCP lease file for changes
    systemd.paths.unbound-dynamic-dns-homelab = mkIf (homelabDnsEnabled && ((homelabCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Watch DHCP leases for HOMELAB Dynamic DNS updates";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/var/lib/kea/dhcp4.leases";
      };
    };
    
    systemd.paths.unbound-dynamic-dns-lan = mkIf (lanDnsEnabled && ((lanCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Watch DHCP leases for LAN Dynamic DNS updates";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/var/lib/kea/dhcp4.leases";
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

