{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  
  # Extract bridge information from config
  bridges = routerConfig.lan.bridges;
  bridgeIPs = map (b: b.ipv4.address) bridges;

in

{
  # PowerDNS Recursor - Recursive DNS resolver with caching
  services.pdns-recursor = {
    enable = true;
    # Forward to upstream DNS servers (list format for YAML)
    forwardZones = {
      "." = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
    };
    settings = {
      # Listen addresses - Listen on all bridge IPs plus localhost
      local-address = (map (ip: "${ip}:53") bridgeIPs) ++ [ "127.0.0.1:53" ];
      
      # Allow queries from private networks
      allow-from = [
        "127.0.0.0/8"
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
      ];
      
      # Caching settings
      max-cache-entries = 1000000;
      max-cache-ttl = 7200;  # 2 hours
      max-negative-ttl = 3600;  # 1 hour for negative caching
      
      # Performance optimizations
      threads = 2;
      pdns-distributes-queries = "yes";
      
      # Security
      dnssec = "process-no-validate";
      
      # Logging
      loglevel = 4;  # Info level
      log-common-errors = "yes";
    };
  };

  # PowerDNS Authoritative Server - For local zone management
  services.powerdns = {
    enable = true;
    extraConfig = ''
      # Run on different port than recursor
      local-port=5300
      local-address=127.0.0.1
      
      # Use SQLite backend for zone storage
      launch=gsqlite3
      gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
      
      # API for PowerDNS Admin
      api=yes
      api-key=$POWERDNS_API_KEY
      webserver=yes
      webserver-address=0.0.0.0
      webserver-port=8081
      webserver-allow-from=0.0.0.0/0
      
      # Security
      security-poll-suffix=
      
      # Logging
      loglevel=4
      log-dns-queries=no
      log-dns-details=no
    '';
  };
  
  # Generate and load PowerDNS API key
  systemd.services.pdns.serviceConfig.EnvironmentFile = "-/var/lib/powerdns/api-key-env";
  
  systemd.services.pdns.preStart = ''
    # Ensure directory exists
    mkdir -p /var/lib/powerdns
    chown pdns:pdns /var/lib/powerdns
    
    # Generate API key if it doesn't exist
    if [ ! -f /var/lib/powerdns/api-key ]; then
      echo "Generating PowerDNS API key..."
      tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > /var/lib/powerdns/api-key
      chown pdns:pdns /var/lib/powerdns/api-key
      chmod 600 /var/lib/powerdns/api-key
    fi
    
    # Create environment file from API key
    if [ -f /var/lib/powerdns/api-key ]; then
      echo "POWERDNS_API_KEY=$(cat /var/lib/powerdns/api-key)" > /var/lib/powerdns/api-key-env
      chown pdns:pdns /var/lib/powerdns/api-key-env
      chmod 600 /var/lib/powerdns/api-key-env
    fi
  '';

  # PowerDNS Admin - Web interface for managing PowerDNS
  # Disabled native service due to Flask/SQLAlchemy conflicts
  # Running in Docker instead (see systemd service below)
  services.powerdns-admin = {
    enable = false;
    
    # Secret key and salt files (generated on first run)
    secretKeyFile = "/var/lib/powerdns-admin/secret-key";
    saltFile = "/var/lib/powerdns-admin/salt";
    
    # Configuration
    config = ''
      import os
      
      # BASIC APP CONFIG
      SECRET_KEY = os.environ.get('POWERDNS_ADMIN_SECRET_KEY', 'changeme-please-use-something-secure')
      BIND_ADDRESS = '0.0.0.0'
      PORT = 9191
      
      # POWERDNS CONFIG
      PDNS_STATS_URL = 'http://127.0.0.1:8081/'
      PDNS_API_KEY = os.environ.get('POWERDNS_API_KEY', 'changeme')
      PDNS_VERSION = '4.7.0'
      
      # DATABASE CONFIG  
      SQLALCHEMY_DATABASE_URI = 'sqlite:////var/lib/powerdns-admin/powerdns-admin.db'
      SQLALCHEMY_TRACK_MODIFICATIONS = False
      
      # AUTHENTICATION
      SIGNUP_ENABLED = False  # Disabled - admin created via init script
      LOCAL_DB_ENABLED = True
      LDAP_ENABLED = False
      SAML_ENABLED = False
      OIDC_ENABLED = False
      
      # RECORDS CONFIG
      RECORDS_ALLOW_EDIT = ['A', 'AAAA', 'CAA', 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'SRV', 'TXT', 'LOC', 'SSHFP', 'SPF', 'TLSA', 'CAA']
      FORWARD_RECORDS_ALLOW_EDIT = {
        'A': True, 'AAAA': True, 'CAA': True, 'CNAME': True, 
        'MX': True, 'NS': True, 'PTR': True, 'SOA': True, 
        'SRV': True, 'TXT': True, 'LOC': True, 'SSHFP': True, 
        'SPF': True, 'TLSA': True
      }
      REVERSE_RECORDS_ALLOW_EDIT = {
        'A': False, 'AAAA': False, 'CAA': True, 'CNAME': False, 
        'MX': False, 'NS': True, 'PTR': True, 'SOA': True, 
        'SRV': False, 'TXT': True, 'LOC': True, 'SSHFP': True, 
        'SPF': True, 'TLSA': True
      }
      
      # SESSION CONFIG
      SESSION_TYPE = 'sqlalchemy'
    '';
    
    # Listen configuration
    extraArgs = [
      "--bind" "0.0.0.0:9191"
      "--workers" "2"
      "--timeout" "120"
    ];
  };
  
  # Initialize PowerDNS Admin on first run and sync password
  systemd.services.powerdns-admin-init = {
    description = "Initialize PowerDNS Admin database, secrets, and sync admin password";
    wantedBy = [ "multi-user.target" ];
    after = [ "powerdns-admin.service" "pdns.service" "sops-nix.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      # Wait for PowerDNS Admin to be ready
      echo "Waiting for PowerDNS Admin to initialize..."
      for i in {1..30}; do
        if ${pkgs.curl}/bin/curl -s http://localhost:9191/ > /dev/null 2>&1; then
          echo "PowerDNS Admin is ready"
          break
        fi
        sleep 2
      done
      
      # Always sync password (in case it changed)
      FIRST_RUN=false
      if [ ! -f /var/lib/powerdns-admin/.admin-created ]; then
        echo "First run - creating admin user..."
        FIRST_RUN=true
      else
        echo "Syncing admin password with system password..."
      fi
      
      # Create admin user using system credentials
      echo "Using system credentials for PowerDNS Admin..."
      
      # Use system username and password from sops secrets
      ADMIN_USER="${routerConfig.username}"
      ADMIN_EMAIL="${routerConfig.username}@localhost"
      
      # Read password from sops secret (optional - if not found, use default)
      if [ -f /run/secrets/password ]; then
        ADMIN_PASSWORD=$(cat /run/secrets/password)
      else
        echo "Warning: Password secret not found at /run/secrets/password"
        echo "Using default password 'admin' - please change after first login"
        ADMIN_PASSWORD="admin"
      fi
      
      # Wait for database to exist (PowerDNS Admin creates it on first start)
      DB_PATH="/var/lib/powerdns-admin/powerdns-admin.db"
      echo "Waiting for PowerDNS Admin to create database..."
      for i in {1..60}; do
        if [ -f "$DB_PATH" ]; then
          echo "Database found at $DB_PATH"
          break
        fi
        sleep 1
      done
      
      if [ ! -f "$DB_PATH" ]; then
        echo "WARNING: Database not found at $DB_PATH after 60 seconds"
        echo "PowerDNS Admin may not have started successfully"
        echo "Check: systemctl status powerdns-admin.service"
        exit 1
      fi
      
      # Generate password hash (SHA256)
      PASSWORD_HASH=$(echo -n "$ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)
      
      # Read PowerDNS API key
      if [ -f /var/lib/powerdns/api-key ]; then
        PDNS_API_KEY=$(cat /var/lib/powerdns/api-key)
      else
        PDNS_API_KEY='changeme'
      fi
      
      # Use nix-shell to temporarily provide sqlite3 (no permanent install)
      ${pkgs.nix}/bin/nix-shell -p sqlite --run "
        # Check if user exists
        USER_EXISTS=\$(sqlite3 '$DB_PATH' 'SELECT COUNT(*) FROM user WHERE username=\"$ADMIN_USER\";')
        
        if [ \"\$USER_EXISTS\" -gt 0 ]; then
          # User exists - update password
          echo 'Updating password for user: $ADMIN_USER'
          sqlite3 '$DB_PATH' 'UPDATE user SET password=\"$PASSWORD_HASH\" WHERE username=\"$ADMIN_USER\";'
          echo 'Password synchronized with system password'
        else
          # User does not exist - create new
          echo 'Creating new admin user: $ADMIN_USER'
          sqlite3 '$DB_PATH' 'INSERT INTO user (username, password, email, role_id, confirmed) VALUES (\"$ADMIN_USER\", \"$PASSWORD_HASH\", \"$ADMIN_EMAIL\", 1, 1);'
          echo 'Admin user created successfully'
        fi
        
        # Always ensure PowerDNS API settings exist
        sqlite3 '$DB_PATH' 'INSERT OR IGNORE INTO setting (name, value) VALUES (\"pdns_api_url\", \"http://127.0.0.1:8081\"), (\"pdns_api_key\", \"$PDNS_API_KEY\"), (\"pdns_version\", \"4.7.0\");'
      "
      
      echo "Username: $ADMIN_USER"
      echo "Password: synced with system"
      
      # Mark as initialized (only on first run)
      if [ "$FIRST_RUN" = "true" ]; then
        touch /var/lib/powerdns-admin/.admin-created
        echo ""
        echo "=============================================="
        echo "PowerDNS Admin Setup Complete!"
        echo "=============================================="
        echo "Access: http://router-ip:9191"
        echo "Username: ${routerConfig.username}"
        echo "Password: same as system login"
        echo ""
        echo "Use your system credentials to log in."
        echo "=============================================="
      else
        echo ""
        echo "=============================================="
        echo "PowerDNS Admin Password Synced!"
        echo "=============================================="
        echo "Your PowerDNS Admin password has been updated"
        echo "to match your current system password."
        echo "=============================================="
      fi
    '';
  };
  
  # Load secret key into environment for PowerDNS Admin (- prefix makes it optional)
  systemd.services.powerdns-admin.serviceConfig.EnvironmentFile = "-/var/lib/powerdns-admin/secret-key-env";
  
  # Create the files before systemd tries to mount them
  system.activationScripts.powerdns-admin-setup = ''
    # Ensure directory exists
    mkdir -p /var/lib/powerdns-admin
    
    # Generate secret key if it doesn't exist
    if [ ! -f /var/lib/powerdns-admin/secret-key ]; then
      echo "Generating secret key for PowerDNS Admin..."
      tr -dc A-Za-z0-9 </dev/urandom | head -c 64 > /var/lib/powerdns-admin/secret-key
      chmod 600 /var/lib/powerdns-admin/secret-key
    fi
    
    # Generate salt if it doesn't exist
    if [ ! -f /var/lib/powerdns-admin/salt ]; then
      echo "Generating salt for PowerDNS Admin..."
      tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > /var/lib/powerdns-admin/salt
      chmod 600 /var/lib/powerdns-admin/salt
    fi
    
    # Create environment file from secret key
    if [ -f /var/lib/powerdns-admin/secret-key ]; then
      echo "POWERDNS_ADMIN_SECRET_KEY=$(cat /var/lib/powerdns-admin/secret-key)" > /var/lib/powerdns-admin/secret-key-env
      chmod 600 /var/lib/powerdns-admin/secret-key-env
    fi
  '';
  
  # Ensure the service user has access to the files
  systemd.services.powerdns-admin.serviceConfig = {
    # Let systemd handle ownership
    StateDirectory = "powerdns-admin";
    StateDirectoryMode = "0750";
  };

  # Enable Docker for PowerDNS Admin
  virtualisation.docker.enable = true;
  
  # Docker Compose configuration for PowerDNS Admin
  environment.etc."powerdns-admin/docker-compose.yml".text = ''
    version: '3.8'
    
    services:
      powerdns-admin:
        image: ngoduykhanh/powerdns-admin:latest
        container_name: powerdns-admin
        restart: unless-stopped
        network_mode: host
        environment:
          - SECRET_KEY=changeme-on-first-run
          - BIND_ADDRESS=0.0.0.0
          - PORT=9191
          - SQLA_DB_USER=powerdns
          - SQLA_DB_NAME=powerdnsadmin
        volumes:
          - /var/lib/powerdns-admin:/data
        depends_on:
          - pdns
        healthcheck:
          test: ["CMD", "curl", "-f", "http://localhost:9191/"]
          interval: 30s
          timeout: 10s
          retries: 3
          start_period: 40s
  '';
  
  # Systemd service to manage PowerDNS Admin via docker-compose
  systemd.services.powerdns-admin-compose = {
    description = "PowerDNS Admin (Docker Compose)";
    after = [ "network.target" "docker.service" "pdns.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/etc/powerdns-admin";
    };
    
    path = [ pkgs.docker-compose ];
    
    script = ''
      # Ensure data directory exists
      mkdir -p /var/lib/powerdns-admin
      
      # Start PowerDNS Admin
      ${pkgs.docker-compose}/bin/docker-compose up -d
      
      # Wait for service to be ready
      echo "Waiting for PowerDNS Admin to start..."
      for i in {1..30}; do
        if ${pkgs.curl}/bin/curl -sf http://localhost:9191/ > /dev/null 2>&1; then
          echo "PowerDNS Admin is ready!"
          echo "Access at: http://your-router-ip:9191"
          echo "Default credentials: admin / admin"
          echo "IMPORTANT: Change password on first login!"
          break
        fi
        sleep 2
      done
    '';
    
    preStop = "${pkgs.docker-compose}/bin/docker-compose down";
    
    reload = "${pkgs.docker-compose}/bin/docker-compose restart";
  };

  # Firewall rules for PowerDNS services
  networking.firewall.allowedUDPPorts = mkAfter [ 53 ];
  networking.firewall.allowedTCPPorts = mkAfter [ 53 8081 9191 ];  # 53=DNS, 8081=PowerDNS API, 9191=PowerDNS Admin
}

