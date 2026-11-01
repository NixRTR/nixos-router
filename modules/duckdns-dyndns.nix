
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.duckdns;
  routerConfig = import ../router-config.nix;
  duckdnsConfig = routerConfig.duckdns or { enable = false; };

in
{
  options.services.duckdns = {
    enable = mkEnableOption "DuckDNS Dynamic DNS updater";

    tokenFile = mkOption {
      type = types.str;
      default = "/run/secrets/duckdns-token";
      description = "Path to file containing DuckDNS API token";
    };

    domain = mkOption {
      type = types.str;
      description = "DuckDNS subdomain (without .duckdns.org)";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "5m";
      description = "How often to check for IP changes";
    };

    wanInterface = mkOption {
      type = types.str;
      default = routerConfig.wan.interface;
      description = "WAN interface to monitor for IP changes";
    };

    fullDomain = mkOption {
      type = types.str;
      internal = true;
      readOnly = true;
      default = "${cfg.domain}.duckdns.org";
      description = "Full DuckDNS domain";
    };
  };

  config = mkIf (duckdnsConfig.enable or false) {
    services.duckdns = {
      enable = true;
      domain = duckdnsConfig.domain;
      checkInterval = duckdnsConfig.checkInterval or "5m";
    };

    # SOPS secret
    sops.secrets."duckdns-token" = mkIf cfg.enable {
      path = "/run/secrets/duckdns-token";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # DuckDNS updater service
    systemd.services.duckdns = mkIf cfg.enable {
      description = "DuckDNS Dynamic DNS updater for ${cfg.fullDomain}";

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      script = ''
        set -euo pipefail

        STATE_DIR="/var/lib/duckdns"
        STATE_FILE="$STATE_DIR/last-ip"

        mkdir -p "$STATE_DIR"

        # Read DuckDNS token
        if [ ! -f "${cfg.tokenFile}" ]; then
          echo "[ERROR] DuckDNS token file not found: ${cfg.tokenFile}"
          exit 1
        fi

        DUCKDNS_TOKEN=$(cat "${cfg.tokenFile}")

        if [ -z "$DUCKDNS_TOKEN" ]; then
          echo "[ERROR] DuckDNS token is empty"
          exit 1
        fi

        # Get current public IP with retry logic
        echo "[INFO] Attempting to get public IP..."

        PUBLIC_IP=""

        for i in {1..5}; do
          PUBLIC_IP=$(${pkgs.curl}/bin/curl \
            -4 -fsS \
            --connect-timeout 10 \
            --max-time 30 \
            https://api.ipify.org || true)

          if [ -n "$PUBLIC_IP" ]; then
            break
          fi

          echo "[WARN] Failed to get public IP (attempt $i/5), retrying in 10 seconds..."
          sleep 10
        done

        if [ -z "$PUBLIC_IP" ]; then
          echo "[ERROR] Failed to obtain public IP after 5 attempts"
          exit 1
        fi

        echo "[INFO] Current public IP: $PUBLIC_IP"

        # Check if IP has changed
        if [ -f "$STATE_FILE" ]; then
          LAST_IP=$(cat "$STATE_FILE")

          if [ "$PUBLIC_IP" = "$LAST_IP" ]; then
            echo "[INFO] IP unchanged: No action taken"
            exit 0
          fi

          echo "[INFO] IP changed from $LAST_IP to $PUBLIC_IP"
        else
          echo "[INFO] First run, no previous IP recorded"
        fi

        # Update DuckDNS
        echo "[INFO] Updating ${cfg.fullDomain}..."

        RESPONSE=$(${pkgs.curl}/bin/curl \
          -4 -fsS \
          --connect-timeout 10 \
          --max-time 30 \
          "https://www.duckdns.org/update?domains=${cfg.domain}&token=$DUCKDNS_TOKEN&ip=$PUBLIC_IP")

        # DuckDNS returns OK on success and KO on failure
        if [ "$RESPONSE" = "OK" ]; then
          echo "$PUBLIC_IP" > "$STATE_FILE"
          echo "[SUCCESS] ${cfg.fullDomain} updated to $PUBLIC_IP"
        else
          echo "[ERROR] DuckDNS update failed: $RESPONSE"
          exit 1
        fi
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        StateDirectory = "duckdns";
        StateDirectoryMode = "0700";
      };
    };

    # Periodic update timer
    systemd.timers.duckdns = mkIf cfg.enable {
      description = "DuckDNS Dynamic DNS update timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.checkInterval;
        Persistent = true;
      };
    };

    # Trigger update when WAN comes up
    systemd.services.duckdns-on-wan-up = mkIf cfg.enable {
      description = "Trigger DuckDNS update when WAN gets IP";

      after = [ "network-online.target" ]
        ++ optional (routerConfig.wan.type == "pppoe")
          "pppd-${cfg.wanInterface}.service";

      wants = [ "network-online.target" ];

      requires = optional (routerConfig.wan.type == "pppoe")
        "pppd-${cfg.wanInterface}.service";

      script = ''
        echo "[INFO] Triggering DuckDNS update..."
        systemctl start duckdns.service || true
      '';

      serviceConfig = {
        Type = "oneshot";
      };
    };

    # Trigger after boot
    systemd.timers.duckdns-on-wan-up = mkIf cfg.enable {
      description = "Trigger DuckDNS update after WAN is stable";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "1min";
        Unit = "duckdns-on-wan-up.service";
      };
    };

    # Monitor WAN interface state
    systemd.paths.duckdns-wan-trigger = mkIf cfg.enable {
      description = "Monitor WAN interface for changes";
      wantedBy = [ "multi-user.target" ];

      pathConfig = {
        PathModified = "/sys/class/net/${cfg.wanInterface}/operstate";
        Unit = "duckdns.service";
      };
    };
  };
}
