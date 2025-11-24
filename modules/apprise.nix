{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.apprise-api;

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
    
    # Note: apprise-urls secret is defined in modules/secrets.nix
    
    # Service to copy config to apprise config directory
    # This runs before router-webui-backend starts
    systemd.services.apprise-config-init = {
      description = "Initialize Apprise configuration";
      wantedBy = [ "router-webui-backend.service" ];
      before = [ "router-webui-backend.service" ];
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        # Ensure directories exist with correct permissions
        mkdir -p ${cfg.configDir}
        chown router-webui:router-webui ${cfg.configDir}
        chmod 750 ${cfg.configDir}
        
        # Copy secret file to apprise config location
        cp ${config.sops.secrets."apprise-urls".path} ${cfg.configDir}/apprise
        chown router-webui:router-webui ${cfg.configDir}/apprise
        chmod 600 ${cfg.configDir}/apprise
      '';
    };
  };
}
