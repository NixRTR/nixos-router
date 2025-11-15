{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router.dashboard;
  routerCfg = config.router;
in

{
  options.router.dashboard = {
    enable = mkEnableOption "Grafana dashboard for router monitoring";

    grafanaPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };

    prometheusPort = mkOption {
      type = types.port;
      default = 9090;
      description = "Port for Prometheus";
    };

    nodeExporterPort = mkOption {
      type = types.port;
      default = 9100;
      description = "Port for Node Exporter";
    };

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

      exporterPort = mkOption {
        type = types.port;
        default = 9516;
        description = "Port for speedtest exporter metrics";
      };
    };
  };

  config = mkIf cfg.enable {
    # Prometheus - metrics collection
    services.prometheus = {
      enable = true;
      port = cfg.prometheusPort;

      exporters.node = {
        enable = true;
        enabledCollectors = [
          "systemd"      # Service status
          "netdev"       # Network interfaces
          "netstat"      # Network statistics
          "conntrack"    # Connection tracking
          "cpu"          # CPU stats
          "diskstats"    # Disk I/O
          "filesystem"   # Filesystem usage
          "loadavg"      # System load
          "meminfo"      # Memory info
          "vmstat"       # Virtual memory stats
        ] ++ optionals cfg.speedtest.enable [ "textfile" ];
        extraFlags = optionals cfg.speedtest.enable [ "--collector.textfile.directory=/var/lib/speedtest" ];
        port = cfg.nodeExporterPort;
      };

      scrapeConfigs = [
        {
          job_name = "router";
          static_configs = [{
            targets = [ "localhost:${toString cfg.nodeExporterPort}" ];
            labels = {
              alias = config.networking.hostName;
              role = "router";
            };
          }];
          scrape_interval = "5s";
        }
      ] ++ optionals cfg.speedtest.enable [
        {
          job_name = "speedtest";
          static_configs = [{
            targets = [ "localhost:${toString cfg.speedtest.exporterPort}" ];
          }];
          scrape_interval = "5m";  # Scrape frequently, but speedtest runs on schedule
        }
      ];
    };

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
          
          # Write metrics to textfile for node_exporter
          METRICS_FILE="/var/lib/speedtest/metrics.prom"
          mkdir -p /var/lib/speedtest
          
          cat > "$METRICS_FILE" <<EOF
          # HELP speedtest_ping_ms Ping latency in milliseconds
          # TYPE speedtest_ping_ms gauge
          speedtest_ping_ms $PING
          # HELP speedtest_download_mbps Download speed in Mbps
          # TYPE speedtest_download_mbps gauge
          speedtest_download_mbps $DOWNLOAD
          # HELP speedtest_upload_mbps Upload speed in Mbps
          # TYPE speedtest_upload_mbps gauge
          speedtest_upload_mbps $UPLOAD
          # HELP speedtest_timestamp Last speedtest run timestamp
          # TYPE speedtest_timestamp gauge
          speedtest_timestamp $(date +%s)
          EOF
          
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
        ++ optional (routerCfg.wan.type == "pppoe") "pppd@${routerCfg.wan.interface}.service";
      wants = [ "network-online.target" ];
      # For PPPoE, require the PPPoE connection to be up
      requires = optional (routerCfg.wan.type == "pppoe") "pppd@${routerCfg.wan.interface}.service";
      wantedBy = [ "multi-user.target" ];
      
      # Add delay to ensure connection is stable before running speedtest
      script = ''
        echo "[INFO] Waiting for WAN connection to stabilize..."
        sleep 30
        echo "[INFO] Triggering speedtest..."
        systemctl start speedtest.service || true
      '';
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Grafana - visualization
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = cfg.grafanaPort;
          domain = config.networking.hostName;
          root_url = "http://%(domain)s:${toString cfg.grafanaPort}/";
        };
        security = {
          admin_user = "admin";
          admin_password = "admin";  # Change on first login
        };
        analytics.reporting_enabled = false;
        analytics.check_for_updates = false;
      };

      provision = {
        enable = true;

        # Auto-configure Prometheus data source
        datasources.settings = {
          apiVersion = 1;
          datasources = [{
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${toString cfg.prometheusPort}";
            isDefault = true;
            jsonData = {
              timeInterval = "5s";
            };
          }];
        };

        # Auto-load router dashboard
        dashboards.settings = {
          apiVersion = 1;
          providers = [{
            name = "Router Dashboards";
            type = "file";
            disableDeletion = false;
            updateIntervalSeconds = 10;
            allowUiUpdates = true;
            options.path = "/etc/grafana-dashboards";
          }];
        };
      };
    };

    # Create dashboard file
    environment.etc."grafana-dashboards/router-monitoring.json" = {
      text = builtins.toJSON {
        title = "Router Monitoring";
        uid = "router-main";
        tags = [ "router" "network" "system" ];
        timezone = "browser";
        schemaVersion = 16;
        version = 1;
        refresh = "5s";

          panels = [
            # WAN Interface Status
            {
              id = 1;
              title = "WAN Interface - ${routerCfg.wan.interface}";
              type = "graph";
              gridPos = { x = 0; y = 0; w = 12; h = 8; };
              targets = [
                {
                  expr = ''rate(node_network_receive_bytes_total{device="${routerCfg.wan.interface}"}[1m]) * 8'';
                  legendFormat = "Download";
                  refId = "A";
                }
                {
                  expr = ''rate(node_network_transmit_bytes_total{device="${routerCfg.wan.interface}"}[1m]) * 8'';
                  legendFormat = "Upload";
                  refId = "B";
                }
              ];
              yaxes = [
                { format = "bps"; label = "Bandwidth"; }
                { format = "short"; }
              ];
              legend.show = true;
              nullPointMode = "null";
            }

            # HOMELAB Bridge (br0)
            {
              id = 2;
              title = "HOMELAB Bridge (br0)";
              type = "graph";
              gridPos = { x = 12; y = 0; w = 12; h = 4; };
              targets = [
                {
                  expr = ''rate(node_network_receive_bytes_total{device="br0"}[1m]) * 8'';
                  legendFormat = "Download";
                  refId = "A";
                }
                {
                  expr = ''rate(node_network_transmit_bytes_total{device="br0"}[1m]) * 8'';
                  legendFormat = "Upload";
                  refId = "B";
                }
              ];
              yaxes = [
                { format = "bps"; label = "Bandwidth"; }
                { format = "short"; }
              ];
              legend.show = true;
              nullPointMode = "null";
            }

            # LAN Bridge (br1)
            {
              id = 12;
              title = "LAN Bridge (br1)";
              type = "graph";
              gridPos = { x = 12; y = 4; w = 12; h = 4; };
              targets = [
                {
                  expr = ''rate(node_network_receive_bytes_total{device="br1"}[1m]) * 8'';
                  legendFormat = "Download";
                  refId = "A";
                }
                {
                  expr = ''rate(node_network_transmit_bytes_total{device="br1"}[1m]) * 8'';
                  legendFormat = "Upload";
                  refId = "B";
                }
              ];
              yaxes = [
                { format = "bps"; label = "Bandwidth"; }
                { format = "short"; }
              ];
              legend.show = true;
              nullPointMode = "null";
            }

            # Network Interface Status
            {
              id = 3;
              title = "Interface Status";
              type = "stat";
              gridPos = { x = 0; y = 8; w = 6; h = 4; };
              targets = [{
                expr = ''node_network_up{device=~"${routerCfg.wan.interface}|br0|br1|ppp0"}'';
                legendFormat = "{{device}}";
                refId = "A";
              }];
              options = {
                reduceOptions = {
                  values = false;
                  calcs = [ "lastNotNull" ];
                };
                textMode = "auto";
                colorMode = "value";
              };
              fieldConfig = {
                defaults = {
                  mappings = [
                    { type = "value"; options = { "0" = { text = "Down"; color = "red"; }; }; }
                    { type = "value"; options = { "1" = { text = "Up"; color = "green"; }; }; }
                  ];
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "red"; }
                      { value = 1; color = "green"; }
                    ];
                  };
                };
              };
            }

            # CPU Usage
            {
              id = 4;
              title = "CPU Usage";
              type = "gauge";
              gridPos = { x = 6; y = 8; w = 6; h = 4; };
              targets = [{
                expr = ''100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
                legendFormat = "CPU %";
                refId = "A";
              }];
              options = {
                showThresholdLabels = false;
                showThresholdMarkers = true;
              };
              fieldConfig = {
                defaults = {
                  unit = "percent";
                  min = 0;
                  max = 100;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "green"; }
                      { value = 70; color = "yellow"; }
                      { value = 90; color = "red"; }
                    ];
                  };
                };
              };
            }

            # Memory Usage
            {
              id = 5;
              title = "Memory Usage";
              type = "gauge";
              gridPos = { x = 12; y = 8; w = 6; h = 4; };
              targets = [{
                expr = ''(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'';
                legendFormat = "Memory %";
                refId = "A";
              }];
              options = {
                showThresholdLabels = false;
                showThresholdMarkers = true;
              };
              fieldConfig = {
                defaults = {
                  unit = "percent";
                  min = 0;
                  max = 100;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "green"; }
                      { value = 80; color = "yellow"; }
                      { value = 95; color = "red"; }
                    ];
                  };
                };
              };
            }

            # System Load
            {
              id = 6;
              title = "System Load";
              type = "stat";
              gridPos = { x = 18; y = 8; w = 6; h = 4; };
              targets = [{
                expr = "node_load1";
                legendFormat = "1m";
                refId = "A";
              }];
              options = {
                reduceOptions = {
                  values = false;
                  calcs = [ "lastNotNull" ];
                };
                textMode = "auto";
                colorMode = "value";
              };
              fieldConfig = {
                defaults = {
                  decimals = 2;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "green"; }
                      { value = 2; color = "yellow"; }
                      { value = 4; color = "red"; }
                    ];
                  };
                };
              };
            }

            # Packet Errors/Drops
            {
              id = 7;
              title = "Network Errors & Drops";
              type = "graph";
              gridPos = { x = 0; y = 12; w = 12; h = 6; };
              targets = [
                {
                  expr = ''rate(node_network_receive_errs_total{device="${routerCfg.wan.interface}"}[1m])'';
                  legendFormat = "WAN RX Errors";
                  refId = "A";
                }
                {
                  expr = ''rate(node_network_transmit_errs_total{device="${routerCfg.wan.interface}"}[1m])'';
                  legendFormat = "WAN TX Errors";
                  refId = "B";
                }
                {
                  expr = ''rate(node_network_receive_drop_total{device="${routerCfg.wan.interface}"}[1m])'';
                  legendFormat = "WAN RX Drops";
                  refId = "C";
                }
              ];
              yaxes = [
                { format = "pps"; label = "Packets/sec"; }
                { format = "short"; }
              ];
              legend.show = true;
            }

            # System Services Status
            {
              id = 8;
              title = "Service Status";
              type = "stat";
              gridPos = { x = 12; y = 12; w = 12; h = 6; };
              targets = [
                {
                  expr = ''node_systemd_unit_state{name=~"blocky.service|kea-dhcp4-server.service|pppd-.*.service",state="active"}'';
                  legendFormat = "{{name}}";
                  refId = "A";
                }
              ];
              options = {
                reduceOptions = {
                  values = false;
                  calcs = [ "lastNotNull" ];
                };
                textMode = "name";
                colorMode = "background";
              };
              fieldConfig = {
                defaults = {
                  mappings = [
                    { type = "value"; options = { "0" = { text = "Inactive"; color = "red"; }; }; }
                    { type = "value"; options = { "1" = { text = "Active"; color = "green"; }; }; }
                  ];
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "red"; }
                      { value = 1; color = "green"; }
                    ];
                  };
                };
              };
            }

            # System Uptime
            {
              id = 9;
              title = "System Uptime";
              type = "stat";
              gridPos = { x = 0; y = 18; w = 8; h = 3; };
              targets = [{
                expr = "time() - node_boot_time_seconds";
                legendFormat = "Uptime";
                refId = "A";
              }];
              options = {
                reduceOptions = {
                  values = false;
                  calcs = [ "lastNotNull" ];
                };
                textMode = "auto";
                colorMode = "none";
              };
              fieldConfig = {
                defaults = {
                  unit = "s";
                };
              };
            }

            # Disk Usage
            {
              id = 10;
              title = "Disk Usage";
              type = "gauge";
              gridPos = { x = 8; y = 18; w = 8; h = 3; };
              targets = [{
                expr = ''100 - ((node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}) * 100)'';
                legendFormat = "Root FS";
                refId = "A";
              }];
              options = {
                showThresholdLabels = false;
                showThresholdMarkers = true;
              };
              fieldConfig = {
                defaults = {
                  unit = "percent";
                  min = 0;
                  max = 100;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "green"; }
                      { value = 80; color = "yellow"; }
                      { value = 95; color = "red"; }
                    ];
                  };
                };
              };
            }

            # Active Connections
            {
              id = 11;
              title = "Active Network Connections";
              type = "stat";
              gridPos = { x = 16; y = 18; w = 8; h = 3; };
              targets = [{
                expr = "node_netstat_Tcp_CurrEstab";
                legendFormat = "TCP Connections";
                refId = "A";
              }];
              options = {
                reduceOptions = {
                  values = false;
                  calcs = [ "lastNotNull" ];
                };
                textMode = "auto";
                colorMode = "value";
              };
              fieldConfig = {
                defaults = {
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "green"; }
                      { value = 1000; color = "yellow"; }
                      { value = 5000; color = "red"; }
                    ];
                  };
                };
              };
            }
          ] ++ optionals cfg.speedtest.enable [
            # Speedtest Download Speed
            {
              id = 13;
              title = "Speedtest - Download";
              type = "gauge";
              gridPos = { x = 0; y = 21; w = 8; h = 5; };
              targets = [{
                expr = "speedtest_download_mbps";
                legendFormat = "Download";
                refId = "A";
              }];
              options = {
                showThresholdLabels = false;
                showThresholdMarkers = true;
              };
              fieldConfig = {
                defaults = {
                  unit = "Mbits";
                  min = 0;
                  max = 1000;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "red"; }
                      { value = 10; color = "yellow"; }
                      { value = 50; color = "green"; }
                    ];
                  };
                };
              };
            }

            # Speedtest Upload Speed
            {
              id = 14;
              title = "Speedtest - Upload";
              type = "gauge";
              gridPos = { x = 8; y = 21; w = 8; h = 5; };
              targets = [{
                expr = "speedtest_upload_mbps";
                legendFormat = "Upload";
                refId = "A";
              }];
              options = {
                showThresholdLabels = false;
                showThresholdMarkers = true;
              };
              fieldConfig = {
                defaults = {
                  unit = "Mbits";
                  min = 0;
                  max = 100;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "red"; }
                      { value = 5; color = "yellow"; }
                      { value = 20; color = "green"; }
                    ];
                  };
                };
              };
            }

            # Speedtest Ping
            {
              id = 15;
              title = "Speedtest - Ping";
              type = "stat";
              gridPos = { x = 16; y = 21; w = 8; h = 5; };
              targets = [{
                expr = "speedtest_ping_ms";
                legendFormat = "Ping";
                refId = "A";
              }];
              options = {
                reduceOptions = {
                  values = false;
                  calcs = [ "lastNotNull" ];
                };
                textMode = "value_and_name";
                colorMode = "value";
              };
              fieldConfig = {
                defaults = {
                  unit = "ms";
                  decimals = 1;
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      { value = null; color = "green"; }
                      { value = 50; color = "yellow"; }
                      { value = 100; color = "red"; }
                    ];
                  };
                };
              };
            }
            ];
      };
      mode = "0644";
    };

    # Open firewall for Grafana
    networking.firewall.allowedTCPPorts = [ cfg.grafanaPort ];
  };
}

