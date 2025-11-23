{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  pppoeEnabled = routerConfig.wan.type == "pppoe";
  dyndnsEnabled = routerConfig.dyndns.enable or false;
  appriseEnabled = routerConfig.apprise.enable or false;
  appriseServices = routerConfig.apprise.services or {};
  
  # Check if individual apprise services are enabled
  emailEnabled = appriseEnabled && (appriseServices.email.enable or false);
  homeAssistantEnabled = appriseEnabled && (appriseServices.homeAssistant.enable or false);
  discordEnabled = appriseEnabled && (appriseServices.discord.enable or false);
  slackEnabled = appriseEnabled && (appriseServices.slack.enable or false);
  telegramEnabled = appriseEnabled && (appriseServices.telegram.enable or false);
  ntfyEnabled = appriseEnabled && (appriseServices.ntfy.enable or false);
  ntfyAuthEnabled = ntfyEnabled && (appriseServices.ntfy.username or null) != null;

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
    # Apprise API secrets (conditional on service enablement)
    # Owner is router-webui since Apprise is integrated into the WebUI backend
    // optionalAttrs emailEnabled {
      apprise-email-password = {
        owner = "router-webui";
        mode = "0400";
      };
    }
    // optionalAttrs homeAssistantEnabled {
      apprise-homeassistant-token = {
        owner = "router-webui";
        mode = "0400";
      };
    }
    // optionalAttrs discordEnabled {
      apprise-discord-webhook-id = {
        owner = "router-webui";
        mode = "0400";
      };
      apprise-discord-webhook-token = {
        owner = "router-webui";
        mode = "0400";
      };
    }
    // optionalAttrs slackEnabled {
      apprise-slack-token-a = {
        owner = "router-webui";
        mode = "0400";
      };
      apprise-slack-token-b = {
        owner = "router-webui";
        mode = "0400";
      };
      apprise-slack-token-c = {
        owner = "router-webui";
        mode = "0400";
      };
    }
    // optionalAttrs telegramEnabled {
      apprise-telegram-bot-token = {
        owner = "router-webui";
        mode = "0400";
      };
    }
    // optionalAttrs ntfyAuthEnabled {
      apprise-ntfy-username = {
        owner = "router-webui";
        mode = "0400";
      };
      apprise-ntfy-password = {
        owner = "router-webui";
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

