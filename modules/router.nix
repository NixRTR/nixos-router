{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router;

  # Type definitions and helper functions
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

      isolationExceptions = mkOption {
        type = types.listOf (types.submodule {
          options = {
            source = mkOption {
              type = types.str;
              description = "Source IP address to allow through isolation.";
              example = "192.168.3.50";
            };
            sourceBridge = mkOption {
              type = types.str;
              description = "Source bridge name.";
              example = "br1";
            };
            destBridge = mkOption {
              type = types.str;
              description = "Destination bridge name.";
              example = "br0";
            };
            description = mkOption {
              type = types.str;
              default = "";
              description = "Optional description of this exception.";
            };
          };
        });
        default = [];
        description = ''
          List of exceptions to bridge isolation rules. Allows specific source IPs
          to communicate with specific destination bridges despite isolation being enabled.
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
      # All config-dependent variables defined here to avoid accessing them at module-level
      wanCfg = cfg.wan;
      wanType = wanCfg.type;
      wanInterface = wanCfg.interface;
      staticCfg = wanCfg.static;
      pppoeCfg = wanCfg.pppoe;
      lanCfg = cfg.lan;
      firewallCfg = cfg.firewall;
      natCfg = cfg.nat;

      bridges = lanCfg.bridges;
      bridgeNames = map (b: b.name) bridges;
      lanIsolation = lanCfg.isolation;
      isolationExceptions = lanCfg.isolationExceptions;

      natExternalInterface =
        if natCfg.externalInterface != null then natCfg.externalInterface
        else if wanType == "pppoe" then pppoeCfg.logicalInterface
        else wanInterface;

      natForwardEntries = concatMap mkPortPairs cfg.portForwards;
    in
    mkMerge [
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
        
        # Enable hardware offloading on WAN interface
        links."10-${wanInterface}" = {
          matchConfig.Name = wanInterface;
          linkConfig = {
            # Enable all hardware offload features
            ReceiveChecksumOffload = true;
            TransmitChecksumOffload = true;
            TCPSegmentationOffload = true;
            GenericSegmentationOffload = true;
            GenericReceiveOffload = true;
            LargeReceiveOffload = true;
          };
        };
      };

      # Assign IP addresses to each bridge (done below in separate mkMerge blocks)

      networking.firewall = {
        enable = true;
        allowPing = firewallCfg.allowPing;
        trustedInterfaces = bridgeNames;  # Trust all LAN bridges for WAN access
        
        # Block traffic between bridges if isolation is enabled
        extraCommands = mkIf (lanIsolation && (length bridges) > 1) (
          let
            # Generate all bridge pairs for blocking
            bridgePairs = flatten (map (i: 
              map (j: { from = elemAt bridgeNames i; to = elemAt bridgeNames j; })
                (range (i + 1) ((length bridgeNames) - 1))
            ) (range 0 ((length bridgeNames) - 2)));
            
            # Generate exception rules (must come BEFORE drop rules)
            exceptionRules = concatMapStrings (ex: ''
              # Exception: ${ex.description}
              # Allow ${ex.source} (${ex.sourceBridge}) -> ${ex.destBridge}
              iptables -I FORWARD -s ${ex.source} -i ${ex.sourceBridge} -o ${ex.destBridge} -j ACCEPT
              # Allow return traffic from ${ex.destBridge} -> ${ex.source}
              iptables -I FORWARD -d ${ex.source} -i ${ex.destBridge} -o ${ex.sourceBridge} -j ACCEPT
            '') isolationExceptions;
          in
            # Apply exceptions first, then blocking rules
            exceptionRules + (concatMapStrings (pair: ''
              # Block ${pair.from} <-> ${pair.to}
              iptables -A FORWARD -i ${pair.from} -o ${pair.to} -j DROP
              iptables -A FORWARD -i ${pair.to} -o ${pair.from} -j DROP
            '') bridgePairs)
        );
        
        extraStopCommands = mkIf (lanIsolation && (length bridges) > 1) (
          let
            bridgePairs = flatten (map (i: 
              map (j: { from = elemAt bridgeNames i; to = elemAt bridgeNames j; })
                (range (i + 1) ((length bridgeNames) - 1))
            ) (range 0 ((length bridgeNames) - 2)));
            
            # Clean up exception rules
            cleanupExceptions = concatMapStrings (ex: ''
              iptables -D FORWARD -s ${ex.source} -i ${ex.sourceBridge} -o ${ex.destBridge} -j ACCEPT || true
              iptables -D FORWARD -d ${ex.source} -i ${ex.destBridge} -o ${ex.sourceBridge} -j ACCEPT || true
            '') isolationExceptions;
          in
            cleanupExceptions + (concatMapStrings (pair: ''
              iptables -D FORWARD -i ${pair.from} -o ${pair.to} -j DROP || true
              iptables -D FORWARD -i ${pair.to} -o ${pair.from} -j DROP || true
            '') bridgePairs)
        );
      };

      networking.nat = {
        enable = natCfg.enable;
        externalInterface = natExternalInterface;
        internalInterfaces =
          if natCfg.internalInterfaces == [ ] then bridgeNames else natCfg.internalInterfaces;
        enableIPv6 = natCfg.enableIPv6;
        forwardPorts = natForwardEntries;
        
        # MSS clamping to fix MTU issues (prevents slow loading/fragmentation)
        extraCommands = ''
          iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        '';
        
        extraStopCommands = ''
          iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
        '';
      };

      # Initialize nftables sets and rules for per-device blocking (IP-based)
      systemd.services."nft-device-block-init" = {
        description = "Initialize nftables sets for per-device blocking";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-pre.target" ];
        before = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.nftables}/bin/nft -f - <<'EOF'
          table inet router_block {
            set blocked_v4 {
              type ipv4_addr
              flags interval
            }
            set blocked_v6 {
              type ipv6_addr
              flags interval
            }
            chain forward {
              type filter hook forward priority 0; policy accept;
              ip saddr @blocked_v4 drop
              ip daddr @blocked_v4 drop
              ip6 saddr @blocked_v6 drop
              ip6 daddr @blocked_v6 drop
            }
            chain input {
              type filter hook input priority 0; policy accept;
              ip saddr @blocked_v4 drop
              ip6 saddr @blocked_v6 drop
            }
          }
          EOF
        '';
      };

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        
        # TCP optimization for router performance
        "net.ipv4.tcp_window_scaling" = 1;
        "net.ipv4.tcp_timestamps" = 1;
        "net.ipv4.tcp_sack" = 1;
        "net.ipv4.tcp_no_metrics_save" = 1;
        
        # Use BBR congestion control (modern, better performance)
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.core.default_qdisc" = "fq";  # Fair Queue required for BBR
        
        # Increase TCP buffer sizes for better throughput
        "net.core.rmem_max" = 134217728;  # 128 MB
        "net.core.wmem_max" = 134217728;  # 128 MB
        "net.ipv4.tcp_rmem" = "4096 87380 67108864";  # min default max
        "net.ipv4.tcp_wmem" = "4096 65536 67108864";
        
        # Enable TCP Fast Open
        "net.ipv4.tcp_fastopen" = 3;
        
        # Reduce TIME_WAIT connections
        "net.ipv4.tcp_fin_timeout" = 30;
        "net.ipv4.tcp_tw_reuse" = 1;
        
        # Connection tracking optimization
        "net.netfilter.nf_conntrack_max" = 262144;  # Handle more concurrent connections
        "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;  # 24 hours
        "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 30;
        
        # SYN flood protection
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.tcp_max_syn_backlog" = 8192;
        "net.ipv4.tcp_synack_retries" = 2;
        
        # Increase network device backlog for high-speed networks
        "net.core.netdev_max_backlog" = 5000;
        
        # Optimize for routing/forwarding
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.all.rp_filter" = 1;  # Reverse path filtering (security)
        
        # Reduce swappiness (router shouldn't swap)
        "vm.swappiness" = 10;
        
        # Optimize file handle limits
        "fs.file-max" = 2097152;
      };

      # CPU governor for performance
      powerManagement.cpuFreqGovernor = "ondemand";
      
      # Enable kernel modules for BBR
      boot.kernelModules = [ "tcp_bbr" ];
      
      # DNS and DHCP services configured elsewhere (e.g., blocky + dhcpd4)
    }

    # Bridge interfaces - br0 (HOMELAB)
    {
      networking.interfaces.br0 = mkIf (length bridges > 0) {
        ipv4.addresses = [{
          address = (elemAt bridges 0).ipv4.address;
          prefixLength = (elemAt bridges 0).ipv4.prefixLength;
        }];
        ipv6.addresses = optionals (elemAt bridges 0).ipv6.enable [{
          address = (elemAt bridges 0).ipv6.address;
          prefixLength = (elemAt bridges 0).ipv6.prefixLength;
        }];
      };
    }

    # Bridge interfaces - br1 (LAN)
    {
      networking.interfaces.br1 = mkIf (length bridges > 1) {
        ipv4.addresses = [{
          address = (elemAt bridges 1).ipv4.address;
          prefixLength = (elemAt bridges 1).ipv4.prefixLength;
        }];
        ipv6.addresses = optionals (elemAt bridges 1).ipv6.enable [{
          address = (elemAt bridges 1).ipv6.address;
          prefixLength = (elemAt bridges 1).ipv6.prefixLength;
        }];
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
            # Credentials are injected from sops template
            file ${config.sops.templates."pppoe-peer.conf".path}
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
    })
  ]);
}

