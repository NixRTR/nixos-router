{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.apprise-api;
  routerConfig = import ../router-config.nix;
  
  # Build custom apprise package pinned to version 1.9.4 (required by apprise-api)
  # nixpkgs has 1.9.5, but apprise-api requires exactly 1.9.4
  apprise-1-9-4 = pkgs.python311Packages.buildPythonPackage rec {
    pname = "apprise";
    version = "1.9.4";
    
    src = pkgs.python311Packages.fetchPypi {
      inherit pname version;
      sha256 = "126951n9lnlqrw5lbsvs9xs7jzg33bqqxm7cfnqag2csw6p24ca8";
    };
    
    # Apprise uses setuptools, not pyproject
    format = "setuptools";
    
    propagatedBuildInputs = with pkgs.python311Packages; [
      requests
      pyyaml
      click
      markdown
      # Optional but commonly used dependencies
      beautifulsoup4  # For HTML parsing in some notification services
      cryptography    # For encrypted connections
    ];
    
    nativeBuildInputs = with pkgs.python311Packages; [
      setuptools
      wheel
    ];
    
    doCheck = false;
    
    meta = with lib; {
      description = "Push Notifications that work with just about every platform";
      homepage = "https://github.com/caronc/apprise";
      license = licenses.bsd2;
    };
  };
  
  # Build custom apprise-api package from GitHub
  # apprise-api is not available in nixpkgs, so we build it ourselves
  apprise-api-package = pkgs.python311Packages.buildPythonPackage rec {
    pname = "apprise-api";
    version = "1.2.1";
    
    src = pkgs.fetchFromGitHub {
      owner = "caronc";
      repo = "apprise-api";
      rev = "v${version}";
      sha256 = "sha256-duGwg/zBtbdPv6fpNubNJ6yCqiv1JI9kYLIf799LzlI=";
    };
    
    format = "pyproject";
    
    propagatedBuildInputs = with pkgs.python311Packages; [
      apprise-1-9-4  # Use our custom apprise 1.9.4 package
      flask
      gunicorn
      pyyaml
      click
      requests
      # Optional dependencies that apprise-api supports
      django
      gevent
      paho-mqtt
      gntp
      django-prometheus
    ];
    
    # Apprise-api uses pyproject.toml, so we need to ensure it's properly built
    nativeBuildInputs = with pkgs.python311Packages; [
      setuptools
      wheel
      pip
    ];
    
    doCheck = false; # Skip tests for now
    
    meta = with lib; {
      description = "A lightweight REST framework that wraps the Apprise Notification Library";
      homepage = "https://github.com/caronc/apprise-api";
      license = licenses.mit;
    };
  };
  
  # Python environment with apprise-api and dependencies
  # Note: apprise-1-9-4 is included via apprise-api-package's propagatedBuildInputs
  pythonEnv = pkgs.python311.withPackages (ps: with ps; [
    apprise-api-package
    flask
    gunicorn
    pyyaml
    click
    requests
  ]);

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
    # Create system user for the service
    users.users.apprise = {
      isSystemUser = true;
      group = "apprise";
      description = "Apprise API service user";
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
      '';
    };
    
    # Apprise API service
    systemd.services.apprise-api = {
      description = "Apprise API notification service";
      after = [ "network.target" "apprise-api-config-init.service" ];
      wants = [ "apprise-api-config-init.service" ];
      requires = [ "apprise-api-config-init.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        APPRISE_CONFIG_DIR = cfg.configDir;
        APPRISE_ATTACH_SIZE = toString cfg.attachSize;
      } // (optionalAttrs (cfg.attachmentsDir != null) {
        APPRISE_ATTACHMENTS = cfg.attachmentsDir;
      });
      
      serviceConfig = {
        Type = "simple";
        User = "apprise";
        Group = "apprise";
        WorkingDirectory = "/var/lib/apprise";
        ExecStart = "${pythonEnv}/bin/gunicorn --bind 127.0.0.1:${toString cfg.port} --workers 2 apprise_api:app";
        Restart = "always";
        RestartSec = "10s";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/apprise" ];
        ReadOnlyPaths = [ "/proc" "/sys" ];
      };
    };
    
    # Add nginx location for /apprise/
    # This extends the existing nginx virtual host (webui or creates new one)
    services.nginx.virtualHosts."router-webui" = {
      locations."/apprise/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/";
        proxyWebsockets = true;
        extraConfig = ''
          rewrite ^/apprise(/.*)$ $1 break;
          proxy_set_header Host $host:$server_port;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host:$server_port;
        '';
      };
    };
  };
}

