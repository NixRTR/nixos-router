# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, lib, ... }:

let
  # Import router configuration variables
  routerConfig = import ./router-config.nix;
  pppoeEnabled = routerConfig.wan.type == "pppoe";
in

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./router.nix
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
      bridge.interfaces = routerConfig.lan.interfaces;
      ipv4 = {
        address = routerConfig.lan.ip;
        prefixLength = routerConfig.lan.prefix;
      };
      ipv6 = {
        enable = false;
      };
    };
    firewall = {
      allowedTCPPorts = [ 80 443 22000 4242];
      allowedUDPPorts = [ 80 443 22000 4242];
    };
    dnsmasq = {
      rangeStart = routerConfig.dhcp.start;
      rangeEnd = routerConfig.dhcp.end;
    };
    portForwards = [
      {
        proto = "both";
        externalPort = 80;
        destination = routerConfig.lan.ip;
        destinationPort = 80;
      }
      {
        proto = "both";
        externalPort = 443;
        destination = routerConfig.lan.ip;
        destinationPort = 443;
      }
      {
        proto = "both";
        externalPort = 22000;
        destination = routerConfig.lan.ip;
        destinationPort = 22000;
      }
      {
        proto = "both";
        externalPort = 4242;
        destination = routerConfig.lan.ip;
        destinationPort = 4242;
      }
    ];
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
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
  ];


  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  system.stateVersion = "25.05"; # Did you read the comment?

}
