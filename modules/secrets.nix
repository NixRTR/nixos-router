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
      # User password (always required)
      password = {
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
  };
}

