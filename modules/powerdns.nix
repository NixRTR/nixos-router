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
    dns.address = 
      # Listen on all bridge IPs plus localhost
      (map (ip: "${ip}:53") bridgeIPs) ++ [ "127.0.0.1:53" ];
    dns.allowFrom = [
      "127.0.0.0/8"
      "192.168.0.0/16"
      "10.0.0.0/8"
      "172.16.0.0/12"
    ];
    # Forward to upstream DNS servers
    forwardZones = {
      "." = "1.1.1.1;8.8.8.8;9.9.9.9";
    };
    settings = {
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

  # PowerDNS Admin - Web interface for managing PowerDNS
  services.powerdns-admin = {
    enable = true;
    
    # Secret key file (generated on first run)
    secretKeyFile = "/var/lib/powerdns-admin/secret-key";
    
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
    after = [ "powerdns-admin.service" "sops-nix.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      # Wait for PowerDNS Admin to be ready
      echo "Waiting for PowerDNS Admin to initialize..."
      for i in {1..30}; do
        if curl -s http://localhost:9191/ > /dev/null 2>&1; then
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
      
      # Read password from sops secret
      if [ -f /run/secrets/password ]; then
        ADMIN_PASSWORD=$(cat /run/secrets/password)
      else
        echo "ERROR: Password secret not found at /run/secrets/password"
        exit 1
      fi
      
      # Wait for database to exist
      DB_PATH="/var/lib/powerdns-admin/powerdns-admin.db"
      for i in {1..30}; do
        if [ -f "$DB_PATH" ]; then
          break
        fi
        sleep 1
      done
      
      if [ ! -f "$DB_PATH" ]; then
        echo "ERROR: Database not found at $DB_PATH"
        exit 1
      fi
      
      # Generate password hash (SHA256)
      PASSWORD_HASH=$(echo -n "$ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)
      
      # Use nix-shell to temporarily provide sqlite3 (no permanent install)
      ${pkgs.nix}/bin/nix-shell -p sqlite --run "
        # Check if user exists
        USER_EXISTS=\$(sqlite3 '$DB_PATH' \"SELECT COUNT(*) FROM user WHERE username='$ADMIN_USER';\")
        
        if [ \"\$USER_EXISTS\" -gt 0 ]; then
          # User exists - update password
          echo 'Updating password for user: $ADMIN_USER'
          sqlite3 '$DB_PATH' \"UPDATE user SET password='$PASSWORD_HASH' WHERE username='$ADMIN_USER';\"
          echo 'Password synchronized with system password'
        else
          # User doesn't exist - create new
          echo 'Creating new admin user: $ADMIN_USER'
          sqlite3 '$DB_PATH' \"INSERT INTO user (username, password, email, role_id, confirmed) VALUES ('$ADMIN_USER', '$PASSWORD_HASH', '$ADMIN_EMAIL', 1, 1);\"
          echo 'Admin user created successfully'
        fi
        
        # Always ensure PowerDNS API settings exist
        sqlite3 '$DB_PATH' \"INSERT OR IGNORE INTO setting (name, value) VALUES ('pdns_api_url', 'http://127.0.0.1:8081'), ('pdns_api_key', 'changeme'), ('pdns_version', '4.7.0');\"
      "
      
      echo "Username: $ADMIN_USER"
      echo "Password: (synced with system)"
      
      # Mark as initialized (only on first run)
      if [ "$FIRST_RUN" = "true" ]; then
        touch /var/lib/powerdns-admin/.admin-created
        echo ""
        echo "=============================================="
        echo "PowerDNS Admin Setup Complete!"
        echo "=============================================="
        echo "Access: http://router-ip:9191"
        echo "Username: ${routerConfig.username}"
        echo "Password: (same as system login)"
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
  
  # Load secret key into environment for PowerDNS Admin
  systemd.services.powerdns-admin.serviceConfig.EnvironmentFile = "/var/lib/powerdns-admin/secret-key-env";
  
  systemd.services.powerdns-admin.preStart = ''
    # Ensure directory exists with correct ownership
    mkdir -p /var/lib/powerdns-admin
    chown powerdns-admin:powerdns-admin /var/lib/powerdns-admin
    
    # Generate secret key if it doesn't exist
    if [ ! -f /var/lib/powerdns-admin/secret-key ]; then
      echo "Generating secret key for PowerDNS Admin..."
      tr -dc A-Za-z0-9 </dev/urandom | head -c 64 > /var/lib/powerdns-admin/secret-key
      chown powerdns-admin:powerdns-admin /var/lib/powerdns-admin/secret-key
      chmod 600 /var/lib/powerdns-admin/secret-key
    fi
    
    # Create environment file from secret key
    if [ -f /var/lib/powerdns-admin/secret-key ]; then
      echo "POWERDNS_ADMIN_SECRET_KEY=$(cat /var/lib/powerdns-admin/secret-key)" > /var/lib/powerdns-admin/secret-key-env
      chmod 600 /var/lib/powerdns-admin/secret-key-env
    fi
  '';

  # Firewall rules for PowerDNS services
  networking.firewall.allowedUDPPorts = mkAfter [ 53 ];
  networking.firewall.allowedTCPPorts = mkAfter [ 53 8081 9191 ];  # 53=DNS, 8081=PowerDNS API, 9191=PowerDNS Admin
}

