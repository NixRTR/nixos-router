# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./router.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.

  router = {
    enable = true;
    wan = {
       type = "dhcp";
       interface = "eno1";
#      type = "pppoe";
#      interface = "eno1";
#      pppoe = {
#        passwordFile = config.sops.secrets."pppoe-password".path;
#        user = config.sops.secrets."pppoe-username".path;
#        service = null;
#        ipv6 = false;
#      };
    };
    lan = {
      bridge.interfaces = [ "enp4s0" "enp5s0" "enp6s0" "enp7s0" ];
      ipv4 = {
        address = "192.168.4.1";
        prefixLength = 24;
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
      rangeStart = "192.168.4.100";
      rangeEnd = "192.168.4.200";
    };
    portForwards = [
      {
        proto = "both";
        externalPort = 80;
        destination = "192.168.2.33";
        destinationPort = 80;
      }
      {
        proto = "both";
        externalPort = 443;
        destination = "192.168.2.33";
        destinationPort = 443;
      }
      {
        proto = "both";
        externalPort = 22000;
        destination = "192.168.2.33";
        destinationPort = 22000;
      }
      {
        proto = "both";
        externalPort = 4242;
        destination = "192.168.2.31";
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
    secrets = {
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
      "password" = {
        path = "/run/secrets/password";
        owner = "root";
        group = "root";
        mode = "0400";
        neededForUsers = true;
      };
    };
  };

  # Set your time zone.
  time.timeZone = "America/Anchorage";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.routeradmin = {
    isNormalUser = true;
    description = "Router administrator";
    extraGroups = [ "wheel" ];
    packages = with pkgs; [];
    hashedPasswordFile = config.sops.secrets."password".path;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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
