{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-webui;
  routerConfig = import ../router-config.nix;
  
  # pyhw package (not in nixpkgs, build it manually)
  pyhw = pkgs.python311Packages.buildPythonPackage rec {
    pname = "pyhw";
    version = "0.15.3";
    format = "pyproject";
    
    src = pkgs.python311Packages.fetchPypi {
      inherit pname version;
      sha256 = "97c7cf2d16ece0decc51c898f2691c3894e6e5f1c60fc9f153c9361dce578c68";
    };
    
    nativeBuildInputs = with pkgs.python311Packages; [
      setuptools  # Required for pyproject builds
    ];
    
    propagatedBuildInputs = with pkgs.python311Packages; [
      # pyhw only depends on Python standard library according to PyPI
      # But it may have optional dependencies, check if needed
    ];
    
    # No tests in the package
    doCheck = false;
    
    meta = with lib; {
      description = "A neofetch-like command line tool for fetching system information";
      homepage = "https://pypi.org/project/pyhw/";
      license = licenses.bsd3;
    };
  };
  
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
    pillow  # Image processing for ANSI to image conversion
    pyhw  # System information tool (neofetch/fastfetch alternative)
  ]);
  
  # Backend source
  backendSrc = ../webui/backend;
  
  # Frontend build (pre-built, committed to repository)
  frontendSrc = ../webui/frontend;
  frontendBuild = frontendSrc + "/dist";
  
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
    
    # Backend service
    systemd.services.router-webui-backend = {
      description = "Router WebUI Backend (FastAPI)";
      after = [ "network.target" "postgresql.service" "router-webui-initdb.service" "router-webui-jwt-init.service" "router-webui-frontend-install.service" ];
      wants = [ "postgresql.service" ];
      requires = [ "router-webui-jwt-init.service" "router-webui-frontend-install.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        DATABASE_URL = "postgresql+asyncpg://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
        PYTHONPATH = "${../webui}";
        COLLECTION_INTERVAL = toString cfg.collectionInterval;
        PORT = toString cfg.port;
        KEA_LEASE_FILE = "/var/lib/kea/dhcp4.leases";
        ROUTER_CONFIG_FILE = "/etc/nixos/router-config.nix";
        JWT_SECRET_FILE = "/var/lib/router-webui/jwt-secret";
        # Provide absolute binary paths for commands used by backend
        NFT_BIN = "${pkgs.nftables}/bin/nft";
        IP_BIN = "${pkgs.iproute2}/bin/ip";
        CONNTRACK_BIN = "${pkgs.conntrack-tools}/bin/conntrack";
      };
      
      serviceConfig = {
        Type = "simple";
        User = "router-webui";
        Group = "router-webui";
        WorkingDirectory = "${../webui}";
        ExecStart = "${pythonEnv}/bin/python -m uvicorn backend.main:app --host 0.0.0.0 --port ${toString cfg.port}";
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

