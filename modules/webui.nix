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
    python-pam
    alembic
  ]);
  
  # Backend source
  backendSrc = ../webui/backend;
  
  # Frontend build (if exists)
  frontendSrc = ../webui/frontend;
  
in

{
  options.services.router-webui = {
    enable = mkEnableOption "Router WebUI monitoring dashboard";
    
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for the WebUI backend server";
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
    };
    
    # Create system user for the service
    users.users.router-webui = {
      isSystemUser = true;
      group = "router-webui";
      description = "Router WebUI service user";
    };
    
    users.groups.router-webui = {};
    
    # Create state directory
    systemd.tmpfiles.rules = [
      "d /var/lib/router-webui 0750 router-webui router-webui -"
      "d /var/lib/router-webui/frontend 0755 router-webui router-webui -"
    ];
    
    # Database initialization service
    systemd.services.router-webui-initdb = {
      description = "Router WebUI Database Initialization";
      after = [ "postgresql.service" ];
      before = [ "router-webui-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = cfg.database.user;
        RemainAfterExit = true;
      };
      
      script = ''
        # Wait for PostgreSQL to be ready
        until ${pkgs.postgresql}/bin/pg_isready -h ${cfg.database.host} -p ${toString cfg.database.port}; do
          echo "Waiting for PostgreSQL..."
          sleep 1
        done
        
        # Run database schema
        ${pkgs.postgresql}/bin/psql -h ${cfg.database.host} -p ${toString cfg.database.port} -d ${cfg.database.name} < ${backendSrc}/schema.sql || true
      '';
    };
    
    # Backend service
    systemd.services.router-webui-backend = {
      description = "Router WebUI Backend (FastAPI)";
      after = [ "network.target" "postgresql.service" "router-webui-initdb.service" ];
      wants = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        DATABASE_URL = "postgresql+asyncpg://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
        PYTHONPATH = "${backendSrc}";
        COLLECTION_INTERVAL = toString cfg.collectionInterval;
        PORT = toString cfg.port;
        KEA_LEASE_FILE = "/var/lib/kea/dhcp4.leases";
        ROUTER_CONFIG_FILE = "/etc/nixos/router-config.nix";
      };
      
      serviceConfig = {
        Type = "simple";
        User = "router-webui";
        Group = "router-webui";
        WorkingDirectory = backendSrc;
        ExecStart = "${pythonEnv}/bin/python -m uvicorn main:app --host 0.0.0.0 --port ${toString cfg.port}";
        Restart = "always";
        RestartSec = "10s";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/router-webui" ];
        ReadOnlyPaths = [ "/var/lib/kea" "/run/unbound-homelab" "/run/unbound-lan" ];
        
        # Allow access to system monitoring
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_SYS_PTRACE" ];
      };
    };
    
    # JWT secret management via sops
    sops.secrets."webui-jwt-secret" = mkIf (cfg.jwtSecretFile != null) {
      sopsFile = cfg.jwtSecretFile;
      owner = "router-webui";
      mode = "0400";
    };
    
    # Firewall configuration
    networking.firewall.allowedTCPPorts = [ cfg.port ];
    
    # Add router-webui service to monitored services
    # This allows the WebUI to monitor itself
    environment.etc."router-webui/monitored-services.conf".text = ''
      router-webui-backend
    '';
  };
}

