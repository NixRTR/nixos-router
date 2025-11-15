{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.linode-dyndns;
  routerConfig = import ../router-config.nix;
  dyndnsConfig = routerConfig.dyndns or { enable = false; };
  
  # Update script will be inlined in the service

in

{
  options.services.linode-dyndns = {
    enable = mkEnableOption "Linode Dynamic DNS updater";

    tokenFile = mkOption {
      type = types.str;
      default = "/run/secrets/linode-api-token";
      description = "Path to file containing Linode API token";
    };

    domainId = mkOption {
      type = types.int;
      description = "Linode domain ID";
    };

    recordId = mkOption {
      type = types.int;
      description = "Linode DNS record ID";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain name to update";
    };

    subdomain = mkOption {
      type = types.str;
      default = "";
      description = "Subdomain to update (empty string for root domain)";
    };

    fullDomain = mkOption {
      type = types.str;
      internal = true;
      readOnly = true;
      default = if cfg.subdomain == "" then cfg.domain else "${cfg.subdomain}.${cfg.domain}";
      description = "Full domain name (computed)";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "5m";
      description = "How often to check for IP changes (systemd timer format)";
    };

    wanInterface = mkOption {
      type = types.str;
      default = routerConfig.wan.interface;
      description = "WAN interface to monitor for IP changes";
    };
  };

  config = mkIf (dyndnsConfig.enable or false) {
    services.linode-dyndns = {
      enable = true;
      domainId = dyndnsConfig.domainId;
      recordId = dyndnsConfig.recordId;
      domain = dyndnsConfig.domain;
      subdomain = dyndnsConfig.subdomain or "";
      checkInterval = dyndnsConfig.checkInterval or "5m";
    };

    # Add Linode API token to sops secrets
    sops.secrets."linode-api-token" = mkIf cfg.enable {
      path = "/run/secrets/linode-api-token";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # Service to update DNS
    systemd.services.linode-dyndns = mkIf cfg.enable {
      description = "Linode Dynamic DNS updater for ${cfg.fullDomain}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      script = ''
        set -euo pipefail
        
        STATE_FILE="/var/lib/linode-dyndns/last-ip"
        mkdir -p /var/lib/linode-dyndns
        
        # Get Linode API token from secrets
        if [ ! -f "${cfg.tokenFile}" ]; then
          echo "[ERROR] Linode API token file not found: ${cfg.tokenFile}"
          exit 1
        fi
        
        LINODE_TOKEN=$(cat "${cfg.tokenFile}")
        
        # Get current public IP with retry logic
        echo "[INFO] Attempting to get public IP..."
        PUBLIC_IP=""
        for i in {1..5}; do
          PUBLIC_IP=$(${pkgs.curl}/bin/curl -s --connect-timeout 10 --max-time 30 https://api.ipify.org || true)
          if [ -n "$PUBLIC_IP" ]; then
            break
          fi
          echo "[WARN] Failed to get public IP (attempt $i/5), retrying in 10 seconds..."
          sleep 10
        done
        
        if [ -z "$PUBLIC_IP" ]; then
          echo "[ERROR] Failed to get public IP address after 5 attempts"
          exit 1
        fi
        
        echo "[INFO] Current public IP: $PUBLIC_IP"
        
        # Check if IP has changed
        if [ -f "$STATE_FILE" ]; then
          LAST_IP=$(cat "$STATE_FILE")
          if [ "$PUBLIC_IP" == "$LAST_IP" ]; then
            echo "[INFO] IP unchanged: No action taken"
            exit 0
          fi
          echo "[INFO] IP changed from $LAST_IP to $PUBLIC_IP"
        else
          echo "[INFO] First run, no previous IP recorded"
        fi
        
        # Get current DNS record
        CURRENT_RECORD=$(${pkgs.curl}/bin/curl -s -H "Authorization: Bearer $LINODE_TOKEN" \
          "https://api.linode.com/v4/domains/${toString cfg.domainId}/records/${toString cfg.recordId}")
        
        CURRENT_TARGET=$(echo "$CURRENT_RECORD" | ${pkgs.jq}/bin/jq -r ".target")
        
        if [ "$CURRENT_TARGET" == "$PUBLIC_IP" ]; then
          echo "[INFO] DNS record already up to date"
          echo "$PUBLIC_IP" > "$STATE_FILE"
          exit 0
        fi
        
        echo "[INFO] Updating DNS record from $CURRENT_TARGET to $PUBLIC_IP"
        
        # Update the DNS record
        RESPONSE=$(${pkgs.curl}/bin/curl -s -X PUT \
          -H "Authorization: Bearer $LINODE_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"target\": \"$PUBLIC_IP\", \"ttl_sec\": 30}" \
          "https://api.linode.com/v4/domains/${toString cfg.domainId}/records/${toString cfg.recordId}")
        
        # Check if update was successful
        NEW_TARGET=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r ".target")
        
        if [ "$NEW_TARGET" == "$PUBLIC_IP" ]; then
          echo "[SUCCESS] DNS record updated successfully"
          echo "$PUBLIC_IP" > "$STATE_FILE"
          
          # Log to systemd journal
          echo "[INFO] ${cfg.fullDomain} → $PUBLIC_IP"
        else
          ERROR=$(echo "$RESPONSE" | jq -r ".errors[0].reason // \"Unknown error\"")
          echo "[ERROR] Failed to update DNS record: $ERROR"
          exit 1
        fi
      '';
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    # Timer to check periodically
    systemd.timers.linode-dyndns = mkIf cfg.enable {
      description = "Linode Dynamic DNS update timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";  # Run 2 minutes after boot
        OnUnitActiveSec = cfg.checkInterval;  # Run periodically
        Persistent = true;
      };
    };

    # Trigger update when WAN interface gets IP address
    systemd.services.linode-dyndns-on-wan-up = mkIf cfg.enable {
      description = "Trigger Linode DNS update when WAN gets IP";
      # Wait for network to be fully online
      after = [ "network-online.target" ] 
        ++ optional (routerConfig.wan.type == "pppoe") "pppd-${cfg.wanInterface}.service";
      wants = [ "network-online.target" ];
      # For PPPoE, require the PPPoE connection to be up
      requires = optional (routerConfig.wan.type == "pppoe") "pppd-${cfg.wanInterface}.service";
      wantedBy = [ "multi-user.target" ];
      
      # Add delay to ensure connection is stable
      script = ''
        echo "[INFO] Waiting for WAN connection to stabilize..."
        sleep 30
        echo "[INFO] Triggering Linode DynDNS update..."
        systemctl start linode-dyndns.service || true
      '';
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Path-based activation: trigger when WAN interface state changes
    systemd.paths.linode-dyndns-wan-trigger = mkIf cfg.enable {
      description = "Monitor WAN interface for IP changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/sys/class/net/${cfg.wanInterface}/operstate";
        Unit = "linode-dyndns.service";
      };
    };
  };
}

