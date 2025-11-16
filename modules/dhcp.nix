{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  
  # Extract bridge information from config
  bridges = routerConfig.lan.bridges;
  
  # Get enabled DHCP networks to determine which interfaces to listen on
  homelabDhcpEnabled = routerConfig.homelab.dhcp.enable or true;
  lanDhcpEnabled = routerConfig.lan.dhcp.enable or true;
  
  # Build list of bridge names where DHCP is enabled
  bridgeNames = 
    (lib.optional homelabDhcpEnabled "br0") ++
    (lib.optional lanDhcpEnabled "br1");

  # Helper function to extract domain from first A record
  # Takes the domain from the first A record key (e.g., "jeandr.net" from "server.jeandr.net")
  extractDomain = aRecords:
    if aRecords == {} || aRecords == null then "local"
    else
      let
        firstRecord = builtins.head (builtins.attrNames aRecords);
        parts = lib.splitString "." firstRecord;
        # Get last two parts (e.g., "jeandr.net" from "server.jeandr.net")
        # Or just use the full name if it's already a domain
        numParts = builtins.length parts;
      in
        if numParts >= 2 then
          "${builtins.elemAt parts (numParts - 2)}.${builtins.elemAt parts (numParts - 1)}"
        else firstRecord;

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

  # Build DHCP subnets from config (only enabled networks)
  dhcpSubnets = 
    (lib.optional (routerConfig.homelab.dhcp.enable or true) {
      id = 1;
      subnet = routerConfig.homelab.subnet;
      pools = [{
        pool = "${routerConfig.homelab.dhcp.start} - ${routerConfig.homelab.dhcp.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.homelab.ipAddress; }
        { name = "domain-name-servers"; data = builtins.concatStringsSep ", " (routerConfig.homelab.dhcp.dnsServers or [ routerConfig.homelab.ipAddress ]); }
        { name = "domain-name"; data = extractDomain (routerConfig.homelab.dns.a_records or {}); }
      ];
      valid-lifetime = leaseToSeconds routerConfig.homelab.dhcp.leaseTime;
      # Static reservations for HOMELAB
      reservations = map (res: {
        hostname = res.hostname;
        hw-address = res.hwAddress;
        ip-address = res.ipAddress;
      }) (routerConfig.homelab.dhcp.reservations or []);
    }) ++
    (lib.optional (routerConfig.lan.dhcp.enable or true) {
      id = 2;
      subnet = routerConfig.lan.subnet;
      pools = [{
        pool = "${routerConfig.lan.dhcp.start} - ${routerConfig.lan.dhcp.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.lan.ipAddress; }
        { name = "domain-name-servers"; data = builtins.concatStringsSep ", " (routerConfig.lan.dhcp.dnsServers or [ routerConfig.lan.ipAddress ]); }
        { name = "domain-name"; data = extractDomain (routerConfig.lan.dns.a_records or {}); }
      ];
      valid-lifetime = leaseToSeconds routerConfig.lan.dhcp.leaseTime;
      # Static reservations for LAN
      reservations = map (res: {
        hostname = res.hostname;
        hw-address = res.hwAddress;
        ip-address = res.ipAddress;
      }) (routerConfig.lan.dhcp.reservations or []);
    });

in

{
  # Kea DHCP4 Server - only enable if at least one network has DHCP enabled
  services.kea.dhcp4 = mkIf (homelabDhcpEnabled || lanDhcpEnabled) {
    enable = true;
    settings = {
      interfaces-config = {
        # Listen on bridge interfaces where DHCP is enabled
        interfaces = bridgeNames;
      };
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };
      # Use per-subnet option-data instead of global
      # Each subnet defines its own gateway and DNS
      subnet4 = dhcpSubnets;
    };
  };

  # Firewall rules for DHCP - only if service is enabled
  networking.firewall.allowedUDPPorts = mkIf (homelabDhcpEnabled || lanDhcpEnabled) (mkAfter [ 67 ]);
}

