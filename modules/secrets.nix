{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  pppoeEnabled = routerConfig.wan.type == "pppoe";
  dyndnsEnabled = routerConfig.dyndns.enable or false;
  appriseEnabled = routerConfig.apprise.enable or false;

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
    }
    # Apprise API URLs (conditional on apprise enablement)
    # Contains newline-separated list of apprise service URLs
    # Format: description|url (one per line)
    # Example URLs:
    #   mailto://user:pass@smtp:port?to=recipient
    #   tgram://bot-token/chat-id
    #   discord://webhook-id/webhook-token
    #   ntfy://topic or ntfy://user:pass@server/topic
    // optionalAttrs appriseEnabled {
      apprise-urls = {
        owner = "router-webui";
        mode = "0400";
        # No format specified - sops-nix will handle multiline YAML strings automatically
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

