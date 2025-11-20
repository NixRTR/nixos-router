{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-webui;
  routerConfig = import ../router-config.nix;
  
  # Python environment with all dependencies
  pythonEnv = pkgs.python311.withPackages (ps: with ps; [
    fastapi
    uvicorn
    websockets
    sqlalchemy
    asyncpg
    psutil
    pydantic
    pydantic-settings
    python-jose
    passlib
    alembic
    bcrypt
    pamela  # PAM authentication support
    manuf  # MAC address OUI vendor lookup
    httpx  # HTTP client for GitHub API requests
  ]);
  
  # Backend source
  backendSrc = ../webui/backend;
  
  # Frontend build (pre-built, committed to repository)
  frontendSrc = ../webui/frontend;
  frontendBuild = frontendSrc + "/dist";
  
  # Documentation source and build (pre-built, committed to repository)
  docsSrc = ../docs;
  docsBuild = docsSrc + "/dist";
  
in

{
  options.services.router-webui = {
    enable = mkEnableOption "Router WebUI monitoring dashboard";
    
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for nginx (public-facing)";
    };
    
    backendPort = mkOption {
      type = types.port;
      default = 8081;
      description = "Port for the FastAPI backend (internal)";
    };
    
    database = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "PostgreSQL host";
      };
      
      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };
      
      name = mkOption {
        type = types.str;
        default = "router_webui";
        description = "PostgreSQL database name";
      };
      
      user = mkOption {
        type = types.str;
        default = "router_webui";
        description = "PostgreSQL user";
      };
    };
    
    collectionInterval = mkOption {
      type = types.int;
      default = 2;
      description = "Data collection interval in seconds";
    };
    
    jwtSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to JWT secret key file (managed by sops)";
    };
  };
  
  config = mkIf cfg.enable {
    # Enable PostgreSQL
    services.postgresql = {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [{
        name = cfg.database.user;
        ensureDBOwnership = true;
      }];
      
      # Allow local trust authentication for the router_webui user
      authentication = pkgs.lib.mkOverride 10 ''
        local all all trust
        host all all 127.0.0.1/32 trust
        host all all ::1/128 trust
      '';
    };
    
    # Create system user for the service
    users.users.router-webui = {
      isSystemUser = true;
      group = "router-webui";
      extraGroups = [ "shadow" "kea" ];  # shadow for PAM auth, kea for DHCP leases
      description = "Router WebUI service user";
    };
    
    users.groups.router-webui = {};
    
    # Configure PAM to allow router-webui user to authenticate
    security.pam.services.router-webui = {
      allowNullPassword = false;
      unixAuth = true;
    };
    
    # Create state directory
    systemd.tmpfiles.rules = [
      "d /var/lib/router-webui 0750 router-webui router-webui -"
      "d /var/lib/router-webui/frontend 0755 router-webui router-webui -"
      "d /var/lib/router-webui/docs 0755 router-webui router-webui -"
    ];
    
    # Copy frontend build to state directory
    systemd.services.router-webui-frontend-install = {
      description = "Install Router WebUI Frontend";
      wantedBy = [ "multi-user.target" ];
      before = [ "router-webui-backend.service" ];
      after = [ "local-fs.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        echo "Installing Router WebUI frontend..."
        rm -rf /var/lib/router-webui/frontend/*
        cp -r ${frontendBuild}/* /var/lib/router-webui/frontend/
        chown -R router-webui:router-webui /var/lib/router-webui/frontend
        chmod -R 755 /var/lib/router-webui/frontend
        # Ensure nginx (in router-webui group) can read files
        chmod -R g+r /var/lib/router-webui/frontend
        echo "Frontend installed successfully"
      '';
    };
    
    # Database initialization service
    systemd.services.router-webui-initdb = {
      description = "Router WebUI Database Initialization";
      after = [ "postgresql.service" ];
      before = [ "router-webui-migrate.service" "router-webui-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";  # Run as postgres user to execute database commands
        RemainAfterExit = true;
      };
      
      script = ''
        # Wait for PostgreSQL to be ready
        until ${pkgs.postgresql}/bin/pg_isready -h ${cfg.database.host} -p ${toString cfg.database.port}; do
          echo "Waiting for PostgreSQL..."
          sleep 1
        done
        
        # Run database schema as the router_webui database user
        ${pkgs.postgresql}/bin/psql -U ${cfg.database.user} -d ${cfg.database.name} -f ${backendSrc}/schema.sql || true
      '';
    };
    
    # Database migration service
    systemd.services.router-webui-migrate = {
      description = "Router WebUI Database Migrations";
      after = [ "router-webui-initdb.service" ];
      before = [ "router-webui-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";  # Run as postgres user to execute database commands
        RemainAfterExit = true;
      };
      
      script = ''
        echo "Running database migrations..."
        
        # Run migrations in order
        for migration in ${backendSrc}/migrations/*.sql; do
          if [ -f "$migration" ]; then
            echo "Applying migration: $(basename $migration)"
            ${pkgs.postgresql}/bin/psql -U ${cfg.database.user} -d ${cfg.database.name} -f "$migration" || {
              echo "Warning: Migration $(basename $migration) failed or already applied"
            }
          fi
        done
        
        echo "Migrations completed"
      '';
    };
    
    # JWT secret generation service
    systemd.services.router-webui-jwt-init = {
      description = "Generate JWT secret for Router WebUI";
      wantedBy = [ "multi-user.target" ];
      before = [ "router-webui-backend.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        if [ ! -f /var/lib/router-webui/jwt-secret ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/router-webui/jwt-secret
          chmod 600 /var/lib/router-webui/jwt-secret
          chown router-webui:router-webui /var/lib/router-webui/jwt-secret
        fi
      '';
    };
    
    # Documentation install service (copies pre-built docs)
    systemd.services.router-webui-docs-init = {
      description = "Install Router WebUI Documentation (React)";
      wantedBy = [ "multi-user.target" ];
      before = [ "router-webui-backend.service" ];
      after = [ "local-fs.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        echo "Installing Router WebUI documentation..."
        mkdir -p /var/lib/router-webui/docs
        rm -rf /var/lib/router-webui/docs/*
        cp -r ${docsBuild}/* /var/lib/router-webui/docs/
        chown -R router-webui:router-webui /var/lib/router-webui/docs
        chmod -R 755 /var/lib/router-webui/docs
        # Ensure nginx (in router-webui group) can read files
        chmod -R g+r /var/lib/router-webui/docs
        echo "Documentation installed successfully"
      '';
    };
    
    # Backend service (internal, only accessible via nginx)
    systemd.services.router-webui-backend = {
      description = "Router WebUI Backend (FastAPI)";
      after = [ "network.target" "postgresql.service" "router-webui-initdb.service" "router-webui-jwt-init.service" "router-webui-frontend-install.service" "router-webui-docs-init.service" ];
      wants = [ "postgresql.service" ];
      requires = [ "router-webui-jwt-init.service" "router-webui-frontend-install.service" "router-webui-docs-init.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        DATABASE_URL = "postgresql+asyncpg://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
        PYTHONPATH = "${../webui}";
        COLLECTION_INTERVAL = toString cfg.collectionInterval;
        PORT = toString cfg.backendPort;
        KEA_LEASE_FILE = "/var/lib/kea/dhcp4.leases";
        ROUTER_CONFIG_FILE = "/etc/nixos/router-config.nix";
        JWT_SECRET_FILE = "/var/lib/router-webui/jwt-secret";
        DOCUMENTATION_DIR = "/var/lib/router-webui/docs";
        # Provide absolute binary paths for commands used by backend
        NFT_BIN = "${pkgs.nftables}/bin/nft";
        IP_BIN = "${pkgs.iproute2}/bin/ip";
        TC_BIN = "${pkgs.iproute2}/bin/tc";  # Traffic control (for CAKE statistics)
        CONNTRACK_BIN = "${pkgs.conntrack-tools}/bin/conntrack";
        FASTFETCH_BIN = "${pkgs.fastfetch}/bin/fastfetch";
        SPEEDTEST_BIN = "${pkgs.speedtest-cli}/bin/speedtest";
      };
      
      serviceConfig = {
        Type = "simple";
        User = "router-webui";
        Group = "router-webui";
        WorkingDirectory = "${../webui}";
        ExecStart = "${pythonEnv}/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port ${toString cfg.backendPort}";
        Restart = "always";
        RestartSec = "10s";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/router-webui" ];
        ReadOnlyPaths = [ 
          "/var/lib/kea" 
          "/run/unbound-homelab" 
          "/run/unbound-lan"
          "/proc"
          "/sys"
        ];
        
        # Allow access to system monitoring
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      };
    };
    
    # Nginx reverse proxy
    services.nginx = {
      enable = true;
      
      # Enable gzip compression globally
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      
      virtualHosts."router-webui" = {
        listen = [{
          addr = "0.0.0.0";
          port = cfg.port;
        }];
        
        root = "/var/lib/router-webui/frontend";
        
        # Additional gzip configuration for this virtual host
        extraConfig = ''
          # Enable gzip compression
          gzip on;
          gzip_vary on;
          gzip_proxied any;
          gzip_comp_level 6;
          gzip_types
            text/plain
            text/css
            text/xml
            text/javascript
            application/json
            application/javascript
            application/xml+rss
            application/rss+xml
            application/atom+xml
            image/svg+xml
            font/truetype
            font/opentype
            application/vnd.ms-fontobject
            application/font-woff
            application/font-woff2;
          gzip_min_length 256;
          gzip_disable "msie6";
        '';
        
        locations = {
          # Proxy API requests to FastAPI backend (must come before /)
          # FastAPI routers already have /api in their prefix, so we proxy /api to backend root
          # This way /api/bandwidth/... becomes /api/bandwidth/... on the backend (correct)
          "/api" = {
            proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host:$server_port;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host:$server_port;
              proxy_redirect http://$host/ http://$host:$server_port/;
              proxy_redirect http://$host/api/ http://$host:$server_port/api/;
            '';
          };
          
          # Proxy WebSocket connections (must come before /)
          "/ws" = {
            proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host:$server_port;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host:$server_port;
            '';
          };
          
          # Serve documentation assets (must come before /docs)
          "/docs/assets" = {
            root = "/var/lib/router-webui";
            extraConfig = ''
              expires 1y;
              add_header Cache-Control "public, immutable";
            '';
          };

          # Serve documentation screenshots (must come before /docs)
          "/docs/screenshots" = {
            root = "/var/lib/router-webui";
            extraConfig = ''
              expires 1y;
              add_header Cache-Control "public, immutable";
            '';
          };

          # Serve documentation site (must come before /)
          "/docs" = {
            root = "/var/lib/router-webui";
            tryFiles = "$uri $uri/ /docs/index.html";
          };
          
          # Serve frontend assets (must come before /)
          "/assets" = {
            root = "/var/lib/router-webui/frontend";
            extraConfig = ''
              expires 1y;
              add_header Cache-Control "public, immutable";
            '';
          };
          
          # Serve frontend (SPA fallback to index.html) - catch-all
          "/" = {
            root = "/var/lib/router-webui/frontend";
            tryFiles = "$uri $uri/ /index.html";
          };
        };
      };
    };
    
    # JWT secret management via sops
    sops.secrets."webui-jwt-secret" = mkIf (cfg.jwtSecretFile != null) {
      sopsFile = cfg.jwtSecretFile;
      owner = "router-webui";
      mode = "0400";
    };
    
    # Firewall configuration (nginx port, not backend port)
    networking.firewall.allowedTCPPorts = [ cfg.port ];
    
    # Ensure nginx can read static files
    users.users.nginx.extraGroups = [ "router-webui" ];
    
    # Add router-webui service to monitored services
    # This allows the WebUI to monitor itself
    environment.etc."router-webui/monitored-services.conf".text = ''
      router-webui-backend
    '';
  };
}

