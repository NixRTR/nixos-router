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
  
  # Get forward_unlisted settings (default to false for backward compatibility)
  homelabForwardUnlisted = homelabDns.forward_unlisted or false;
  lanForwardUnlisted = lanDns.forward_unlisted or false;
  
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

  # DHCP option 15 (domain name / Windows DNS suffix). If unset, derived from A records (legacy).
  # If set to "", omit option 15 entirely. See dhcp-*.nix comments: apex wildcards (*.zone) + same suffix break public names.
  dhcpOption15OrNull = dhcpCfg: aRecords:
    let
      v =
        if builtins.hasAttr "option15Domain" dhcpCfg
        then dhcpCfg.option15Domain
        else extractDomain aRecords;
    in
      if v == "" then null else v;
  
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

  homelabDhcpOption15 = dhcpOption15OrNull homelabCfg.dhcp (homelabDns.a_records or {});
  lanDhcpOption15 = dhcpOption15OrNull lanCfg.dhcp (lanDns.a_records or {});
  
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

  # Shell snippet that writes a network's DHCP lease names to hosts.d/dynamic (hosts format).
  # dnsmasq watches hosts.d through hostsdir= and picks up changes by itself, so a lease
  # change never needs a dnsmasq restart.
  mkDynamicHostsScript = name: label: netCfg: ''
    mkdir -p /var/lib/dnsmasq/${name}/hosts.d
    ${if (netCfg.dhcp.dynamicDomain or "") != "" then ''
      if [ -f /var/lib/dnsmasq/${name}/dhcp.leases ]; then
        ${pkgs.gawk}/bin/awk -v domain="${netCfg.dhcp.dynamicDomain}" -v subnet="${netCfg.subnet}" '
          BEGIN {
            split(subnet, parts, "/");
            network_prefix = parts[1];
            split(network_prefix, octets, ".");
            base = octets[1] "." octets[2] "." octets[3];
          }

          # Parse dnsmasq lease file format: <expiry-time> <MAC> <IP> <hostname> <client-id>
          {
            if (NF >= 4) {
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

                print ip " " hostname "." domain;
              }
            }
          }
        ' /var/lib/dnsmasq/${name}/dhcp.leases > /var/lib/dnsmasq/${name}/hosts.d/.dynamic.tmp
      else
        : > /var/lib/dnsmasq/${name}/hosts.d/.dynamic.tmp
      fi

      # Only replace the file when it changed (a plain renewal changes nothing).
      # dnsmasq ignores dotfiles in hosts.d, so the temp file is never loaded.
      if ${pkgs.diffutils}/bin/cmp -s /var/lib/dnsmasq/${name}/hosts.d/.dynamic.tmp /var/lib/dnsmasq/${name}/hosts.d/dynamic; then
        rm -f /var/lib/dnsmasq/${name}/hosts.d/.dynamic.tmp
      else
        mv /var/lib/dnsmasq/${name}/hosts.d/.dynamic.tmp /var/lib/dnsmasq/${name}/hosts.d/dynamic
        echo "${label}: $(wc -l < /var/lib/dnsmasq/${name}/hosts.d/dynamic) dynamic DNS entries"
      fi
    '' else ''
      rm -f /var/lib/dnsmasq/${name}/hosts.d/dynamic
    ''}
  '';

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
          
          # Blocklists are refreshed by dnsmasq-blocklist-update-homelab, not here:
          # a slow download must never hold up DNS/DHCP startup
          ${if homelabBlocklistUrls == [] then ''
            : > /var/lib/dnsmasq/homelab/blocklist.conf
          '' else ''
            [ -f /var/lib/dnsmasq/homelab/blocklist.conf ] || touch /var/lib/dnsmasq/homelab/blocklist.conf
          ''}

          # Generate dynamic DNS entries from DHCP leases
          ${mkDynamicHostsScript "homelab" "HOMELAB" homelabCfg}
          rm -f /var/lib/dnsmasq/homelab/dynamic-dns.conf
          
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
          
          # Local domain (only set domain= in fully hosted mode)
          ${if homelabPrimaryDomain != "local" && !homelabForwardUnlisted then ''
            domain=${homelabPrimaryDomain}
          '' else ""}
          # Only use local= if we don't have wildcards (address= handles wildcards and local resolution)
          # AND if forward_unlisted is false (fully hosted mode)
          ${if homelabPrimaryDomain != "local" && homelabWildcards == [] && !homelabForwardUnlisted then "local=/${homelabPrimaryDomain}/" else ""}
          
          # Wildcard domains (from CNAME records)
          # address=/domain/IP makes all subdomains resolve to that IP
          # This also marks the domain as local, so we don't need local= when wildcards exist
          ${concatStringsSep "\n" (map (wildcard: 
            "address=/${wildcard.domain}/${wildcard.ip}${if (wildcard.comment or "") != "" && wildcard.comment != null then "  # ${wildcard.comment}" else ""}"
          ) homelabWildcards)}
          
          # Specific host records (override wildcards)
          ${concatStringsSep "\n" (map (record: 
            "host-record=${record.hostname},${record.ip}${if (record.comment or "") != "" && record.comment != null then "  # ${record.comment}" else ""}"
          ) homelabAllHostRecords)}
          
          # Whitelist - domains that should never be blocked
          ${concatMapStringsSep "\n" (domain: "server=/${domain}/  # Whitelisted") (homelabDns.whitelist or [])}
          
          # Include blocklists and dynamic DNS
          conf-file=/var/lib/dnsmasq/homelab/blocklist.conf
          hostsdir=/var/lib/dnsmasq/homelab/hosts.d
          
          # WebUI-managed configurations (may not exist if WebUI hasn't written them yet)
          conf-file=/var/lib/dnsmasq/homelab/webui-dns.conf
          ${if homelabDhcpEnabled then "conf-file=/var/lib/dnsmasq/homelab/webui-dhcp.conf" else ""}
          
          # DHCP Configuration (static reservations come from webui-dhcp.conf only to avoid duplicate "multiple names" errors)
          ${if homelabDhcpEnabled then ''
            dhcp-range=${homelabBridge},${homelabCfg.dhcp.start},${homelabCfg.dhcp.end},${homelabCfg.dhcp.leaseTime}
            dhcp-option=${homelabBridge},3,${homelabCfg.ipAddress}
            dhcp-option=${homelabBridge},6${concatMapStringsSep "," (s: ",${s}") (homelabCfg.dhcp.dnsServers or [ homelabCfg.ipAddress ])}
            ${lib.optionalString (homelabDhcpOption15 != null) "dhcp-option=${homelabBridge},15,${homelabDhcpOption15}"}
            dhcp-authoritative
            dhcp-leasefile=/var/lib/dnsmasq/homelab/dhcp.leases
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
          
          # Generate initial WebUI DNS config from router-config.nix (if file doesn't exist)
          # This ensures dnsmasq can start even before WebUI has written configs
          if [ ! -f /var/lib/dnsmasq/homelab/webui-dns.conf ]; then
            cat > /var/lib/dnsmasq/homelab/webui-dns.conf << WEBUI_DNS_EOF
          # WebUI-managed DNS configuration
          # Generated automatically from router-config.nix - do not edit manually
          
          ${if homelabPrimaryDomain != "local" && homelabWildcards == [] && !homelabForwardUnlisted then "local=/${homelabPrimaryDomain}/" else ""}
          ${concatStringsSep "\n" (map (wildcard: 
            "address=/${wildcard.domain}/${wildcard.ip}${if (wildcard.comment or "") != "" && wildcard.comment != null then "  # ${wildcard.comment}" else ""}"
          ) homelabWildcards)}
          ${concatStringsSep "\n" (map (record: 
            "host-record=${record.hostname},${record.ip}${if (record.comment or "") != "" && record.comment != null then "  # ${record.comment}" else ""}"
          ) homelabAllHostRecords)}
          WEBUI_DNS_EOF
          fi
          
          # Generate initial WebUI DHCP config from router-config.nix (if file doesn't exist and DHCP is enabled)
          if [ ! -f /var/lib/dnsmasq/homelab/webui-dhcp.conf ] && [ "${if homelabDhcpEnabled then "1" else "0"}" = "1" ]; then
            cat > /var/lib/dnsmasq/homelab/webui-dhcp.conf << WEBUI_DHCP_EOF
          # WebUI-managed DHCP configuration
          # Generated automatically from router-config.nix - do not edit manually
          
          ${concatStringsSep "\n" (map (res: 
            "dhcp-host=${res.hwAddress},${res.hostname},${res.ipAddress}  # Static reservation"
          ) (homelabCfg.dhcp.reservations or []))}
          WEBUI_DHCP_EOF
          fi
          
          # Set proper ownership
          chown dnsmasq:dnsmasq /var/lib/dnsmasq/homelab/webui-dns.conf /var/lib/dnsmasq/homelab/webui-dhcp.conf 2>/dev/null || true
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
          
          # Allow binding to privileged port 53 and DHCP configuration
          # CAP_NET_BIND_SERVICE: bind to port 53 (DNS)
          # CAP_NET_ADMIN: configure network interfaces for DHCP
          # CAP_NET_RAW: send raw packets for DHCP
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          
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
          
          # Blocklists are refreshed by dnsmasq-blocklist-update-lan, not here:
          # a slow download must never hold up DNS/DHCP startup
          ${if lanBlocklistUrls == [] then ''
            : > /var/lib/dnsmasq/lan/blocklist.conf
          '' else ''
            [ -f /var/lib/dnsmasq/lan/blocklist.conf ] || touch /var/lib/dnsmasq/lan/blocklist.conf
          ''}

          # Generate dynamic DNS entries from DHCP leases
          ${mkDynamicHostsScript "lan" "LAN" lanCfg}
          rm -f /var/lib/dnsmasq/lan/dynamic-dns.conf
          
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
          
          # Local domain (only set domain= in fully hosted mode)
          ${if lanPrimaryDomain != "local" && !lanForwardUnlisted then ''
            domain=${lanPrimaryDomain}
          '' else ""}
          # Only use local= if we don't have wildcards (address= handles wildcards and local resolution)
          # AND if forward_unlisted is false (fully hosted mode)
          ${if lanPrimaryDomain != "local" && lanWildcards == [] && !lanForwardUnlisted then "local=/${lanPrimaryDomain}/" else ""}
          
          # Wildcard domains (from CNAME records)
          # address=/domain/IP makes all subdomains resolve to that IP
          # This also marks the domain as local, so we don't need local= when wildcards exist
          ${concatStringsSep "\n" (map (wildcard: 
            "address=/${wildcard.domain}/${wildcard.ip}${if (wildcard.comment or "") != "" && wildcard.comment != null then "  # ${wildcard.comment}" else ""}"
          ) lanWildcards)}
          
          # Specific host records (override wildcards)
          ${concatStringsSep "\n" (map (record: 
            "host-record=${record.hostname},${record.ip}${if (record.comment or "") != "" && record.comment != null then "  # ${record.comment}" else ""}"
          ) lanAllHostRecords)}
          
          # Whitelist - domains that should never be blocked
          ${concatMapStringsSep "\n" (domain: "server=/${domain}/  # Whitelisted") (lanDns.whitelist or [])}
          
          # Include blocklists and dynamic DNS
          conf-file=/var/lib/dnsmasq/lan/blocklist.conf
          hostsdir=/var/lib/dnsmasq/lan/hosts.d
          
          # WebUI-managed configurations (may not exist if WebUI hasn't written them yet)
          conf-file=/var/lib/dnsmasq/lan/webui-dns.conf
          ${if lanDhcpEnabled then "conf-file=/var/lib/dnsmasq/lan/webui-dhcp.conf" else ""}
          
          # DHCP Configuration (static reservations come from webui-dhcp.conf only to avoid duplicate "multiple names" errors)
          ${if lanDhcpEnabled then ''
            dhcp-range=${lanBridge},${lanCfg.dhcp.start},${lanCfg.dhcp.end},${lanCfg.dhcp.leaseTime}
            dhcp-option=${lanBridge},3,${lanCfg.ipAddress}
            dhcp-option=${lanBridge},6${concatMapStringsSep "," (s: ",${s}") (lanCfg.dhcp.dnsServers or [ lanCfg.ipAddress ])}
            ${lib.optionalString (lanDhcpOption15 != null) "dhcp-option=${lanBridge},15,${lanDhcpOption15}"}
            dhcp-authoritative
            dhcp-leasefile=/var/lib/dnsmasq/lan/dhcp.leases
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
          
          # Generate initial WebUI DNS config from router-config.nix (if file doesn't exist)
          # This ensures dnsmasq can start even before WebUI has written configs
          if [ ! -f /var/lib/dnsmasq/lan/webui-dns.conf ]; then
            cat > /var/lib/dnsmasq/lan/webui-dns.conf << WEBUI_DNS_EOF
          # WebUI-managed DNS configuration
          # Generated automatically from router-config.nix - do not edit manually
          
          ${if lanPrimaryDomain != "local" && lanWildcards == [] && !lanForwardUnlisted then "local=/${lanPrimaryDomain}/" else ""}
          ${concatStringsSep "\n" (map (wildcard: 
            "address=/${wildcard.domain}/${wildcard.ip}${if (wildcard.comment or "") != "" && wildcard.comment != null then "  # ${wildcard.comment}" else ""}"
          ) lanWildcards)}
          ${concatStringsSep "\n" (map (record: 
            "host-record=${record.hostname},${record.ip}${if (record.comment or "") != "" && record.comment != null then "  # ${record.comment}" else ""}"
          ) lanAllHostRecords)}
          WEBUI_DNS_EOF
          fi
          
          # Generate initial WebUI DHCP config from router-config.nix (if file doesn't exist and DHCP is enabled)
          if [ ! -f /var/lib/dnsmasq/lan/webui-dhcp.conf ] && [ "${if lanDhcpEnabled then "1" else "0"}" = "1" ]; then
            cat > /var/lib/dnsmasq/lan/webui-dhcp.conf << WEBUI_DHCP_EOF
          # WebUI-managed DHCP configuration
          # Generated automatically from router-config.nix - do not edit manually
          
          ${concatStringsSep "\n" (map (res: 
            "dhcp-host=${res.hwAddress},${res.hostname},${res.ipAddress}  # Static reservation"
          ) (lanCfg.dhcp.reservations or []))}
          WEBUI_DHCP_EOF
          fi
          
          # Set proper ownership
          chown dnsmasq:dnsmasq /var/lib/dnsmasq/lan/webui-dns.conf /var/lib/dnsmasq/lan/webui-dhcp.conf 2>/dev/null || true
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
          
          # Allow binding to privileged port 53 and DHCP configuration
          # CAP_NET_BIND_SERVICE: bind to port 53 (DNS)
          # CAP_NET_ADMIN: configure network interfaces for DHCP
          # CAP_NET_RAW: send raw packets for DHCP
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          
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
              ${pkgs.curl}/bin/curl -s -f -L --connect-timeout 10 --max-time 60 "${url}" >> /tmp/blocklist-homelab-combined.txt || echo "Warning: Failed to download ${url}"
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
              
              if ${pkgs.diffutils}/bin/cmp -s /var/lib/dnsmasq/homelab/blocklist.conf.new /var/lib/dnsmasq/homelab/blocklist.conf; then
                echo "HOMELAB: blocklist unchanged"
                rm /var/lib/dnsmasq/homelab/blocklist.conf.new
              else
                mv /var/lib/dnsmasq/homelab/blocklist.conf.new /var/lib/dnsmasq/homelab/blocklist.conf
                # dnsmasq only reads the blocklist at startup; ExecStartPost restarts it (as root)
                touch /var/lib/dnsmasq/homelab/.blocklist-changed
              fi
              rm /tmp/blocklist-homelab-combined.txt
            else
              echo "No blocklists downloaded for HOMELAB"
            fi
            
            echo "=== HOMELAB blocklist update completed ==="
          ''}";
          # "+" runs this as root: the dnsmasq user is not allowed to restart the service
          ExecStartPost = "+${pkgs.writeShellScript "apply-blocklists-homelab" ''
            if [ -e /var/lib/dnsmasq/homelab/.blocklist-changed ]; then
              rm -f /var/lib/dnsmasq/homelab/.blocklist-changed
              ${pkgs.systemd}/bin/systemctl try-restart dnsmasq-homelab.service
            fi
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
              ${pkgs.curl}/bin/curl -s -f -L --connect-timeout 10 --max-time 60 "${url}" >> /tmp/blocklist-lan-combined.txt || echo "Warning: Failed to download ${url}"
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
              
              if ${pkgs.diffutils}/bin/cmp -s /var/lib/dnsmasq/lan/blocklist.conf.new /var/lib/dnsmasq/lan/blocklist.conf; then
                echo "LAN: blocklist unchanged"
                rm /var/lib/dnsmasq/lan/blocklist.conf.new
              else
                mv /var/lib/dnsmasq/lan/blocklist.conf.new /var/lib/dnsmasq/lan/blocklist.conf
                # dnsmasq only reads the blocklist at startup; ExecStartPost restarts it (as root)
                touch /var/lib/dnsmasq/lan/.blocklist-changed
              fi
              rm /tmp/blocklist-lan-combined.txt
            else
              echo "No blocklists downloaded for LAN"
            fi
            
            echo "=== LAN blocklist update completed ==="
          ''}";
          # "+" runs this as root: the dnsmasq user is not allowed to restart the service
          ExecStartPost = "+${pkgs.writeShellScript "apply-blocklists-lan" ''
            if [ -e /var/lib/dnsmasq/lan/.blocklist-changed ]; then
              rm -f /var/lib/dnsmasq/lan/.blocklist-changed
              ${pkgs.systemd}/bin/systemctl try-restart dnsmasq-lan.service
            fi
          ''}";
        };
      };
      })
      
      # Dynamic DNS updater services (started by the .path units below when the lease file changes)
      (mkIf homelabDnsEnabled {
        dnsmasq-dynamic-dns-homelab = {
          description = "Update dnsmasq Dynamic DNS for HOMELAB";
          # Runs on every lease file write; never let a burst of leases trip the start limit
          startLimitIntervalSec = 0;
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "dnsmasq/homelab";
            User = "dnsmasq";
            Group = "dnsmasq";
            # Let a burst of lease changes settle so they are handled in one run
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
          };
          script = mkDynamicHostsScript "homelab" "HOMELAB" homelabCfg;
        };
      })
      
      (mkIf lanDnsEnabled {
        dnsmasq-dynamic-dns-lan = {
          description = "Update dnsmasq Dynamic DNS for LAN";
          # Runs on every lease file write; never let a burst of leases trip the start limit
          startLimitIntervalSec = 0;
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "dnsmasq/lan";
            User = "dnsmasq";
            Group = "dnsmasq";
            # Let a burst of lease changes settle so they are handled in one run
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
          };
          script = mkDynamicHostsScript "lan" "LAN" lanCfg;
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
