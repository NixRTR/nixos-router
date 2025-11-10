{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dnclient;
  routerConfig = import ./router-config.nix;
  dnclientConfig = routerConfig.dnclient or { enable = false; };

in

{
  options.services.dnclient = {
    enable = mkEnableOption "Defined Networking Nebula client";

    enrollmentCode = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Enrollment code for the host. Only needed for initial enrollment.
        After enrollment, this can be removed from the configuration.
      '';
    };

    enrollmentCodeFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to file containing enrollment code. Preferred over enrollmentCode
        for security (can use sops-nix secrets).
      '';
    };

    configDir = mkOption {
      type = types.str;
      default = "/var/lib/dnclient";
      description = "Directory for dnclient configuration and state";
    };

    port = mkOption {
      type = types.port;
      default = 4242;
      description = "UDP port for Nebula traffic";
    };

    image = mkOption {
      type = types.str;
      default = "definednet/dnclient:latest";
      description = "Docker image for dnclient";
    };
  };

  config = mkIf (dnclientConfig.enable or false) (mkMerge [
    {
      services.dnclient = {
        enable = true;
        enrollmentCode = dnclientConfig.enrollmentCode or null;
        enrollmentCodeFile = dnclientConfig.enrollmentCodeFile or null;
        port = dnclientConfig.port or 4242;
      };
    }
    
    (mkIf cfg.enable {
      # Enable Docker
      virtualisation.docker.enable = true;

      # Ensure config directory exists
      systemd.tmpfiles.rules = [
        "d ${cfg.configDir} 0700 root root -"
      ];

      # Docker container for dnclient
      systemd.services.dnclient = {
        description = "Defined Networking Nebula client (Docker)";
        after = [ "docker.service" "network-online.target" ];
        requires = [ "docker.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          
          # Stop existing container
          ExecStartPre = [
            "-${pkgs.docker}/bin/docker stop dnclient"
            "-${pkgs.docker}/bin/docker rm dnclient"
          ];
          
          # Start container
          ExecStart = pkgs.writeShellScript "dnclient-start" ''
            set -euo pipefail
            
            # Get enrollment code if provided
            ENROLL_ARGS=""
            ${optionalString (cfg.enrollmentCode != null) ''
              ENROLL_ARGS="-e ENROLL_CODE='${cfg.enrollmentCode}'"
            ''}
            ${optionalString (cfg.enrollmentCodeFile != null) ''
              if [ -f "${cfg.enrollmentCodeFile}" ]; then
                ENROLL_CODE=$(cat "${cfg.enrollmentCodeFile}")
                ENROLL_ARGS="-e ENROLL_CODE=$ENROLL_CODE"
              fi
            ''}
            
            # Run dnclient container
            ${pkgs.docker}/bin/docker run \
              --name dnclient \
              --rm \
              --network host \
              --cap-add NET_ADMIN \
              --device /dev/net/tun \
              -v ${cfg.configDir}:/etc/dnclient \
              $ENROLL_ARGS \
              ${cfg.image}
          '';
          
          # Stop container
          ExecStop = "${pkgs.docker}/bin/docker stop dnclient";
        };
      };

      # Allow Nebula traffic through firewall
      networking.firewall.allowedUDPPorts = [ cfg.port ];
    })
  ]);
}
