{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  
  # Extract bridge information from config
  bridges = routerConfig.lan.bridges;
  bridgeNames = map (b: b.name) bridges;

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

  # Build DHCP subnets from config
  dhcpSubnets = [
    # HOMELAB network
    {
      id = 1;
      subnet = routerConfig.homelab.subnet;
      pools = [{
        pool = "${routerConfig.homelab.dhcp.start} - ${routerConfig.homelab.dhcp.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.homelab.ipAddress; }
        { name = "domain-name-servers"; data = routerConfig.homelab.ipAddress; }
        { name = "domain-name"; data = routerConfig.homelab.domain; }
      ];
      valid-lifetime = leaseToSeconds routerConfig.homelab.dhcp.leaseTime;
    }
    # LAN network
    {
      id = 2;
      subnet = routerConfig.lan.subnet;
      pools = [{
        pool = "${routerConfig.lan.dhcp.start} - ${routerConfig.lan.dhcp.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.lan.ipAddress; }
        { name = "domain-name-servers"; data = routerConfig.lan.ipAddress; }
        { name = "domain-name"; data = routerConfig.lan.domain; }
      ];
      valid-lifetime = leaseToSeconds routerConfig.lan.dhcp.leaseTime;
    }
  ];

in

{
  # Kea DHCP4 Server
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config = {
        # Listen on all bridge interfaces
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

  # Firewall rules for DHCP
  networking.firewall.allowedUDPPorts = mkAfter [ 67 ];
}

