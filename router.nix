{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router;
  wanCfg = cfg.wan;
  wanType = wanCfg.type;
  wanInterface = wanCfg.interface;
  staticCfg = wanCfg.static;
  pppoeCfg = wanCfg.pppoe;
  lanCfg = cfg.lan;
  firewallCfg = cfg.firewall;
  natCfg = cfg.nat;

  natExternalInterface =
    if natCfg.externalInterface != null then natCfg.externalInterface
    else if wanType == "pppoe" then pppoeCfg.logicalInterface
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

  bridgeModule = types.submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Bridge interface name.";
        example = "br0";
      };
      interfaces = mkOption {
        type = types.listOf types.str;
        description = "Physical interfaces that form this bridge.";
        example = [ "enp4s0" "enp5s0" ];
      };
      ipv4 = {
        address = mkOption {
          type = types.str;
          description = "IPv4 address of the router on this bridge.";
          example = "192.168.1.1";
        };
        prefixLength = mkOption {
          type = types.int;
          default = 24;
          description = "Prefix length for the IPv4 network.";
        };
      };
      ipv6 = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to assign an IPv6 address to this bridge.";
        };
        address = mkOption {
          type = types.str;
          default = "fd00:dead:beef::1";
          description = "IPv6 address assigned to the bridge.";
        };
        prefixLength = mkOption {
          type = types.int;
          default = 64;
          description = "Prefix length for the IPv6 network.";
        };
      };
    };
  });

in {
  options.router = {
    enable = mkEnableOption "the integrated router configuration";

    wan = {
      type = mkOption {
        type = types.enum [ "dhcp" "static" "pppoe" ];
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
    };

    lan = {
      bridges = mkOption {
        type = types.listOf bridgeModule;
        default = [ ];
        description = ''
          List of LAN bridges to create. Each bridge can have multiple physical interfaces
          and its own IP configuration. Supports multiple isolated LAN segments.
        '';
        example = [
          {
            name = "br0";
            interfaces = [ "enp4s0" "enp5s0" ];
            ipv4 = { address = "192.168.2.1"; prefixLength = 24; };
            ipv6.enable = false;
          }
          {
            name = "br1";
            interfaces = [ "enp6s0" "enp7s0" ];
            ipv4 = { address = "192.168.3.1"; prefixLength = 24; };
            ipv6.enable = false;
          }
        ];
      };

      isolation = mkOption {
        type = types.bool;
        default = true;
        description = ''
          When true and multiple bridges are defined, blocks direct traffic between bridges.
          Bridges can still reach WAN and router services, but not each other.
        '';
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

    portForwards = mkOption {
      type = types.listOf portForwardModule;
      default = [ ];
      description = ''
        Port forwarding rules to expose internal services.
        Supports single ports or ranges, for TCP, UDP, or both.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      # Get bridges from config
      bridges = lanCfg.bridges;
      bridgeNames = map (b: b.name) bridges;
    in
    mkMerge ([
    {
      networking.networkmanager.enable = false;
      networking.useNetworkd = true;
      systemd.network.enable = true;
      systemd.network.wait-online.enable = false;
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
      ];

      # Create systemd network devices for each bridge
      systemd.network = {
        netdevs = listToAttrs (map (bridge: {
          name = bridge.name;
          value = {
            netdevConfig = {
              Kind = "bridge";
              Name = bridge.name;
            };
          };
        }) bridges);

        networks = listToAttrs (flatten (map (bridge: {
          name = "${bridge.name}-members";
          value = {
            matchConfig.Name = concatStringsSep " " bridge.interfaces;
            networkConfig.Bridge = bridge.name;
          };
        }) bridges));
      };

      # Assign IP addresses to each bridge (done below in separate mkMerge blocks)

      networking.firewall = {
        enable = true;
        allowPing = firewallCfg.allowPing;
        trustedInterfaces = bridgeNames;  # Trust all LAN bridges for WAN access
        
        # Block traffic between bridges if isolation is enabled
        extraCommands = mkIf (lanCfg.isolation && (length bridges) > 1) (
          let
            # Generate all bridge pairs for blocking
            bridgePairs = flatten (map (i: 
              map (j: { from = elemAt bridgeNames i; to = elemAt bridgeNames j; })
                (range (i + 1) ((length bridgeNames) - 1))
            ) (range 0 ((length bridgeNames) - 2)));
          in
            concatMapStrings (pair: ''
              # Block ${pair.from} <-> ${pair.to}
              iptables -I FORWARD -i ${pair.from} -o ${pair.to} -j DROP
              iptables -I FORWARD -i ${pair.to} -o ${pair.from} -j DROP
            '') bridgePairs
        );
        
        extraStopCommands = mkIf (lanCfg.isolation && (length bridges) > 1) (
          let
            bridgePairs = flatten (map (i: 
              map (j: { from = elemAt bridgeNames i; to = elemAt bridgeNames j; })
                (range (i + 1) ((length bridgeNames) - 1))
            ) (range 0 ((length bridgeNames) - 2)));
          in
            concatMapStrings (pair: ''
              iptables -D FORWARD -i ${pair.from} -o ${pair.to} -j DROP || true
              iptables -D FORWARD -i ${pair.to} -o ${pair.from} -j DROP || true
            '') bridgePairs
        );
      };

      networking.nat = {
        enable = natCfg.enable;
        externalInterface = natExternalInterface;
        internalInterfaces =
          if natCfg.internalInterfaces == [ ] then bridgeNames else natCfg.internalInterfaces;
        enableIPv6 = natCfg.enableIPv6;
        forwardPorts = natForwardEntries;
      };

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # DNS and DHCP services configured elsewhere (e.g., blocky + dhcpd4)
    }

    # Configure each bridge interface with its IP addresses
  ] ++ (map (bridge: {
    networking.interfaces.${bridge.name} = {
      ipv4.addresses = [{
        address = bridge.ipv4.address;
        prefixLength = bridge.ipv4.prefixLength;
      }];
      ipv6.addresses = optionals bridge.ipv6.enable [{
        address = bridge.ipv6.address;
        prefixLength = bridge.ipv6.prefixLength;
      }];
    };
  }) bridges) ++ [

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

    (mkIf (wanType == "pppoe") {
      # Install rp-pppoe package for the PPPoE plugin
      environment.systemPackages = [ pkgs.rpPPPoE ];
      
      # Setup PPPoE session using pppd
      # Based on: https://francis.begyn.be/blog/nixos-home-router
      services.pppd = {
        enable = true;
        peers.${wanInterface} = {
          enable = true;
          autostart = true;
          config = ''
            plugin ${pkgs.rpPPPoE}/lib/rp-pppoe.so
            nic-${wanInterface}
            user PPPOE_USERNAME_PLACEHOLDER
            password PPPOE_PASSWORD_PLACEHOLDER
            noauth
            persist
            maxfail 0
            holdoff 5
            noipdefault
            defaultroute
            replacedefaultroute
            lcp-echo-interval 15
            lcp-echo-failure 3
            usepeerdns
            ${optionalString (pppoeCfg.service != null) "rp_pppoe_service '${pppoeCfg.service}'"}
            ${optionalString pppoeCfg.ipv6 "+ipv6"}
            ${optionalString (pppoeCfg.mtu != null) "mtu ${toString pppoeCfg.mtu}"}
            ${optionalString (pppoeCfg.mtu != null) "mru ${toString pppoeCfg.mtu}"}
          '';
        };
      };

      # Inject actual credentials at activation time
      system.activationScripts.setup-pppoe-credentials = {
        text = ''
          if [ -f ${pppoeCfg.user} ] && [ -f ${pppoeCfg.passwordFile} ]; then
            USERNAME=$(cat ${pppoeCfg.user})
            PASSWORD=$(cat ${pppoeCfg.passwordFile})
            
            # Update peer config with actual credentials
            PEER_FILE="/etc/ppp/peers/${wanInterface}"
            if [ -f "$PEER_FILE" ]; then
              ${pkgs.gnused}/bin/sed -i "s/PPPOE_USERNAME_PLACEHOLDER/$USERNAME/" "$PEER_FILE"
              ${pkgs.gnused}/bin/sed -i "s/PPPOE_PASSWORD_PLACEHOLDER/$PASSWORD/" "$PEER_FILE"
              chmod 600 "$PEER_FILE"
            fi
          fi
        '';
        deps = [];
      };
    })
  ]));
}

