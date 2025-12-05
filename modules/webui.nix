{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.router-webui;
  routerConfig = import ../router-config.nix;
  
  # Override paho-mqtt to disable tests (optional MQTT dependency we don't use)
  # This prevents build failures when paho-mqtt is pulled in as an optional dependency
  python311WithOverrides = pkgs.python311.override {
    packageOverrides = self: super: {
      paho-mqtt = super.paho-mqtt.overridePythonAttrs (attrs: {
        doCheck = false;
      });
    };
  };
  
  # Python environment with all dependencies
  pythonEnv = python311WithOverrides.withPackages (ps: with ps; [
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
    python-pam  # PAM authentication support
    manuf  # MAC address OUI vendor lookup
    httpx  # HTTP client for GitHub API requests
    apprise  # Notification service integration
    jinja2  # Template engine for notification messages
    redis  # Redis client for caching and write buffering
    celery  # Task queue for background workers
  ]);
  
  # Backend source (from flake input)
  backendSrc = inputs.router-webui + "/backend";
  
  # Frontend build (pre-built, committed to repository, from flake input)
  frontendBuild = inputs.router-webui + "/frontend/dist";
  
  # Documentation build (pre-built, committed to repository, from flake input)
  docsBuild = inputs.router-docs + "/dist";
  
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
    
    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug mode (verbose logging, auto-reload, etc.)";
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
    
    # Enable Redis for caching and write buffering
    # Use the servers configuration format for NixOS 25.11+
    services.redis.servers."" = {
      enable = true;
      bind = "127.0.0.1";
      port = 6379;
      # In-memory only (no persistence)
      settings = {
        # Disable AOF persistence (in-memory only)
        appendonly = "no";
        # Limit memory usage
        maxmemory = "256mb";
        maxmemory-policy = "allkeys-lru";
        # Note: RDB snapshots are enabled by default, but since data is ephemeral
        # and we're using maxmemory with eviction, this is acceptable for caching
      };
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
    
    # Create state directory and socket directory
    systemd.tmpfiles.rules = [
      "d /var/lib/router-webui 0750 router-webui router-webui -"
      "d /var/lib/router-webui/frontend 0755 router-webui router-webui -"
      "d /var/lib/router-webui/docs 0755 router-webui router-webui -"
      "d /run/router-webui 0750 router-webui router-webui -"
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
        PYTHONPATH = "${inputs.router-webui}";
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
        SYSTEMCTL_BIN = "${pkgs.systemd}/bin/systemctl";
        # Note: Don't set SUDO_BIN - use the wrapped sudo from /run/wrappers/bin/sudo
        # The store path sudo doesn't have setuid bit, but the wrapper does
      };
      
      serviceConfig = {
        Type = "simple";
        User = "router-webui";
        Group = "router-webui";
        WorkingDirectory = "${inputs.router-webui}";
        ExecStart = "${pythonEnv}/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port ${toString cfg.backendPort}";
        Restart = "always";
        RestartSec = "10s";
        
        # Set debug mode and ensure PATH includes /run/wrappers/bin for wrapped sudo
        Environment = [
          "DEBUG=${if cfg.debug then "true" else "false"}"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        ];
        
        # Security hardening
        PrivateTmp = true;
        # Don't use ProtectSystem as it prevents PAM from accessing necessary system files
        # Instead, rely on other security measures and the fact that the service runs as unprivileged user
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/router-webui" "/run" ];
        # Note: Don't include /run/unbound-* in ReadOnlyPaths as they may not exist if DNS is disabled
        # The service will have read access to them via /run being in ReadWritePaths when they do exist
        ReadOnlyPaths = [ 
          "/var/lib/kea" 
          "/proc"
          "/sys"
          "/usr"  # Protect /usr (read-only)
          "/boot"  # Protect /boot (read-only)
        ];
        
        # Allow access to system monitoring
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      };
    };
    
    # Celery worker service for background tasks
    systemd.services.router-webui-celery-worker = {
      description = "Router WebUI Celery Worker";
      after = [ "network.target" "postgresql.service" "redis.service" "router-webui-initdb.service" ];
      wants = [ "postgresql.service" "redis.service" ];
      requires = [ "router-webui-initdb.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        DATABASE_URL = "postgresql+asyncpg://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
        PYTHONPATH = "${inputs.router-webui}";
        COLLECTION_INTERVAL = toString cfg.collectionInterval;
        KEA_LEASE_FILE = "/var/lib/kea/dhcp4.leases";
        ROUTER_CONFIG_FILE = "/etc/nixos/router-config.nix";
        JWT_SECRET_FILE = "/var/lib/router-webui/jwt-secret";
        DOCUMENTATION_DIR = "/var/lib/router-webui/docs";
        # Provide absolute binary paths for commands used by backend
        NFT_BIN = "${pkgs.nftables}/bin/nft";
        IP_BIN = "${pkgs.iproute2}/bin/ip";
        TC_BIN = "${pkgs.iproute2}/bin/tc";
        CONNTRACK_BIN = "${pkgs.conntrack-tools}/bin/conntrack";
        FASTFETCH_BIN = "${pkgs.fastfetch}/bin/fastfetch";
        SPEEDTEST_BIN = "${pkgs.speedtest-cli}/bin/speedtest";
        SYSTEMCTL_BIN = "${pkgs.systemd}/bin/systemctl";
      };
      
      serviceConfig = {
        Type = "simple";
        User = "router-webui";
        Group = "router-webui";
        WorkingDirectory = "${inputs.router-webui}";
        ExecStart = "${pythonEnv}/bin/python -m celery -A backend.celery_app worker --loglevel=info --concurrency=2 --queues=aggregation,notifications,buffer_flush";
        Restart = "always";
        RestartSec = "10s";
        
        # Set debug mode and ensure PATH includes /run/wrappers/bin for wrapped sudo
        Environment = [
          "DEBUG=${if cfg.debug then "true" else "false"}"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        ];
        
        # Security hardening
        PrivateTmp = true;
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/router-webui" "/run" ];
        ReadOnlyPaths = [ 
          "/var/lib/kea" 
          "/proc"
          "/sys"
          "/usr"
          "/boot"
        ];
        
        # Allow access to system monitoring
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      };
    };
    
    # Celery Beat service for periodic task scheduling
    systemd.services.router-webui-celery-beat = {
      description = "Router WebUI Celery Beat Scheduler";
      after = [ "network.target" "postgresql.service" "redis.service" "router-webui-celery-worker.service" ];
      wants = [ "postgresql.service" "redis.service" "router-webui-celery-worker.service" ];
      requires = [ "router-webui-initdb.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        DATABASE_URL = "postgresql+asyncpg://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
        PYTHONPATH = "${inputs.router-webui}";
        COLLECTION_INTERVAL = toString cfg.collectionInterval;
        KEA_LEASE_FILE = "/var/lib/kea/dhcp4.leases";
        ROUTER_CONFIG_FILE = "/etc/nixos/router-config.nix";
        JWT_SECRET_FILE = "/var/lib/router-webui/jwt-secret";
        DOCUMENTATION_DIR = "/var/lib/router-webui/docs";
        # Provide absolute binary paths for commands used by backend
        NFT_BIN = "${pkgs.nftables}/bin/nft";
        IP_BIN = "${pkgs.iproute2}/bin/ip";
        TC_BIN = "${pkgs.iproute2}/bin/tc";
        CONNTRACK_BIN = "${pkgs.conntrack-tools}/bin/conntrack";
        FASTFETCH_BIN = "${pkgs.fastfetch}/bin/fastfetch";
        SPEEDTEST_BIN = "${pkgs.speedtest-cli}/bin/speedtest";
        SYSTEMCTL_BIN = "${pkgs.systemd}/bin/systemctl";
      };
      
      serviceConfig = {
        Type = "simple";
        User = "router-webui";
        Group = "router-webui";
        WorkingDirectory = "${inputs.router-webui}";
        ExecStart = "${pythonEnv}/bin/python -m celery -A backend.celery_app beat --loglevel=info";
        Restart = "always";
        RestartSec = "10s";
        
        # Set debug mode and ensure PATH includes /run/wrappers/bin for wrapped sudo
        Environment = [
          "DEBUG=${if cfg.debug then "true" else "false"}"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        ];
        
        # Security hardening
        PrivateTmp = true;
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/router-webui" "/run" ];
        ReadOnlyPaths = [ 
          "/var/lib/kea" 
          "/proc"
          "/sys"
          "/usr"
          "/boot"
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
    
    # Socket-activated helper service to control DNS/DHCP services (runs as root)
    # This follows NixOS best practices: avoid sudo in systemd services
    # The router-webui user can write commands to the socket
    systemd.sockets.router-webui-service-control = {
      description = "Router WebUI Service Control Socket";
      wantedBy = [ "sockets.target" ];
      before = [ "router-webui-backend.service" ];
      socketConfig = {
        ListenStream = "/run/router-webui/service-control.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "router-webui";
        # Accept one connection at a time, spawn new service instance per connection
        Accept = true;
      };
    };
    
    # Template service for socket activation (systemd will spawn instances automatically)
    # The @ symbol needs to be escaped in Nix attribute names
    systemd.services."router-webui-service-control@" = {
      description = "Router WebUI Service Control Helper";
      serviceConfig = {
        Type = "simple";
        User = "root";
        StandardInput = "socket";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      script = ''
        # Read command from stdin (format: ACTION SERVICE)
        IFS= read -r line || exit 0
        # Parse action and service
        ACTION=$(echo "$line" | cut -d' ' -f1)
        SERVICE=$(echo "$line" | cut -d' ' -f2-)
        
        # Validate action
        case "$ACTION" in
          start|stop|restart|reload)
            ;;
          *)
            echo "Invalid action: $ACTION" >&2
            exit 1
            ;;
        esac
        
        # Validate service (only allow specific DNS/DHCP services)
        case "$SERVICE" in
          unbound-homelab.service|unbound-lan.service|kea-dhcp4-homelab.service|kea-dhcp4-lan.service)
            ;;
          *)
            echo "Invalid service: $SERVICE" >&2
            exit 1
            ;;
        esac
        
        # Execute systemctl command and output result
        ${pkgs.systemd}/bin/systemctl "$ACTION" "$SERVICE" 2>&1
      '';
    };
    
    # Socket-activated helper service for PAM authentication (runs as root)
    # This is required because PAM can only authenticate other users when running as root
    # The router-webui user can write authentication requests to the socket
    systemd.sockets.router-webui-auth = {
      description = "Router WebUI Authentication Socket";
      wantedBy = [ "sockets.target" ];
      before = [ "router-webui-backend.service" ];
      socketConfig = {
        ListenStream = "/run/router-webui/auth.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "router-webui";
        # Accept one connection at a time, spawn new service instance per connection
        Accept = true;
      };
    };
    
    # Template service for authentication helper (systemd will spawn instances automatically)
    systemd.services."router-webui-auth@" = {
      description = "Router WebUI Authentication Helper";
      # Ensure the service unit doesn't inherit user restrictions
      unitConfig = {
        # Allow the service to run as root
      };
      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        # Ensure service runs as root - required for PAM to authenticate other users
        # Reference: https://pypi.org/project/python-pam/ - "You have root: you can check any account's password"
        StandardInput = "socket";
        # Output to socket so backend can read the response
        StandardOutput = "socket";
        # Errors go to journal for debugging
        StandardError = "journal";
        # Don't use security hardening that prevents root execution
        NoNewPrivileges = false;
        # Ensure we can actually switch to root
        SupplementaryGroups = [ ];
      };
      script = ''
        # Verify we're running as root (required for PAM to authenticate other users)
        CURRENT_UID=$(id -u)
        if [ "$CURRENT_UID" != "0" ]; then
          echo "ERROR: Service must run as root for PAM authentication" >&2
          echo "ERROR"  # Output ERROR so backend can detect it
          exit 1
        fi
        
        # Read authentication request from stdin (format: USERNAME\tPASSWORD)
        # Password may contain spaces, so we use tab as delimiter
        IFS=$'\t' read -r username password || exit 0
        
        # Validate username (alphanumeric, dash, underscore only, no spaces)
        if ! echo "$username" | grep -qE '^[a-zA-Z0-9_-]+$'; then
          echo "INVALID: Invalid username format" >&2
          exit 1
        fi
        
        # Check if user exists
        if ! id "$username" &>/dev/null; then
          echo "FAILURE: User does not exist"
          exit 0
        fi
        
        # Use Python to authenticate via PAM (running as root allows authenticating any user)
        # Reference: https://pypi.org/project/python-pam/ - root can authenticate any user
        # Write Python script to temporary file to avoid nested multiline string issues
        PYTHON_SCRIPT=$(mktemp)
        cat > "$PYTHON_SCRIPT" <<'PYEOF'
import sys
import os
import traceback
try:
    import pam
    username = sys.argv[1]
    password = sys.argv[2]
    # Verify we're running as root
    if os.geteuid() != 0:
        print("ERROR: Python process is not running as root (euid={})".format(os.geteuid()), flush=True)
        sys.exit(1)
    
    # Try to authenticate using PAM
    # When running as root, we can authenticate any user
    # Use 'login' service which is standard for user authentication
    try:
        # python-pam uses pam.authenticate() function
        p = pam.pam()
        result = p.authenticate(username, password, service="login")
        
        if result:
            print("SUCCESS", flush=True)
            sys.exit(0)
        else:
            # Authentication failed
            print("FAILURE", flush=True)
            sys.exit(0)
    except Exception as pam_error:
        # Get detailed error information
        error_msg = "ERROR: PAM exception: {}".format(str(pam_error))
        error_msg += "\nTraceback: {}".format(traceback.format_exc())
        print(error_msg, flush=True)
        sys.exit(1)
except Exception as e:
    # Print error to stdout so it can be captured
    error_msg = "ERROR: {}".format(str(e))
    error_msg += "\nTraceback: {}".format(traceback.format_exc())
    print(error_msg, flush=True)
    sys.exit(1)
PYEOF
        
        # Run Python script and capture output
        # Capture both stdout and stderr
        python_output=$(${pythonEnv}/bin/python3 "$PYTHON_SCRIPT" "$username" "$password" 2>&1)
        exit_code=$?
        
        # Always remove the script file
        rm -f "$PYTHON_SCRIPT"
        
        # Output the result to stdout (SUCCESS, FAILURE, or ERROR message)
        # This will be sent to the socket connection (StandardOutput = "socket")
        # The output must go to stdout so it can be read by the backend via the socket
        if [ -n "$python_output" ]; then
          # Output the Python script's output directly to stdout
          printf "%s" "$python_output"
        else
          # If no output but exit code indicates failure, output error
          if [ $exit_code -ne 0 ]; then
            printf "ERROR: Python script failed with exit code %s but produced no output" "$exit_code"
          fi
        fi
        
        # Also log errors to stderr so they appear in systemd journal
        if [ $exit_code -ne 0 ] && [ -n "$python_output" ]; then
          echo "ERROR: Authentication failed - $python_output" >&2
        fi
        
        # Exit with the Python script's exit code
        exit $exit_code
      '';
    };
  };
}

