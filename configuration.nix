# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, lib, ... }:

let
  # Import router configuration variables
  routerConfig = import ./router-config.nix;
  pppoeEnabled = routerConfig.wan.type == "pppoe";
  dyndnsEnabled = routerConfig.dyndns.enable or false;
  
  # Extract bridge information from config
  bridges = routerConfig.lan.bridges;
  bridgeNames = map (b: b.name) bridges;
  bridgeIPs = map (b: b.ipv4.address) bridges;

  # Helper function to convert lease time string to seconds
  leaseToSeconds = lease:
    let
      numeric = builtins.match "^[0-9]+$" lease;
      unitMatch = builtins.match "^([0-9]+)([smhd])$" lease;
      multiplier = unit:
        if unit == "s" then 1
        else if unit == "m" then 60
        else if unit == "h" then 3600
        else if unit == "d" then 86400
        else 1;
    in if lease == null then 86400
       else if numeric != null then lib.toInt lease
       else if unitMatch != null then
         let
           num = lib.toInt (builtins.elemAt unitMatch 0);
           unit = builtins.elemAt unitMatch 1;
         in num * multiplier unit
       else 86400;

  # Build DHCP subnets from config
  dhcpSubnets = [
    # HOMELAB network
    {
      id = 1;
      subnet = "${routerConfig.dhcp.homelab.network}/${toString routerConfig.dhcp.homelab.prefix}";
      pools = [{
        pool = "${routerConfig.dhcp.homelab.start} - ${routerConfig.dhcp.homelab.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.dhcp.homelab.gateway; }
        { name = "domain-name-servers"; data = routerConfig.dhcp.homelab.dns; }
      ];
      valid-lifetime = leaseToSeconds routerConfig.dhcp.homelab.leaseTime;
    }
    # LAN network
    {
      id = 2;
      subnet = "${routerConfig.dhcp.lan.network}/${toString routerConfig.dhcp.lan.prefix}";
      pools = [{
        pool = "${routerConfig.dhcp.lan.start} - ${routerConfig.dhcp.lan.end}";
      }];
      option-data = [
        { name = "routers"; data = routerConfig.dhcp.lan.gateway; }
        { name = "domain-name-servers"; data = routerConfig.dhcp.lan.dns; }
      ];
      valid-lifetime = leaseToSeconds routerConfig.dhcp.lan.leaseTime;
    }
  ];
in

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./router.nix
      ./dashboard.nix
      ./linode-dyndns.nix
    ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = routerConfig.hostname; # Define your hostname.

  router = {
    enable = true;
    wan = {
       type = routerConfig.wan.type;
       interface = routerConfig.wan.interface;
    } // (if pppoeEnabled then {
      pppoe = {
        passwordFile = config.sops.secrets."pppoe-password".path;
        user = config.sops.secrets."pppoe-username".path;
        service = null;
        ipv6 = false;
      };
    } else {});
    lan = {
      # Use new multi-bridge configuration
      bridges = routerConfig.lan.bridges;
      isolation = routerConfig.lan.isolation or true;
    };
    firewall = {
      allowedTCPPorts = [ 80 443 22000 4242];
      allowedUDPPorts = [ 80 443 22000 4242];
    };
    portForwards = routerConfig.portForwards or [];
    dashboard.enable = true;
  };

  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    secrets =
      {
      "password" = {
        path = "/run/secrets/password";
        owner = "root";
        group = "root";
        mode = "0400";
        neededForUsers = true;
      };
      }
      // lib.optionalAttrs pppoeEnabled {
        "pppoe-password" = {
          path = "/run/secrets/pppoe-password";
          owner = "root";
          group = "root";
          mode = "0400";
        };
        "pppoe-username" = {
          path = "/run/secrets/pppoe-username";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      }
      // lib.optionalAttrs dyndnsEnabled {
        "linode-api-token" = {
          path = "/run/secrets/linode-api-token";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      };
  };

  # Set your time zone.
  time.timeZone = routerConfig.timezone;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.${routerConfig.username} = {
    isNormalUser = true;
    description = routerConfig.username;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [];
    # Password will be set by activation script
  };

  # Enable passwordless sudo for routeradmin
  security.sudo.extraRules = [
    {
      users = [ routerConfig.username ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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
        if ${pkgs.nix}/bin/nix-shell -p curl --run "curl -s http://localhost:9191/" > /dev/null 2>&1; then
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

  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config = {
        # Listen on all bridge interfaces
        interfaces = bridgeNames;
      };
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };
      # Use per-subnet option-data instead of global
      # Each subnet defines its own gateway and DNS
      subnet4 = dhcpSubnets;
    };
  };

  networking.firewall.allowedUDPPorts = lib.mkAfter [ 53 67 ];
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 53 8081 9191 ];  # 53=DNS, 8081=PowerDNS API, 9191=PowerDNS Admin

  # Set user password from encrypted secret
  system.activationScripts.setUserPassword = {
    text = ''
      # Decrypt and hash the user password
      if [ -f /run/secrets/password ]; then
        PLAIN_PASS=$(cat /run/secrets/password)
        # Hash the password using mkpasswd or openssl
        if command -v mkpasswd >/dev/null 2>&1; then
          HASHED_PASS=$(mkpasswd -m sha-512 "$PLAIN_PASS" 2>/dev/null || mkpasswd -5 "$PLAIN_PASS" 2>/dev/null || echo "")
        else
          HASHED_PASS=$(echo -n "$PLAIN_PASS" | openssl passwd -6 -stdin 2>/dev/null || echo "")
        fi

        if [ -n "$HASHED_PASS" ]; then
          # Set the password for the user
          echo "${routerConfig.username}:$HASHED_PASS" | chpasswd -e
          echo "User password set successfully"
        else
          echo "Warning: Failed to hash password, user may need to set password manually"
        fi
      else
        echo "Warning: Password secret not found, user may need to set password manually"
      fi
    '';
    deps = [];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    speedtest-cli
  ];


  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Auto-login on the primary console
  services.getty.autologinUser = routerConfig.username;

  system.stateVersion = "25.05"; # Did you read the comment?

}
