{ config, lib, pkgs, ... }:

with lib;

let
  routerCfg = config.router;
  technitiumCfg = routerCfg.technitium;
  lanCfg = routerCfg.lan;
  dnsmasqCfg = routerCfg.dnsmasq;

  routerIPv4 = lanCfg.ipv4.address;
  bridgeName = lanCfg.bridge.name;

  prefixToNetmask = prefix:
    let
      fullOctets = prefix / 8;
      remainder = prefix - fullOctets * 8;
      partialOctet =
        if remainder == 0 then 0 else 256 - builtins.pow 2 (8 - remainder);
      octetValue = idx:
        if idx < fullOctets then 255
        else if idx == fullOctets then (if remainder == 0 then 0 else partialOctet)
        else 0;
      octets = map octetValue (lib.range 0 3);
    in concatStringsSep "." (map toString octets);

  defaultDhcpInterfaces =
    if technitiumCfg.dhcp.interfaces != [ ] then technitiumCfg.dhcp.interfaces else [ bridgeName ];

  defaultDhcpDnsServers =
    if technitiumCfg.dhcp.dnsServers != [ ] then technitiumCfg.dhcp.dnsServers else [ routerIPv4 ];

  defaultForwarders =
    if technitiumCfg.upstreamServers != [ ] then technitiumCfg.upstreamServers else [ ];

  defaultListenAddresses =
    if technitiumCfg.listenAddresses != [ ] then technitiumCfg.listenAddresses else [ routerIPv4 ];

  dhcpRangeStart = dnsmasqCfg.rangeStart;
  dhcpRangeEnd = dnsmasqCfg.rangeEnd;

  leaseDurationSeconds =
    let
      lease = technitiumCfg.dhcp.leaseTime;
      numeric = builtins.match "^[0-9]+$" lease;
      unitMatch = builtins.match "^([0-9]+)([smhd])$" lease;
      unitMultiplier = unit:
        if unit == "s" then 1
        else if unit == "m" then 60
        else if unit == "h" then 3600
        else if unit == "d" then 86400
        else 1;
    in if technitiumCfg.dhcp.leaseTimeSeconds != null then technitiumCfg.dhcp.leaseTimeSeconds
       else if numeric != null then lib.toInt lease
       else if unitMatch != null then
         let
           num = lib.toInt (builtins.elemAt unitMatch 0);
           unit = builtins.elemAt unitMatch 1;
         in num * unitMultiplier unit
       else 300;

  technitiumSettings = {
    "DnsServerLocalEndPoints" =
      concatMap
        (addr:
          [ "${addr}:53" ]
          ++ optional technitiumCfg.enableDoT "${addr}:${toString technitiumCfg.ports.dot}"
          ++ optional technitiumCfg.enableDoH "${addr}:${toString technitiumCfg.ports.doh}"
        )
        defaultListenAddresses;

    "DnsServerForwarders" = defaultForwarders;
    "DnsServerUseSystemResolver" = technitiumCfg.useSystemResolver;
    "DnsServerListenOnLoopback" = technitiumCfg.listenOnLoopback;

    "EnableDhcpServer" = technitiumCfg.dhcp.enable;
    "DhcpServerInterfaces" = defaultDhcpInterfaces;
    "DhcpServerAddressRange" = {
      "Start" = dhcpRangeStart;
      "End" = dhcpRangeEnd;
    };
    "DhcpServerGateway" = routerIPv4;
    "DhcpServerSubnetMask" = prefixToNetmask lanCfg.ipv4.prefixLength;
    "DhcpServerDnsServers" = defaultDhcpDnsServers;
    "DhcpServerLeaseDuration" = leaseDurationSeconds;
  } // technitiumCfg.extraSettings;
in
{
  options.router.technitium = {
    enable = mkEnableOption "Technitium DNS server integration";

    package = mkOption {
      type = types.package;
      default = pkgs.technitium-dns-server;
      description = "Technitium DNS Server package to deploy.";
    };

    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "IPv4/IPv6 addresses Technitium should bind to for DNS services. Default uses the LAN address.";
    };

    useSystemResolver = mkOption {
      type = types.bool;
      default = false;
      description = "Allow Technitium to forward queries via the system resolver when no forwarders are provided.";
    };

    listenOnLoopback = mkOption {
      type = types.bool;
      default = true;
      description = "Expose DNS listeners on the loopback interface.";
    };

    enableDoT = mkOption {
      type = types.bool;
      default = false;
      description = "Enable DNS-over-TLS listener on the configured DoT port.";
    };

    enableDoH = mkOption {
      type = types.bool;
      default = false;
      description = "Enable DNS-over-HTTPS listener on the configured DoH port.";
    };

    enableHttps = mkOption {
      type = types.bool;
      default = false;
      description = "Serve the management UI over HTTPS.";
    };

    upstreamServers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "1.1.1.1" "1.0.0.1" ];
      description = "Upstream resolvers Technitium will forward to.";
    };

    ports = {
      web = mkOption {
        type = types.port;
        default = 5380;
        description = "HTTP port for the Technitium management UI.";
      };
      webTls = mkOption {
        type = types.port;
        default = 53443;
        description = "HTTPS port for the Technitium management UI.";
      };
      dot = mkOption {
        type = types.port;
        default = 853;
        description = "Port for DNS-over-TLS.";
      };
      doh = mkOption {
        type = types.port;
        default = 5443;
        description = "Port for DNS-over-HTTPS.";
      };
    } // optionalAttrs technitiumCfg.enableDoH {
      "WebServiceDoHEndpoints" =
        map (addr: "https://${addr}:${toString technitiumCfg.ports.doh}/dns-query") defaultListenAddresses;
    };

    dhcp = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the built-in DHCP server.";
      };
      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Interfaces Technitium should serve DHCP on. Defaults to the LAN bridge.";
      };
      dnsServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of DNS servers handed to DHCP clients. Defaults to the router itself.";
      };
      leaseTime = mkOption {
        type = types.str;
        default = dnsmasqCfg.leaseTime;
        description = "Human readable lease time (e.g. \"5m\", \"12h\").";
      };
      leaseTimeSeconds = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Optional explicit lease duration override in seconds.";
      };
    };

    extraSettings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Raw Technitium settings merged into the generated configuration.";
    };
  };

  config = mkIf technitiumCfg.enable {
    services.dnsmasq.enable = mkForce false;

    services.technitium-dns-server = {
      enable = true;
      package = technitiumCfg.package;
      openFirewall = true;
      firewallTCPPorts =
        [ 53 technitiumCfg.ports.web ]
        ++ optional technitiumCfg.enableHttps technitiumCfg.ports.webTls
        ++ optional technitiumCfg.enableDoT technitiumCfg.ports.dot
        ++ optional technitiumCfg.enableDoH technitiumCfg.ports.doh;
      firewallUDPPorts =
        [ 53 ]
        ++ optionals technitiumCfg.dhcp.enable [ 67 68 ];
      settings =
        technitiumSettings
        // {
          "WebServiceHttpEndpoints" = [ "http://${routerIPv4}:${toString technitiumCfg.ports.web}" ];
          "WebServiceHttpsEndpoints" =
            optional technitiumCfg.enableHttps "https://${routerIPv4}:${toString technitiumCfg.ports.webTls}";
          "EnableHttpWebService" = true;
          "EnableHttpsWebService" = technitiumCfg.enableHttps;
        }
        // optionalAttrs technitiumCfg.enableDoH {
          "WebServiceDoHEndpoints" =
            map (addr: "https://${addr}:${toString technitiumCfg.ports.doh}/dns-query") defaultListenAddresses;
        };
    };

    networking.firewall.allowedUDPPorts = mkAfter (
      [ 53 ] ++ optionals technitiumCfg.dhcp.enable [ 67 68 ]
    );
    networking.firewall.allowedTCPPorts = mkAfter (
      [ 53 technitiumCfg.ports.web ]
      ++ optional technitiumCfg.enableHttps technitiumCfg.ports.webTls
      ++ optional technitiumCfg.enableDoT technitiumCfg.ports.dot
      ++ optional technitiumCfg.enableDoH technitiumCfg.ports.doh
    );
  };
}

