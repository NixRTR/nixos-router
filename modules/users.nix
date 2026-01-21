{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;

in

{
  # User management configuration
  users.users.${routerConfig.username} = {
    isNormalUser = true;
    description = "Router administrator";
    extraGroups = [ "wheel" "networkmanager" ];
    
    # Password from sops secret (pre-hashed with mkpasswd -m sha-512)
    # Only set if the secret exists (allows builds without secrets)
    hashedPasswordFile = mkIf (config.sops.secrets ? "password-hash") 
      config.sops.secrets."password-hash".path;
    
    openssh.authorizedKeys.keys = routerConfig.sshKeys or [];
  };

  # Sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Auto-login on the primary console
  services.getty.autologinUser = routerConfig.username;
}

