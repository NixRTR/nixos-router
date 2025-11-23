{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.apprise-api;
  routerConfig = import ../router-config.nix;

  # Generate apprise service URLs from router-config.nix
  # Format: one service URL per line
  generateAppriseConfig = services:
    let
      # Email: mailto://user:pass@smtp:port?to=recipient
      emailUrl = if services.email.enable or false then
        let
          fromParam = if (services.email.from or null) != null then
            "&from=${services.email.from}"
          else "";
        in
        "mailto://${services.email.username}:${config.sops.placeholder."apprise-email-password"}@${services.email.smtpHost}:${toString (services.email.smtpPort or 587)}?to=${services.email.to}${fromParam}"
      else "";
      
      # Home Assistant: hassio://token@host:port
      homeAssistantUrl = if services.homeAssistant.enable or false then
        let
          host = services.homeAssistant.host;
          port = toString (services.homeAssistant.port or 8123);
        in
        "hassio://${config.sops.placeholder."apprise-homeassistant-token"}@${host}:${port}"
      else "";
      
      # Discord: discord://webhook_id/webhook_token
      discordUrl = if services.discord.enable or false then
        "discord://${config.sops.placeholder."apprise-discord-webhook-id"}/${config.sops.placeholder."apprise-discord-webhook-token"}"
      else "";
      
      # Slack: slack://tokenA/tokenB/tokenC
      slackUrl = if services.slack.enable or false then
        "slack://${config.sops.placeholder."apprise-slack-token-a"}/${config.sops.placeholder."apprise-slack-token-b"}/${config.sops.placeholder."apprise-slack-token-c"}"
      else "";
      
      # Telegram: tgram://bot_token/chat_id
      telegramUrl = if services.telegram.enable or false then
        "tgram://${config.sops.placeholder."apprise-telegram-bot-token"}/${services.telegram.chatId or ""}"
      else "";
      
      # ntfy: ntfy://topic or ntfy://user:pass@server/topic
      ntfyUrl = if services.ntfy.enable or false then
        let
          server = services.ntfy.server or "ntfy.sh";
          topic = services.ntfy.topic or "";
          auth = if (services.ntfy.username or null) != null then
            "${config.sops.placeholder."apprise-ntfy-username"}:${config.sops.placeholder."apprise-ntfy-password"}@"
          else "";
        in
        "ntfy://${auth}${server}/${topic}"
      else "";
      
      urls = filter (x: x != "") [
        emailUrl
        homeAssistantUrl
        discordUrl
        slackUrl
        telegramUrl
        ntfyUrl
      ];
    in
    concatStringsSep "\n" urls;

  appriseServices = routerConfig.apprise.services or {};

in

{
  options.services.apprise-api = {
    enable = mkEnableOption "Apprise notification service (integrated with WebUI backend)";
    
    configDir = mkOption {
      type = types.str;
      default = "/var/lib/apprise/config";
      description = "Configuration directory path";
    };
  };
  
  config = mkIf cfg.enable {
    # Create state directories
    systemd.tmpfiles.rules = [
      "d /var/lib/apprise 0750 router-webui router-webui -"
      "d ${cfg.configDir} 0750 router-webui router-webui -"
    ];
    
    # Generate apprise configuration file from router-config.nix
    # Apprise expects a file with one service URL per line
    # Use sops template to ensure placeholders are replaced at runtime
    sops.templates."apprise-config" = {
      content = generateAppriseConfig appriseServices;
      owner = "router-webui";
      group = "router-webui";
      mode = "0600";
    };
    
    # Service to copy config to apprise config directory
    # This runs before router-webui-backend starts
    systemd.services.apprise-api-config-init = {
      description = "Initialize Apprise configuration";
      wantedBy = [ "router-webui-backend.service" ];
      before = [ "router-webui-backend.service" ];
      after = [ "local-fs.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "router-webui";
        Group = "router-webui";
      };
      
      script = ''
        mkdir -p ${cfg.configDir}
        cp ${config.sops.templates."apprise-config".path} ${cfg.configDir}/apprise
        chown router-webui:router-webui ${cfg.configDir}/apprise
        chmod 600 ${cfg.configDir}/apprise
      '';
    };
  };
}
