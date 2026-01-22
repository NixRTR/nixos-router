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
  
  # Check if DHCP is enabled for each network
  homelabDhcpEnabled = homelabCfg.dhcp.enable or true;
  lanDhcpEnabled = lanCfg.dhcp.enable or true;
  
  # Get bridge interface names
  homelabBridge = "br0";
  lanBridge = "br1";
  
  # Helper function to convert lease time string to seconds
  leaseToSeconds = lease:
    let
      numeric = builtins.match "^[0-9]+$" lease;
      unitMatch = builtins.match "^([0-9]+)([smhd])$" lease;
      multiplier = unit:
        if unit == "s" then 1
        else if unit == "m" then 60
        else if unit == "h" then 3600
        else if unit == "d" then 86400
        else 1;
    in if lease == null then 86400
       else if numeric != null then lib.toInt lease
       else if unitMatch != null then
         let
           num = lib.toInt (builtins.elemAt unitMatch 0);
           unit = builtins.elemAt unitMatch 1;
         in num * multiplier unit
       else 86400;
  
  # Helper function to extract domain from A records (for DHCP option 15)
  extractDomain = aRecords:
    if aRecords == {} || aRecords == null then "local"
    else
      let
        firstRecord = builtins.head (builtins.attrNames aRecords);
        parts = lib.splitString "." firstRecord;
        numParts = builtins.length parts;
      in
        if numParts >= 2 then
          "${builtins.elemAt parts (numParts - 2)}.${builtins.elemAt parts (numParts - 1)}"
        else firstRecord;
  
  # Helper to extract the primary domain from A records
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
  
  # Helper to convert DHCP reservations to DNS host records
  dhcpReservationsToHostRecords = reservations: domain:
    map (res: {
      hostname = "${res.hostname}.${domain}";
      ip = res.ipAddress;
      comment = "DHCP reservation for ${res.hostname}";
    }) reservations;
  
  # Get primary domains for each network
  homelabPrimaryDomain = extractPrimaryDomain (homelabDns.a_records or {});
  lanPrimaryDomain = extractPrimaryDomain (lanDns.a_records or {});
  
  # Convert DHCP reservations to host records
  homelabDhcpHostRecords = dhcpReservationsToHostRecords (homelabCfg.dhcp.reservations or []) homelabPrimaryDomain;
  lanDhcpHostRecords = dhcpReservationsToHostRecords (lanCfg.dhcp.reservations or []) lanPrimaryDomain;
  
  # Get wildcard domains and their target IPs (must be defined before filtering)
  homelabWildcards = lib.filter (x: x != null) (
    lib.mapAttrsToList (name: record:
      if lib.hasPrefix "*." name then
        let
          domain = lib.removePrefix "*." name;
          # Find the IP for the target (usually the main domain)
          # Try target first, then fall back to domain itself
          targetRecord = homelabDns.a_records.${record.target} or homelabDns.a_records.${domain} or null;
        in
          if targetRecord != null then {
            domain = domain;
            ip = targetRecord.ip;
            comment = record.comment or "";
          } else null
      else null
    ) (homelabDns.cname_records or {})
  );
  
  lanWildcards = lib.filter (x: x != null) (
    lib.mapAttrsToList (name: record:
      if lib.hasPrefix "*." name then
        let
          domain = lib.removePrefix "*." name;
          # Find the IP for the target (usually the main domain)
          # Try target first, then fall back to domain itself
          targetRecord = lanDns.a_records.${record.target} or lanDns.a_records.${domain} or null;
        in
          if targetRecord != null then {
            domain = domain;
            ip = targetRecord.ip;
            comment = record.comment or "";
          } else null
      else null
    ) (lanDns.cname_records or {})
  );
  
  # Convert A records to host records format
  # Filter out wildcard entries (they should be in CNAME records, not A records)
  homelabARecordsToHostRecords = lib.mapAttrsToList (name: record: {
    hostname = name;
    ip = record.ip;
    comment = record.comment or "";
  }) (lib.filterAttrs (name: record: !lib.hasPrefix "*." name) (homelabDns.a_records or {}));
  
  lanARecordsToHostRecords = lib.mapAttrsToList (name: record: {
    hostname = name;
    ip = record.ip;
    comment = record.comment or "";
  }) (lib.filterAttrs (name: record: !lib.hasPrefix "*." name) (lanDns.a_records or {}));
  
  # Get list of wildcard base domains (to exclude from host records)
  homelabWildcardDomains = map (w: w.domain) homelabWildcards;
  lanWildcardDomains = map (w: w.domain) lanWildcards;
  
  # Filter out base domains that have wildcards (address= already handles them)
  homelabHostRecordsFiltered = lib.filter (record: 
    !(lib.elem record.hostname homelabWildcardDomains)
  ) homelabARecordsToHostRecords;
  
  lanHostRecordsFiltered = lib.filter (record: 
    !(lib.elem record.hostname lanWildcardDomains)
  ) lanARecordsToHostRecords;
  
  # Merge DHCP and manual host records (manual takes precedence)
  # Exclude base domains that have wildcards
  homelabAllHostRecords = homelabHostRecordsFiltered ++ homelabDhcpHostRecords;
  lanAllHostRecords = lanHostRecordsFiltered ++ lanDhcpHostRecords;
  
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
  
  # Helper to parse upstream servers (remove DoT format if present)
  parseUpstreamServer = server:
    let
      # Remove @853#... format if present
      parts = lib.splitString "@" server;
    in
      builtins.head parts;

in

{
  config = mkIf (routerConfig.dns.enable or true) {
    
    # Create dnsmasq instances for each bridge
    systemd.services = mkMerge [
      
      # dnsmasq for HOMELAB (br0)
      {
        dnsmasq-homelab = {
        description = "dnsmasq DNS Server for HOMELAB";
        after = [ "network.target" ];
        wantedBy = if homelabDnsEnabled then [ "multi-user.target" ] else [];
        
        preStart = ''
          # Create state directory
          mkdir -p /var/lib/dnsmasq/homelab
          
          # Download and process blocklists
          echo "Downloading blocklists for HOMELAB..."
          > /tmp/blocklist-homelab-combined.txt  # Clear combined file
          
          ${concatMapStringsSep "\n" (url: ''
            echo "  - Downloading: ${url}"
            ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-homelab-combined.txt || echo "Warning: Failed to download ${url}"
          '') homelabBlocklistUrls}
          
          # Convert hosts file to dnsmasq format
          if [ -s /tmp/blocklist-homelab-combined.txt ]; then
            echo "Processing blocklists..."
            ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
              if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                print "address=/" $2 "/"
              }
            }' /tmp/blocklist-homelab-combined.txt | sort -u > /var/lib/dnsmasq/homelab/blocklist.conf
            
            # Count blocked domains
            BLOCKED_COUNT=$(wc -l < /var/lib/dnsmasq/homelab/blocklist.conf)
            echo "HOMELAB: Blocking $BLOCKED_COUNT domains"
            
            rm /tmp/blocklist-homelab-combined.txt
          else
            echo "Warning: No blocklists downloaded, creating empty blocklist"
            touch /var/lib/dnsmasq/homelab/blocklist.conf
          fi
          
          # Generate dynamic DNS entries from DHCP leases
          echo "Generating dynamic DNS entries from DHCP leases..."
          > /var/lib/dnsmasq/homelab/dynamic-dns.conf
          
          ${if (homelabCfg.dhcp.dynamicDomain or "") != "" then ''
            if [ -f /var/lib/dnsmasq/homelab/dhcp.leases ]; then
              ${pkgs.gawk}/bin/awk -v domain="${homelabCfg.dhcp.dynamicDomain}" -v subnet="${homelabCfg.subnet}" '
                BEGIN {
                  split(subnet, parts, "/");
                  network_prefix = parts[1];
                  split(network_prefix, octets, ".");
                  base = octets[1] "." octets[2] "." octets[3];
                }
                
                # Parse dnsmasq lease file format: <expiry-time> <MAC> <IP> <hostname> <client-id>
                {
                  if (NF >= 4) {
                    expiry = $1;
                    mac = $2;
                    ip = $3;
                    hostname = $4;
                    
                    # Check if IP is in our subnet
                    if (index(ip, base) == 1) {
                      # If hostname is "*" or empty, generate one from IP
                      if (hostname == "*" || hostname == "") {
                        split(ip, ip_parts, ".");
                        last_octet = ip_parts[4];
                        hostname = "dhcp-" last_octet;
                      }
                      
                      print "host-record=" hostname "." domain "," ip "  # Dynamic DHCP";
                    }
                  }
                }
              ' /var/lib/dnsmasq/homelab/dhcp.leases >> /var/lib/dnsmasq/homelab/dynamic-dns.conf
              
              DYNAMIC_COUNT=$(wc -l < /var/lib/dnsmasq/homelab/dynamic-dns.conf)
              echo "HOMELAB: $DYNAMIC_COUNT dynamic DNS entries"
            else
              echo "No DHCP leases found for HOMELAB"
            fi
          '' else ''
            echo "Dynamic DNS disabled for HOMELAB"
          ''}
          
          # Generate dnsmasq config
          cat > /var/lib/dnsmasq/homelab/dnsmasq.conf << 'EOF'
          # Listen on specific IP address
          listen-address=${homelabCfg.ipAddress}
          bind-interfaces
          
          # Port
          port=53
          
          # Upstream DNS servers
          ${concatMapStringsSep "\n" (s: "server=${parseUpstreamServer s}") (routerConfig.dns.upstreamServers or [
            "1.1.1.1"
            "9.9.9.9"
          ])}
          
          # Local domain
          ${if homelabPrimaryDomain != "local" then ''
            domain=${homelabPrimaryDomain}
            # Only use local= if we don't have wildcards (address= handles wildcards and local resolution)
            ${if homelabWildcards == [] then "local=/${homelabPrimaryDomain}/" else ""}
          '' else ""}
          
          # Wildcard domains (from CNAME records)
          # address=/domain/IP makes all subdomains resolve to that IP
          # This also marks the domain as local, so we don't need local= when wildcards exist
          ${concatStringsSep "\n" (map (wildcard: 
            "address=/${wildcard.domain}/${wildcard.ip}  # ${wildcard.comment or ""}"
          ) homelabWildcards)}
          
          # Specific host records (override wildcards)
          ${concatStringsSep "\n" (map (record: 
            "host-record=${record.hostname},${record.ip}  # ${record.comment or ""}"
          ) homelabAllHostRecords)}
          
          # Whitelist - domains that should never be blocked
          ${concatMapStringsSep "\n" (domain: "server=/${domain}/  # Whitelisted") (homelabDns.whitelist or [])}
          
          # Include blocklists and dynamic DNS
          conf-file=/var/lib/dnsmasq/homelab/blocklist.conf
          conf-file=/var/lib/dnsmasq/homelab/dynamic-dns.conf
          
          # DHCP Configuration
          ${if homelabDhcpEnabled then ''
            dhcp-range=${homelabBridge},${homelabCfg.dhcp.start},${homelabCfg.dhcp.end},${homelabCfg.dhcp.leaseTime}
            dhcp-option=${homelabBridge},3,${homelabCfg.ipAddress}
            dhcp-option=${homelabBridge},6${concatMapStringsSep "," (s: ",${s}") (homelabCfg.dhcp.dnsServers or [ homelabCfg.ipAddress ])}
            dhcp-option=${homelabBridge},15,${extractDomain (homelabDns.a_records or {})}
            dhcp-authoritative
            dhcp-leasefile=/var/lib/dnsmasq/homelab/dhcp.leases
            ${concatStringsSep "\n" (map (res: 
              "dhcp-host=${res.hwAddress},${res.hostname},${res.ipAddress}  # Static reservation"
            ) (homelabCfg.dhcp.reservations or []))}
          '' else ""}
          
          # Performance optimizations
          cache-size=10000
          no-negcache
          no-resolv
          no-poll
          query-port=0
          
          # Logging (disabled for performance - enable only for debugging)
          # log-queries
          # log-facility=/var/lib/dnsmasq/homelab/dnsmasq.log
          EOF
        '';
        
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --no-daemon --conf-file=/var/lib/dnsmasq/homelab/dnsmasq.conf";
          Restart = "on-failure";
          RestartSec = "5s";
          
          # Automatically create /var/lib/dnsmasq/homelab with proper permissions
          StateDirectory = "dnsmasq/homelab";
          
          # Run as dedicated user (not root)
          User = "dnsmasq";
          Group = "dnsmasq";
          
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
      
      # dnsmasq for LAN (br1)
      {
        dnsmasq-lan = {
        description = "dnsmasq DNS Server for LAN";
        after = [ "network.target" ];
        wantedBy = if lanDnsEnabled then [ "multi-user.target" ] else [];
        
        preStart = ''
          # Create state directory
          mkdir -p /var/lib/dnsmasq/lan
          
          # Download and process blocklists
          echo "Downloading blocklists for LAN..."
          > /tmp/blocklist-lan-combined.txt  # Clear combined file
          
          ${concatMapStringsSep "\n" (url: ''
            echo "  - Downloading: ${url}"
            ${pkgs.curl}/bin/curl -s -f -L "${url}" >> /tmp/blocklist-lan-combined.txt || echo "Warning: Failed to download ${url}"
          '') lanBlocklistUrls}
          
          # Convert hosts file to dnsmasq format
          if [ -s /tmp/blocklist-lan-combined.txt ]; then
            echo "Processing blocklists..."
            ${pkgs.gawk}/bin/awk '/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ {
              if ($2 !~ /^(localhost|local|broadcasthost|ip6-)/) {
                print "address=/" $2 "/"
              }
            }' /tmp/blocklist-lan-combined.txt | sort -u > /var/lib/dnsmasq/lan/blocklist.conf
            
            # Count blocked domains
            BLOCKED_COUNT=$(wc -l < /var/lib/dnsmasq/lan/blocklist.conf)
            echo "LAN: Blocking $BLOCKED_COUNT domains"
            
            rm /tmp/blocklist-lan-combined.txt
          else
            echo "Warning: No blocklists downloaded, creating empty blocklist"
            touch /var/lib/dnsmasq/lan/blocklist.conf
          fi
          
          # Generate dynamic DNS entries from DHCP leases
          echo "Generating dynamic DNS entries from DHCP leases..."
          > /var/lib/dnsmasq/lan/dynamic-dns.conf
          
          ${if (lanCfg.dhcp.dynamicDomain or "") != "" then ''
            if [ -f /var/lib/dnsmasq/lan/dhcp.leases ]; then
              ${pkgs.gawk}/bin/awk -v domain="${lanCfg.dhcp.dynamicDomain}" -v subnet="${lanCfg.subnet}" '
                BEGIN {
                  split(subnet, parts, "/");
                  network_prefix = parts[1];
                  split(network_prefix, octets, ".");
                  base = octets[1] "." octets[2] "." octets[3];
                }
                
                # Parse dnsmasq lease file format: <expiry-time> <MAC> <IP> <hostname> <client-id>
                {
                  if (NF >= 4) {
                    expiry = $1;
                    mac = $2;
                    ip = $3;
                    hostname = $4;
                    
                    # Check if IP is in our subnet
                    if (index(ip, base) == 1) {
                      # If hostname is "*" or empty, generate one from IP
                      if (hostname == "*" || hostname == "") {
                        split(ip, ip_parts, ".");
                        last_octet = ip_parts[4];
                        hostname = "dhcp-" last_octet;
                      }
                      
                      print "host-record=" hostname "." domain "," ip "  # Dynamic DHCP";
                    }
                  }
                }
              ' /var/lib/dnsmasq/lan/dhcp.leases >> /var/lib/dnsmasq/lan/dynamic-dns.conf
              
              DYNAMIC_COUNT=$(wc -l < /var/lib/dnsmasq/lan/dynamic-dns.conf)
              echo "LAN: $DYNAMIC_COUNT dynamic DNS entries"
            else
              echo "No DHCP leases found for LAN"
            fi
          '' else ''
            echo "Dynamic DNS disabled for LAN"
          ''}
          
          # Generate dnsmasq config
          cat > /var/lib/dnsmasq/lan/dnsmasq.conf << 'EOF'
          # Listen on specific IP address
          listen-address=${lanCfg.ipAddress}
          bind-interfaces
          
          # Port
          port=53
          
          # Upstream DNS servers
          ${concatMapStringsSep "\n" (s: "server=${parseUpstreamServer s}") (routerConfig.dns.upstreamServers or [
            "1.1.1.1"
            "9.9.9.9"
          ])}
          
          # Local domain
          ${if lanPrimaryDomain != "local" then ''
            domain=${lanPrimaryDomain}
            # Only use local= if we don't have wildcards (address= handles wildcards and local resolution)
            ${if lanWildcards == [] then "local=/${lanPrimaryDomain}/" else ""}
          '' else ""}
          
          # Wildcard domains (from CNAME records)
          # address=/domain/IP makes all subdomains resolve to that IP
          # This also marks the domain as local, so we don't need local= when wildcards exist
          ${concatStringsSep "\n" (map (wildcard: 
            "address=/${wildcard.domain}/${wildcard.ip}  # ${wildcard.comment or ""}"
          ) lanWildcards)}
          
          # Specific host records (override wildcards)
          ${concatStringsSep "\n" (map (record: 
            "host-record=${record.hostname},${record.ip}  # ${record.comment or ""}"
          ) lanAllHostRecords)}
          
          # Whitelist - domains that should never be blocked
          ${concatMapStringsSep "\n" (domain: "server=/${domain}/  # Whitelisted") (lanDns.whitelist or [])}
          
          # Include blocklists and dynamic DNS
          conf-file=/var/lib/dnsmasq/lan/blocklist.conf
          conf-file=/var/lib/dnsmasq/lan/dynamic-dns.conf
          
          # DHCP Configuration
          ${if lanDhcpEnabled then ''
            dhcp-range=${lanBridge},${lanCfg.dhcp.start},${lanCfg.dhcp.end},${lanCfg.dhcp.leaseTime}
            dhcp-option=${lanBridge},3,${lanCfg.ipAddress}
            dhcp-option=${lanBridge},6${concatMapStringsSep "," (s: ",${s}") (lanCfg.dhcp.dnsServers or [ lanCfg.ipAddress ])}
            dhcp-option=${lanBridge},15,${extractDomain (lanDns.a_records or {})}
            dhcp-authoritative
            dhcp-leasefile=/var/lib/dnsmasq/lan/dhcp.leases
            ${concatStringsSep "\n" (map (res: 
              "dhcp-host=${res.hwAddress},${res.hostname},${res.ipAddress}  # Static reservation"
            ) (lanCfg.dhcp.reservations or []))}
          '' else ""}
          
          # Performance optimizations
          cache-size=10000
          no-negcache
          no-resolv
          no-poll
          query-port=0
          
          # Logging (disabled for performance - enable only for debugging)
          # log-queries
          # log-facility=/var/lib/dnsmasq/lan/dnsmasq.log
          EOF
        '';
        
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --no-daemon --conf-file=/var/lib/dnsmasq/lan/dnsmasq.conf";
          Restart = "on-failure";
          RestartSec = "5s";
          
          # Automatically create /var/lib/dnsmasq/lan with proper permissions
          StateDirectory = "dnsmasq/lan";
          
          # Run as dedicated user (not root)
          User = "dnsmasq";
          Group = "dnsmasq";
          
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
        dnsmasq-blocklist-update-homelab = {
        description = "Update dnsmasq Blocklists for HOMELAB";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "dnsmasq/homelab";
          User = "dnsmasq";
          Group = "dnsmasq";
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
                  print "address=/" $2 "/"
                }
              }' /tmp/blocklist-homelab-combined.txt | sort -u > /var/lib/dnsmasq/homelab/blocklist.conf.new
              
              BLOCKED_COUNT=$(wc -l < /var/lib/dnsmasq/homelab/blocklist.conf.new)
              echo "HOMELAB: Now blocking $BLOCKED_COUNT domains"
              
              mv /var/lib/dnsmasq/homelab/blocklist.conf.new /var/lib/dnsmasq/homelab/blocklist.conf
              rm /tmp/blocklist-homelab-combined.txt
              systemctl reload-or-restart dnsmasq-homelab || true
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
        dnsmasq-blocklist-update-lan = {
        description = "Update dnsmasq Blocklists for LAN";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "dnsmasq/lan";
          User = "dnsmasq";
          Group = "dnsmasq";
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
                  print "address=/" $2 "/"
                }
              }' /tmp/blocklist-lan-combined.txt | sort -u > /var/lib/dnsmasq/lan/blocklist.conf.new
              
              BLOCKED_COUNT=$(wc -l < /var/lib/dnsmasq/lan/blocklist.conf.new)
              echo "LAN: Now blocking $BLOCKED_COUNT domains"
              
              mv /var/lib/dnsmasq/lan/blocklist.conf.new /var/lib/dnsmasq/lan/blocklist.conf
              rm /tmp/blocklist-lan-combined.txt
              systemctl reload-or-restart dnsmasq-lan || true
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
        dnsmasq-dynamic-dns-homelab = {
          description = "Update dnsmasq Dynamic DNS for HOMELAB";
          serviceConfig = {
            Type = "oneshot";
            User = "dnsmasq";
            Group = "dnsmasq";
          };
          script = ''
            echo "Updating dynamic DNS for HOMELAB..."
            
            # Regenerate dynamic DNS entries
            > /var/lib/dnsmasq/homelab/dynamic-dns.conf
            
            ${if (homelabCfg.dhcp.dynamicDomain or "") != "" then ''
              if [ -f /var/lib/dnsmasq/homelab/dhcp.leases ]; then
                ${pkgs.gawk}/bin/awk -v domain="${homelabCfg.dhcp.dynamicDomain}" -v subnet="${homelabCfg.subnet}" '
                  BEGIN {
                    split(subnet, parts, "/");
                    network_prefix = parts[1];
                    split(network_prefix, octets, ".");
                    base = octets[1] "." octets[2] "." octets[3];
                  }
                  
                  # Parse dnsmasq lease file format: <expiry-time> <MAC> <IP> <hostname> <client-id>
                  {
                    if (NF >= 4) {
                      expiry = $1;
                      mac = $2;
                      ip = $3;
                      hostname = $4;
                      
                      # Check if IP is in our subnet
                      if (index(ip, base) == 1) {
                        # If hostname is "*" or empty, generate one from IP
                        if (hostname == "*" || hostname == "") {
                          split(ip, ip_parts, ".");
                          last_octet = ip_parts[4];
                          hostname = "dhcp-" last_octet;
                        }
                        
                        print "host-record=" hostname "." domain "," ip "  # Dynamic DHCP";
                      }
                    }
                  }
                ' /var/lib/dnsmasq/homelab/dhcp.leases > /var/lib/dnsmasq/homelab/dynamic-dns.conf
                
                # Reload dnsmasq
                systemctl reload-or-restart dnsmasq-homelab || true
                
                DYNAMIC_COUNT=$(wc -l < /var/lib/dnsmasq/homelab/dynamic-dns.conf)
                echo "HOMELAB: $DYNAMIC_COUNT dynamic DNS entries"
              fi
            '' else ""}
          '';
        };
      })
      
      (mkIf lanDnsEnabled {
        dnsmasq-dynamic-dns-lan = {
          description = "Update dnsmasq Dynamic DNS for LAN";
          serviceConfig = {
            Type = "oneshot";
            User = "dnsmasq";
            Group = "dnsmasq";
          };
          script = ''
            echo "Updating dynamic DNS for LAN..."
            
            # Regenerate dynamic DNS entries
            > /var/lib/dnsmasq/lan/dynamic-dns.conf
            
            ${if (lanCfg.dhcp.dynamicDomain or "") != "" then ''
              if [ -f /var/lib/dnsmasq/lan/dhcp.leases ]; then
                ${pkgs.gawk}/bin/awk -v domain="${lanCfg.dhcp.dynamicDomain}" -v subnet="${lanCfg.subnet}" '
                  BEGIN {
                    split(subnet, parts, "/");
                    network_prefix = parts[1];
                    split(network_prefix, octets, ".");
                    base = octets[1] "." octets[2] "." octets[3];
                  }
                  
                  # Parse dnsmasq lease file format: <expiry-time> <MAC> <IP> <hostname> <client-id>
                  {
                    if (NF >= 4) {
                      expiry = $1;
                      mac = $2;
                      ip = $3;
                      hostname = $4;
                      
                      # Check if IP is in our subnet
                      if (index(ip, base) == 1) {
                        # If hostname is "*" or empty, generate one from IP
                        if (hostname == "*" || hostname == "") {
                          split(ip, ip_parts, ".");
                          last_octet = ip_parts[4];
                          hostname = "dhcp-" last_octet;
                        }
                        
                        print "host-record=" hostname "." domain "," ip "  # Dynamic DHCP";
                      }
                    }
                  }
                ' /var/lib/dnsmasq/lan/dhcp.leases > /var/lib/dnsmasq/lan/dynamic-dns.conf
                
                # Reload dnsmasq
                systemctl reload-or-restart dnsmasq-lan || true
                
                DYNAMIC_COUNT=$(wc -l < /var/lib/dnsmasq/lan/dynamic-dns.conf)
                echo "LAN: $DYNAMIC_COUNT dynamic DNS entries"
              fi
            '' else ""}
          '';
        };
      })
    ];
    
    # Timer for HOMELAB blocklist updates
    systemd.timers.dnsmasq-blocklist-update-homelab = mkIf (homelabDnsEnabled && homelabBlocklistsEnabled) {
      description = "Update dnsmasq Blocklists for HOMELAB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";  # TODO: Use minimum of all blocklist intervals
        Persistent = true;
      };
    };
    
    # Timer for LAN blocklist updates
    systemd.timers.dnsmasq-blocklist-update-lan = mkIf (lanDnsEnabled && lanBlocklistsEnabled) {
      description = "Update dnsmasq Blocklists for LAN";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";  # TODO: Use minimum of all blocklist intervals
        Persistent = true;
      };
    };
    
    # Timers to periodically update dynamic DNS
    systemd.timers.dnsmasq-dynamic-dns-homelab = mkIf (homelabDnsEnabled && ((homelabCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Periodically update dnsmasq Dynamic DNS for HOMELAB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "5m";  # Update every 5 minutes
      };
    };
    
    systemd.timers.dnsmasq-dynamic-dns-lan = mkIf (lanDnsEnabled && ((lanCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Periodically update dnsmasq Dynamic DNS for LAN";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "5m";  # Update every 5 minutes
      };
    };
    
    # Watch DHCP lease file for changes
    systemd.paths.dnsmasq-dynamic-dns-homelab = mkIf (homelabDnsEnabled && ((homelabCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Watch DHCP leases for HOMELAB Dynamic DNS updates";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/var/lib/dnsmasq/homelab/dhcp.leases";
      };
    };
    
    systemd.paths.dnsmasq-dynamic-dns-lan = mkIf (lanDnsEnabled && ((lanCfg.dhcp.dynamicDomain or "") != "")) {
      description = "Watch DHCP leases for LAN Dynamic DNS updates";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/var/lib/dnsmasq/lan/dhcp.leases";
      };
    };
    
    # Create dnsmasq user and group
    users.users.dnsmasq = {
      isSystemUser = true;
      group = "dnsmasq";
      description = "dnsmasq DNS server user";
    };
    
    users.groups.dnsmasq = {};
    
    # Install dnsmasq package
    environment.systemPackages = with pkgs; [
      dnsmasq
    ];
    
    # Open firewall for DNS and DHCP
    networking.firewall.interfaces = {
      br0.allowedUDPPorts = [ 53 ] ++ (if homelabDhcpEnabled then [ 67 ] else []);
      br0.allowedTCPPorts = [ 53 ];
      br1.allowedUDPPorts = [ 53 ] ++ (if lanDhcpEnabled then [ 67 ] else []);
      br1.allowedTCPPorts = [ 53 ];
    };
  };
}
