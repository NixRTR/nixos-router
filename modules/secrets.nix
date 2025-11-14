{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  pppoeEnabled = routerConfig.wan.type == "pppoe";
  dyndnsEnabled = routerConfig.dyndns.enable or false;

in

{
  # Sops-nix secrets management
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    # Define secrets
    secrets = {
      # User password hash (hashed with mkpasswd -m sha-512)
      password-hash = {
        neededForUsers = true;
      };
    } 
    # PPPoE secrets (conditional)
    // optionalAttrs pppoeEnabled {
      pppoe-username = {
        owner = "root";
        mode = "0400";
      };
      pppoe-password = {
        owner = "root";
        mode = "0400";
      };
    }
    # Dynamic DNS secrets (conditional)
    // optionalAttrs dyndnsEnabled {
      linode-api-token = {
        owner = "root";
        mode = "0400";
      };
    };
    
    # Templates - generate files with secrets substituted
    templates = optionalAttrs pppoeEnabled {
      # PPPoE peer configuration with credentials
      "pppoe-peer.conf" = {
        content = ''
          user ${config.sops.placeholder."pppoe-username"}
          password ${config.sops.placeholder."pppoe-password"}
        '';
        owner = "root";
        mode = "0400";
      };
    };
  };
}

