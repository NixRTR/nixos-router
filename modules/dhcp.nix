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
      subnet = "${routerConfig.dhcp.homelab.network}/${toString routerConfig.dhcp.homelab.prefix}";
      pools = [{
        pool = "${routerConfig.dhcp.homelab.start} - ${routerConfig.dhcp.homelab.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.dhcp.homelab.gateway; }
        { name = "domain-name-servers"; data = routerConfig.dhcp.homelab.dns; }
      ];
      valid-lifetime = leaseToSeconds routerConfig.dhcp.homelab.leaseTime;
    }
    # LAN network
    {
      id = 2;
      subnet = "${routerConfig.dhcp.lan.network}/${toString routerConfig.dhcp.lan.prefix}";
      pools = [{
        pool = "${routerConfig.dhcp.lan.start} - ${routerConfig.dhcp.lan.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.dhcp.lan.gateway; }
        { name = "domain-name-servers"; data = routerConfig.dhcp.lan.dns; }
      ];
      valid-lifetime = leaseToSeconds routerConfig.dhcp.lan.leaseTime;
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

