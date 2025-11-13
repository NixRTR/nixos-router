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
    # Password is set via activation script from sops secrets
    openssh.authorizedKeys.keys = routerConfig.sshKeys or [];
  };

  # Sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

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

  # Auto-login on the primary console
  services.getty.autologinUser = routerConfig.username;
}

