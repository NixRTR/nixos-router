{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  cakeConfig = routerConfig.wan.cake or { enable = false; };
  
  # Determine WAN interface (same logic as router.nix for NAT)
  wanType = routerConfig.wan.type;
  wanInterface = routerConfig.wan.interface;
  pppoeInterface = (routerConfig.wan.pppoe or {}).logicalInterface or "ppp0";
  
  # WAN interface for CAKE (PPPoE uses logical interface, others use physical)
  cakeInterface = if wanType == "pppoe" then pppoeInterface else wanInterface;
  
  # Map aggressiveness levels to CAKE parameters
  cakeParams = {
    auto = {
      bandwidth = "unlimited";
      extraParams = [ "autorate-ingress" "autorate-egress" ];
      aqm = null;  # Auto-tuned by CAKE
    };
    conservative = {
      bandwidth = "unlimited";  # Will use autorate to detect
      extraParams = [ "autorate-ingress" "autorate-egress" ];
      aqm = null;  # Uses CAKE defaults (target ~5ms, interval ~100ms)
    };
    moderate = {
      bandwidth = "unlimited";
      extraParams = [ "autorate-ingress" "autorate-egress" ];
      aqm = null;  # Uses CAKE defaults
    };
    aggressive = {
      bandwidth = "unlimited";
      extraParams = [ "autorate-ingress" "autorate-egress" ];
      aqm = "target 2ms interval 50ms";  # More aggressive AQM
    };
  };
  
  aggressiveness = cakeConfig.aggressiveness or "auto";
  params = cakeParams.${aggressiveness} or cakeParams.auto;
  
  # Build CAKE command parameters as space-separated string
  # For root qdisc (egress/upload shaping)
  cakeRootParams = 
    "diffserv4 nat wash " +
    (if params.bandwidth != null then "bandwidth ${params.bandwidth} " else "") +
    (concatStringsSep " " params.extraParams) +
    (if params.aqm != null then " ${params.aqm}" else "");
  
  # For ingress qdisc (download shaping) - same params but without autorate-ingress
  # autorate-ingress is only for the root qdisc to measure ingress bandwidth
  filteredExtraParams = filter (p: p != "autorate-ingress") params.extraParams;
  cakeIngressParams = 
    "diffserv4 nat " +
    (if params.bandwidth != null then "bandwidth ${params.bandwidth} " else "") +
    (concatStringsSep " " filteredExtraParams) +
    (if params.aqm != null then " ${params.aqm}" else "");

in

{
  config = mkIf cakeConfig.enable {
    # Ensure iproute2 is available (contains tc command)
    environment.systemPackages = with pkgs; [ iproute2 ];
    
    # Systemd service to configure CAKE on WAN interface
    systemd.services."cake-setup" = {
      description = "Configure CAKE queue discipline on WAN interface";
      wantedBy = [ "network-online.target" ];
      after = [ 
        "network.target" 
        "network-online.target"
      ] ++ (optional (wanType == "pppoe") "pppd-${wanInterface}.service");
      
      # Wait for PPPoE interface if needed
      requires = optional (wanType == "pppoe") "pppd-${wanInterface}.service";
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
      };
      
      script = ''
        # Wait for WAN interface to be available
        max_wait=60
        waited=0
        while [ ! -d /sys/class/net/${cakeInterface} ] && [ $waited -lt $max_wait ]; do
          sleep 1
          waited=$((waited + 1))
        done
        
        if [ ! -d /sys/class/net/${cakeInterface} ]; then
          echo "ERROR: Interface ${cakeInterface} not available after $max_wait seconds"
          exit 1
        fi
        
        # Wait a bit more for interface to be fully up (especially PPPoE)
        sleep 2
        
        # Check if interface is up
        if ! ip link show ${cakeInterface} | grep -q "state UP"; then
          echo "WARNING: Interface ${cakeInterface} is not UP, but proceeding anyway"
        fi
        
        # Remove existing qdisc if any (ignore errors)
        ${pkgs.iproute2}/bin/tc qdisc del dev ${cakeInterface} root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev ${cakeInterface} ingress 2>/dev/null || true
        
        # Apply CAKE for egress (upload) traffic on root qdisc
        # autorate-ingress measures ingress bandwidth to help tune egress shaping
        # autorate-egress automatically adjusts egress bandwidth based on actual link speed
        ${pkgs.iproute2}/bin/tc qdisc add dev ${cakeInterface} root cake ${cakeRootParams}
        
        # Apply CAKE for ingress (download) traffic if autorate-ingress is enabled
        # This provides bidirectional shaping
        if echo "${cakeRootParams}" | grep -q "autorate-ingress"; then
          ${pkgs.iproute2}/bin/tc qdisc add dev ${cakeInterface} ingress cake ${cakeIngressParams}
        fi
        
        echo "CAKE configured on ${cakeInterface}"
        echo "  Aggressiveness: ${aggressiveness}"
        echo "  Egress parameters: ${cakeRootParams}"
        
        echo "CAKE configured on ${cakeInterface} with aggressiveness: ${aggressiveness}"
      '';
      
      preStop = ''
        # Cleanup CAKE qdiscs on service stop
        ${pkgs.iproute2}/bin/tc qdisc del dev ${cakeInterface} root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev ${cakeInterface} ingress 2>/dev/null || true
      '';
    };
  };
}

