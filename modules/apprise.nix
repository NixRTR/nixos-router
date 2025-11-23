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
    enable = mkEnableOption "Apprise API notification service";
    
    port = mkOption {
      type = types.port;
      default = 8001;
      description = "Internal port for apprise-api (separate from webui)";
    };
    
    configDir = mkOption {
      type = types.str;
      default = "/var/lib/apprise/config";
      description = "Configuration directory path";
    };
    
    attachmentsDir = mkOption {
      type = types.nullOr types.str;
      default = "/var/lib/apprise/attachments";
      description = "Attachments directory path (optional)";
    };
    
    attachSize = mkOption {
      type = types.int;
      default = 0;
      description = "Maximum attachment size in MB (0 disables attachments)";
    };
  };
  
  config = mkIf cfg.enable {
    # Enable Docker
    virtualisation.docker.enable = true;
    
    # Create system user for the service
    users.users.apprise = {
      isSystemUser = true;
      group = "apprise";
      description = "Apprise API service user";
      extraGroups = [ "docker" ];
    };
    
    users.groups.apprise = {};
    
    # Create state directories
    systemd.tmpfiles.rules = [
      "d /var/lib/apprise 0750 apprise apprise -"
      "d ${cfg.configDir} 0750 apprise apprise -"
    ] ++ (optional (cfg.attachmentsDir != null) "d ${cfg.attachmentsDir} 0750 apprise apprise -");
    
    # Generate apprise configuration file from router-config.nix
    # Apprise-API expects a file with one service URL per line
    # Use sops template to ensure placeholders are replaced at runtime
    sops.templates."apprise-config" = {
      content = generateAppriseConfig appriseServices;
      owner = "apprise";
      group = "apprise";
      mode = "0600";
    };
    
    # Service to copy config to apprise config directory
    systemd.services.apprise-api-config-init = {
      description = "Initialize Apprise API configuration";
      wantedBy = [ "apprise-api.service" ];
      before = [ "apprise-api.service" ];
      after = [ "local-fs.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "apprise";
        Group = "apprise";
      };
      
      script = ''
        mkdir -p ${cfg.configDir}
        cp ${config.sops.templates."apprise-config".path} ${cfg.configDir}/apprise
        chown apprise:apprise ${cfg.configDir}/apprise
        chmod 600 ${cfg.configDir}/apprise
        
        # Create location-override.conf for Apprise's internal nginx
        # This tells Apprise's nginx to handle being behind a reverse proxy
        cat > ${cfg.configDir}/location-override.conf <<'EOF'
        # Location override for reverse proxy support
        # This file is mounted into the Apprise API container
        # to configure its internal nginx for reverse proxy compatibility
        
        # Ensure proper headers are passed through
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        EOF
        chown apprise:apprise ${cfg.configDir}/location-override.conf
        chmod 644 ${cfg.configDir}/location-override.conf
      '';
    };
    
    # Apprise API service using Docker
    systemd.services.apprise-api = {
      description = "Apprise API notification service (Docker)";
      after = [ "network.target" "docker.service" "apprise-api-config-init.service" ];
      wants = [ "docker.service" "apprise-api-config-init.service" ];
      requires = [ "docker.service" "apprise-api-config-init.service" ];
      wantedBy = [ "multi-user.target" ];
      
      path = with pkgs; [ docker ];
      
      serviceConfig = {
        Type = "simple";
        User = "apprise";
        Group = "apprise";
        Restart = "always";
        RestartSec = "10s";
      };
      
      preStart = ''
        # Pull the image if it doesn't exist
        ${pkgs.docker}/bin/docker pull lscr.io/linuxserver/apprise-api:latest || true
      '';
      
      script = let
        attachSizeEnv = if cfg.attachSize > 0 then "--env APPRISE_ATTACH_SIZE=${toString cfg.attachSize}" else "";
        attachmentsMount = if cfg.attachmentsDir != null then "--volume ${cfg.attachmentsDir}:/apprise/attachments" else "";
        locationOverrideMount = "--volume ${cfg.configDir}/location-override.conf:/etc/nginx/location-override.conf:ro";
      in ''
        # Stop and remove existing container if it exists
        ${pkgs.docker}/bin/docker stop apprise-api 2>/dev/null || true
        ${pkgs.docker}/bin/docker rm apprise-api 2>/dev/null || true
        
        # Run the container in foreground (no --detach) so systemd can manage it
        exec ${pkgs.docker}/bin/docker run \
          --name apprise-api \
          --rm \
          --publish 127.0.0.1:${toString cfg.port}:8000 \
          --volume ${cfg.configDir}:/config \
          ${attachmentsMount} \
          ${locationOverrideMount} \
          --env PUID=$(id -u apprise) \
          --env PGID=$(id -g apprise) \
          ${attachSizeEnv} \
          lscr.io/linuxserver/apprise-api:latest
      '';
    };
    
    # Add nginx location for /apprise/
    # This extends the existing nginx virtual host (webui or creates new one)
    # Note: proxyPass with trailing slash automatically strips /apprise/ prefix
    services.nginx.virtualHosts."router-webui" = {
      locations."/apprise/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/";
        proxyWebsockets = true;
        extraConfig = ''
          # Standard proxy headers
          proxy_set_header Host $host:$server_port;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host:$server_port;
          
          # Rewrite redirects to include /apprise prefix
          proxy_redirect http://$host:$server_port/ http://$host:$server_port/apprise/;
          proxy_redirect http://$host/ http://$host:$server_port/apprise/;
          
          # Rewrite URLs in response body to include /apprise prefix
          # This fixes links, API calls, and other absolute URLs generated by Apprise
          sub_filter 'href="/' 'href="/apprise/';
          sub_filter "href='/" "href='/apprise/";
          sub_filter 'src="/' 'src="/apprise/';
          sub_filter "src='/" "src='/apprise/";
          sub_filter 'action="/' 'action="/apprise/';
          sub_filter "action='/" "action='/apprise/";
          sub_filter '"/api/' '"/apprise/api/';
          sub_filter "'/api/" "'/apprise/api/";
          sub_filter '"/static/' '"/apprise/static/';
          sub_filter "'/static/" "'/apprise/static/";
          sub_filter_once off;
          sub_filter_types text/html application/json text/javascript application/x-javascript;
        '';
      };
    };
  };
}
