{ config, lib, ... }:

with lib;

let
  cfg = config.router;
  wanCfg = cfg.wan;
  wanType = wanCfg.type;
  wanInterface = wanCfg.interface;
  staticCfg = wanCfg.static;
  pppoeCfg = wanCfg.pppoe;
  pptpCfg = wanCfg.pptp;
  lanCfg = cfg.lan;
  firewallCfg = cfg.firewall;
  natCfg = cfg.nat;
  dnsmasqCfg = cfg.dnsmasq;

  bridgeName = lanCfg.bridge.name;

  routerIPv4 = lanCfg.ipv4.address;

  dhcpRange =
    "${dnsmasqCfg.rangeStart},${dnsmasqCfg.rangeEnd},${dnsmasqCfg.leaseTime}";

  dnsServers =
    if dnsmasqCfg.dnsServers != [ ]
    then dnsmasqCfg.dnsServers
    else [ routerIPv4 ];

  dhcpOptions =
    [ "option:router,${routerIPv4}" ]
    ++ map (server: "option:dns-server,${server}") dnsServers
    ++ dnsmasqCfg.dhcpOptionsExtra;

  staticLeaseEntries =
    map (lease:
      let
        base = [ lease.mac ]
          ++ optional (lease.hostname != null) lease.hostname;
      in
        concatStringsSep "," (base ++ [ lease.ip ])
    ) dnsmasqCfg.staticLeases;

  pxeBootComponents =
    [ dnsmasqCfg.pxe.filename ]
    ++ optional (dnsmasqCfg.pxe.serverHostname != null) dnsmasqCfg.pxe.serverHostname
    ++ optional (dnsmasqCfg.pxe.serverAddress != null) dnsmasqCfg.pxe.serverAddress;

  pxeBootValue =
    concatStringsSep "," (filter (entry: entry != "") pxeBootComponents);

  dnsmasqBaseSettings =
    {
      "dhcp-range" = dhcpRange;
      "dhcp-option" = dhcpOptions;
      "bind-interfaces" = true;  # Only bind to specified interfaces
    }
    // optionalAttrs dnsmasqCfg.domainNeeded { "domain-needed" = true; }
    // optionalAttrs dnsmasqCfg.bogusPriv { "bogus-priv" = true; }
    // optionalAttrs (dnsmasqCfg.domain != null) {
      domain = dnsmasqCfg.domain;
      "expand-hosts" = dnsmasqCfg.expandHosts;
    }
    // optionalAttrs (dnsmasqCfg.authoritative) { "dhcp-authoritative" = true; }
    // optionalAttrs (dnsmasqCfg.listenAddresses != [ ]) {
      "listen-address" = dnsmasqCfg.listenAddresses;
    }
    // optionalAttrs (dnsmasqCfg.tftpRoot != null) {
      "enable-tftp" = true;
      "tftp-root" = dnsmasqCfg.tftpRoot;
    }
    // optionalAttrs (dnsmasqCfg.pxe.enable && pxeBootValue != "") {
      "dhcp-boot" = pxeBootValue;
    }
    // optionalAttrs (staticLeaseEntries != [ ]) {
      "dhcp-host" = staticLeaseEntries;
    };

  dnsmasqInterfaces = unique ([ bridgeName ] ++ dnsmasqCfg.extraInterfaces);

  natExternalInterface =
    if natCfg.externalInterface != null then natCfg.externalInterface
    else if wanType == "pppoe" then pppoeCfg.logicalInterface
    else if wanType == "pptp" then pptpCfg.logicalInterface
    else wanInterface;

  portRangeType = types.submodule ({ ... }: {
    options = {
      from = mkOption {
        type = types.port;
        description = "Starting port in the range.";
      };
      to = mkOption {
        type = types.port;
        description = "Ending port in the range.";
      };
    };
  });

  portSpecType = types.either types.port portRangeType;

  expandPortSpec = spec:
    if spec ? from then
      let
        start = spec.from;
        stop = spec.to;
      in if start > stop then
        throw "router.portForwards: range start must be <= end"
      else
        range start stop
    else [ spec ];

  mkPortPairs = forward:
    let
      externalPorts = expandPortSpec forward.externalPort;
      destinationPortsRaw =
        if forward.destinationPort == null then externalPorts
        else expandPortSpec forward.destinationPort;
      destinationPorts =
        if (builtins.length destinationPortsRaw) == (builtins.length externalPorts) then destinationPortsRaw
        else throw "router.portForwards: destinationPort range must match externalPort range length";
      protoList =
        if forward.proto == "both" then [ "tcp" "udp" ] else [ forward.proto ];
    in concatMap (proto:
      zipListsWith (ext: dest: {
        proto = proto;
        sourcePort = ext;
        destination = "${forward.destination}:${toString dest}";
      }) externalPorts destinationPorts
    ) protoList;

  natForwardEntries =
    concatMap mkPortPairs cfg.portForwards;

  portForwardModule = types.submodule ({ name, ... }: {
    options = {
      proto = mkOption {
        type = types.enum [ "tcp" "udp" "both" ];
        default = "tcp";
        description = "Protocol to forward.";
      };
      externalPort = mkOption {
        type = portSpecType;
        description = "External (WAN) port or port range to forward.";
      };
      destination = mkOption {
        type = types.str;
        description = "Internal destination (IPv4 address or hostname).";
      };
      destinationPort = mkOption {
        type = types.nullOr portSpecType;
        default = null;
        description = "Internal port or range; defaults to externalPort when null.";
      };
    };
  });

in {
  options.router = {
    enable = mkEnableOption "the integrated router configuration";

    wan = {
      type = mkOption {
        type = types.enum [ "dhcp" "static" "pppoe" "pptp" ];
        default = "dhcp";
        description = "WAN connection type.";
      };

      interface = mkOption {
        type = types.str;
        default = "en0";
        description = "Physical interface connected to the WAN uplink.";
      };

      static = {
        ipv4 = {
          address = mkOption {
            type = types.str;
            default = "203.0.113.2";
            description = "Static IPv4 address assigned to the WAN interface.";
          };
          prefixLength = mkOption {
            type = types.int;
            default = 24;
            description = "Prefix length for the static IPv4 network.";
          };
          gateway = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default IPv4 gateway for static mode.";
          };
        };
        ipv6 = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable static IPv6 configuration on the WAN interface.";
          };
          address = mkOption {
            type = types.str;
            default = "2001:db8::2";
            description = "Static IPv6 address in static mode.";
          };
          prefixLength = mkOption {
            type = types.int;
            default = 64;
            description = "Prefix length for the static IPv6 network.";
          };
          gateway = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default IPv6 gateway for static mode.";
          };
        };
        dnsServers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "DNS servers to use when static addressing is selected.";
        };
      };

      pppoe = {
        logicalInterface = mkOption {
          type = types.str;
          default = "ppp0";
          description = "Name of the PPPoE interface created by pppd.";
        };
        user = mkOption {
          type = types.str;
          default = "";
          description = "PPPoE username supplied by the ISP.";
        };
        passwordFile = mkOption {
          type = types.str;
          default = "/etc/nixos/secrets/pppoe-password";
          description = "Absolute path to the PPPoE password file.";
        };
        service = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional PPPoE service name.";
        };
        ipv6 = mkOption {
          type = types.bool;
          default = true;
          description = "Enable IPv6 negotiation on the PPPoE session.";
        };
        mtu = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "Override MTU for the PPPoE session.";
        };
      };

      pptp = {
        logicalInterface = mkOption {
          type = types.str;
          default = "pptp0";
          description = "Name of the PPTP interface exposed by systemd-networkd.";
        };
        server = mkOption {
          type = types.str;
          default = "";
          description = "Remote PPTP server address (hostname or IP).";
        };
        user = mkOption {
          type = types.str;
          default = "";
          description = "PPTP username credential.";
        };
        passwordFile = mkOption {
          type = types.str;
          default = "/etc/nixos/secrets/pptp-password";
          description = "File containing the PPTP password.";
        };
        refuseEAP = mkOption {
          type = types.bool;
          default = false;
          description = "Set RefuseEAP=yes for the PPTP connection.";
        };
        requireMPPE = mkOption {
          type = types.bool;
          default = true;
          description = "Require MPPE encryption on the PPTP tunnel.";
        };
        mppeStateful = mkOption {
          type = types.bool;
          default = false;
          description = "Enable stateful MPPE (MPPEStateful=yes).";
        };
        mtu = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "Override MTU on the PPTP tunnel.";
        };
        extraConfig = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "Additional settings merged into the PPTP netdev configuration.";
        };
      };
    };

    lan = {
      bridge = {
        name = mkOption {
          type = types.str;
          default = "br0";
          description = "Bridge interface representing the LAN.";
        };
        interfaces = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Physical interfaces that form the LAN bridge.";
          example = [ "enp4s0" "enp5s0" "enp6s0" "enp7s0" ];
        };
      };

      ipv4 = {
        address = mkOption {
          type = types.str;
          default = "192.168.1.1";
          description = "LAN IPv4 address of the router.";
        };
        prefixLength = mkOption {
          type = types.int;
          default = 24;
          description = "Prefix length for the LAN IPv4 network.";
        };
      };

      ipv6 = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to assign an IPv6 address to the LAN bridge.";
        };
        address = mkOption {
          type = types.str;
          default = "fd00:dead:beef::1";
          description = "IPv6 address assigned to the LAN bridge.";
        };
        prefixLength = mkOption {
          type = types.int;
          default = 64;
          description = "Prefix length for the LAN IPv6 network.";
        };
      };
    };

    firewall = {
      allowPing = mkOption {
        type = types.bool;
        default = true;
        description = "Allow ICMP echo requests on the firewall.";
      };
      allowedTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ 22 80 443 ];
        description = "TCP ports open on the LAN interface.";
      };
      allowedUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ 53 67 68 ];
        description = "UDP ports open on the LAN interface.";
      };
    };

    nat = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NAT between LAN and WAN.";
      };
      externalInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Interface used for outbound NAT. If left null, it is derived
          from the WAN type (ppp0/pptp0 for PPP variants, otherwise the WAN physical interface).
        '';
      };
      internalInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Interfaces treated as internal networks for NAT.";
      };
      enableIPv6 = mkOption {
        type = types.bool;
        default = true;
        description = "Enable IPv6 masquerading (if supported).";
      };
    };

    dnsmasq = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable dnsmasq for DHCP and DNS.";
      };
      resolveLocalQueries = mkOption {
        type = types.bool;
        default = true;
        description = "Let dnsmasq resolve local hostnames.";
      };
      rangeStart = mkOption {
        type = types.str;
        default = "192.168.1.100";
        description = "Starting address for the DHCP range.";
      };
      rangeEnd = mkOption {
        type = types.str;
        default = "192.168.1.200";
        description = "Ending address for the DHCP range.";
      };
      leaseTime = mkOption {
        type = types.str;
        default = "24h";
        description = "DHCP lease duration.";
      };
      domainNeeded = mkOption {
        type = types.bool;
        default = true;
        description = "Never forward plain names without dots.";
      };
      bogusPriv = mkOption {
        type = types.bool;
        default = true;
        description = "Filter reverse lookups for RFC1918 ranges.";
      };
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Local domain served by dnsmasq.";
      };
      expandHosts = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically append the local domain to simple hostnames.";
      };
      authoritative = mkOption {
        type = types.bool;
        default = true;
        description = "Make dnsmasq authoritative for the configured subnet.";
      };
      dnsServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "DNS servers advertised to DHCP clients (defaults to the router itself).";
      };
      dhcpOptionsExtra = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional raw dhcp-option lines.";
      };
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Specific IP addresses dnsmasq should bind to.";
      };
      extraInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional interfaces for dnsmasq to listen on.";
      };
      tftpRoot = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Enable dnsmasq's TFTP server with this root directory.";
      };
      pxe = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable PXE boot advertisement.";
        };
        filename = mkOption {
          type = types.str;
          default = "pxelinux.0";
          description = "PXE boot filename.";
        };
        serverHostname = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Hostname of the PXE server.";
        };
        serverAddress = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "IP address of the PXE server.";
        };
      };
      staticLeases = mkOption {
        type = types.listOf (types.submodule ({ ... }: {
          options = {
            mac = mkOption {
              type = types.str;
              description = "Client MAC address.";
            };
            ip = mkOption {
              type = types.str;
              description = "Static IP address to hand out.";
            };
            hostname = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional hostname tied to the lease.";
            };
          };
        }));
        default = [ ];
        description = "Static DHCP reservations.";
      };
      extraSettings = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional dnsmasq configuration options.";
      };
    };

    portForwards = mkOption {
      type = types.listOf portForwardModule;
      default = [ ];
      description = ''
        Port forwarding rules to expose internal services.
        Supports single ports or ranges, for TCP, UDP, or both.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking.networkmanager.enable = false;
      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;

      networking.interfaces.${wanInterface} = mkMerge [
        (mkIf (wanType == "dhcp") { useDHCP = true; })
        (mkIf (wanType == "static") {
          useDHCP = false;
          ipv4.addresses = [{
            address = staticCfg.ipv4.address;
            prefixLength = staticCfg.ipv4.prefixLength;
          }];
        })
        (mkIf (wanType == "static" && staticCfg.ipv6.enable) {
          ipv6.addresses = [{
            address = staticCfg.ipv6.address;
            prefixLength = staticCfg.ipv6.prefixLength;
          }];
        })
        (mkIf (wanType == "pppoe") { useDHCP = false; })
        (mkIf (wanType == "pptp") { useDHCP = true; })
      ];

      systemd.network = {
        netdevs.${bridgeName} = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName;
          };
        };

        networks.lan-members = {
          matchConfig.Name = concatStringsSep " " lanCfg.bridge.interfaces;
          networkConfig.Bridge = bridgeName;
        };
      };

      networking.interfaces.${bridgeName} = {
        ipv4.addresses = [{
          address = lanCfg.ipv4.address;
          prefixLength = lanCfg.ipv4.prefixLength;
        }];
      };

      networking.firewall = {
        enable = true;
        allowPing = firewallCfg.allowPing;
        trustedInterfaces = [ bridgeName ];  # Trust LAN interface completely
      };

      networking.nat = {
        enable = natCfg.enable;
        externalInterface = natExternalInterface;
        internalInterfaces =
          if natCfg.internalInterfaces == [ ] then [ bridgeName ] else natCfg.internalInterfaces;
        enableIPv6 = natCfg.enableIPv6;
        forwardPorts = natForwardEntries;
      };

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      services.dnsmasq = mkIf dnsmasqCfg.enable {
        enable = true;
        resolveLocalQueries = dnsmasqCfg.resolveLocalQueries;
        settings = recursiveUpdate dnsmasqBaseSettings (
          dnsmasqCfg.extraSettings
          // optionalAttrs (dnsmasqInterfaces != [ ]) { interface = dnsmasqInterfaces; }
        );
      };

      # Ensure dnsmasq starts after network is configured
      systemd.services.dnsmasq = mkIf dnsmasqCfg.enable {
        after = [
          "network-online.target"
          "systemd-networkd.service"
          "sys-subsystem-net-devices-${bridgeName}.device"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "5s";
          Restart = "on-failure";
        };
      };
    }

    (mkIf (wanType == "static" && staticCfg.dnsServers != [ ]) {
      networking.nameservers = staticCfg.dnsServers;
    })

    (mkIf (wanType == "static" && staticCfg.ipv4.gateway != null) {
      networking.defaultGateway = {
        interface = wanInterface;
        address = staticCfg.ipv4.gateway;
      };
    })

    (mkIf (wanType == "static" && staticCfg.ipv6.enable && staticCfg.ipv6.gateway != null) {
      networking.defaultGateway6 = {
        interface = wanInterface;
        address = staticCfg.ipv6.gateway;
      };
    })

    (mkIf (wanType == "pptp") {
      systemd.network.netdevs.${pptpCfg.logicalInterface} = {
        netdevConfig = {
          Kind = "pptp";
          Name = pptpCfg.logicalInterface;
        };
        pptpConfig =
          {
            Remote = pptpCfg.server;
            User = pptpCfg.user;
            PasswordFile = pptpCfg.passwordFile;
            PhysicalDevice = wanInterface;
            RefuseEAP = pptpCfg.refuseEAP;
            RequireMPPE = pptpCfg.requireMPPE;
            MPPEStateful = pptpCfg.mppeStateful;
          }
          // optionalAttrs (pptpCfg.mtu != null) { MTU = pptpCfg.mtu; }
          // pptpCfg.extraConfig;
      };

      systemd.network.networks.${pptpCfg.logicalInterface} = {
        matchConfig.Name = pptpCfg.logicalInterface;
        networkConfig = {
          DHCP = "ipv4";
          KeepConfiguration = "dhcp-on-stop";
        };
      };
    })
  ]);
}

