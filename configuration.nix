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
      ./dnclient.nix
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

  services.blocky = {
    enable = true;
    settings = {
      ports.dns = 
        # Listen on all bridge IPs plus localhost
        (map (ip: "${ip}:53") bridgeIPs) ++ [ "127.0.0.1:53" ];
      upstreams.groups.default = [
        "tcp+udp:1.1.1.1"
        "tcp+udp:8.8.8.8"
        "tcp+udp:9.9.9.9"  # Quad9 (privacy-focused)
      ];
      bootstrapDns = [
        "tcp+udp:1.1.1.1"
        "tcp+udp:8.8.8.8"
      ];
      caching = {
        minTime = "5m";
        maxTime = "2h";  # Increased from 30m for better performance
        prefetching = true;  # Refresh popular entries before expiry
        prefetchExpires = "2h";
        prefetchThreshold = 5;  # Prefetch if queried 5+ times
      };
      # Performance optimizations
      clientLookup = {
        upstream = "tcp+udp:1.1.1.1";
      };
      # Connection pooling for upstream queries
      upstreams.timeout = "2s";
      log.level = "info";
    };
  };

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
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 53 ];

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
