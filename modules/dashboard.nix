{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router.dashboard;
  routerCfg = config.router;
in

{
  options.router.dashboard = {
    enable = mkEnableOption "Router monitoring dashboard";

    speedtest = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable periodic speedtest measurements";
      };

      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = "How often to run speedtest (systemd timer format)";
      };
    };
  };

  config = mkIf cfg.enable {

    # Speedtest service and exporter
    systemd.services.speedtest = mkIf cfg.speedtest.enable {
      description = "Speedtest bandwidth measurement";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "run-speedtest" ''
          set -euo pipefail
          
          # Wait a bit for network to be fully ready
          sleep 10
          
          # Wait for WebUI backend to be ready (it runs on port 8081 by default)
          BACKEND_PORT=${toString config.services.router-webui.backendPort}
          for i in {1..30}; do
            if ${pkgs.curl}/bin/curl -s -f "http://127.0.0.1:$BACKEND_PORT/api" > /dev/null 2>&1; then
              break
            fi
            if [ $i -eq 30 ]; then
              echo "WebUI backend not available, skipping speedtest result storage"
              exit 0
            fi
            sleep 2
          done
          
          # Run speedtest and extract metrics
          RESULT=$(${pkgs.speedtest-cli}/bin/speedtest-cli --simple --secure 2>&1 || echo "ERROR")
          
          if [[ "$RESULT" == "ERROR" ]] || [[ -z "$RESULT" ]]; then
            echo "Speedtest failed"
            exit 1
          fi
          
          # Parse results (format: "Ping: X ms\nDownload: X Mbit/s\nUpload: X Mbit/s")
          PING=$(echo "$RESULT" | ${pkgs.gnugrep}/bin/grep "Ping:" | ${pkgs.gawk}/bin/awk '{print $2}')
          DOWNLOAD=$(echo "$RESULT" | ${pkgs.gnugrep}/bin/grep "Download:" | ${pkgs.gawk}/bin/awk '{print $2}')
          UPLOAD=$(echo "$RESULT" | ${pkgs.gnugrep}/bin/grep "Upload:" | ${pkgs.gawk}/bin/awk '{print $2}')
          
          # POST results to WebUI API
          ${pkgs.curl}/bin/curl -s -X POST "http://127.0.0.1:$BACKEND_PORT/api/speedtest/results" \
            -H "Content-Type: application/json" \
            -d "{\"download_mbps\": $DOWNLOAD, \"upload_mbps\": $UPLOAD, \"ping_ms\": $PING}" \
            > /dev/null || echo "Warning: Failed to store speedtest result in database"
          
          echo "Speedtest complete: Down=$DOWNLOAD Mbps, Up=$UPLOAD Mbps, Ping=$PING ms"
        '';
        User = "root";
      };
    };

    systemd.timers.speedtest = mkIf cfg.speedtest.enable {
      description = "Speedtest timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.speedtest.interval;
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    # Run speedtest when WAN gets IP address
    systemd.services.speedtest-on-wan-up = mkIf cfg.speedtest.enable {
      description = "Trigger speedtest when WAN is online";
      # Wait for network to be fully online
      after = [ "network-online.target" ]
        ++ optional (routerCfg.wan.type == "pppoe") "pppd-${routerCfg.wan.interface}.service";
      wants = [ "network-online.target" ];
      # For PPPoE, require the PPPoE connection to be up
      requires = optional (routerCfg.wan.type == "pppoe") "pppd-${routerCfg.wan.interface}.service";
      
      # Simple oneshot that completes immediately
      script = ''
        echo "[INFO] Triggering speedtest (async)..."
        systemctl start speedtest.service || true
      '';
      
      serviceConfig = {
        Type = "oneshot";
      };
    };
    
    # Timer to run on-wan-up service after boot (non-blocking)
    systemd.timers.speedtest-on-wan-up = mkIf cfg.speedtest.enable {
      description = "Trigger speedtest after WAN is stable";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";  # Wait 2 minutes after boot for WAN to stabilize
        Unit = "speedtest-on-wan-up.service";
      };
    };

  };
}

