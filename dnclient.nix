{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dnclient;
  routerConfig = import ./router-config.nix;
  dnclientConfig = routerConfig.dnclient or { enable = false; };
  
  # Package for dnclient
  dnclient = pkgs.stdenv.mkDerivation rec {
    pname = "dnclient";
    version = "0.8.4";
    
    src = pkgs.fetchurl {
      url = "https://dl.defined.net/290ff4b6/v${version}/linux/amd64/dnclient";
      sha256 = "0000000000000000000000000000000000000000000000000000"; # FIXME: Need actual hash
    };
    
    dontUnpack = true;
    dontBuild = true;
    
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/dnclient
      chmod +x $out/bin/dnclient
    '';
    
    meta = with lib; {
      description = "Defined Networking Nebula client";
      homepage = "https://defined.net";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  };

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

    package = mkOption {
      type = types.package;
      default = dnclient;
      description = "The dnclient package to use";
    };

    port = mkOption {
      type = types.port;
      default = 4242;
      description = "UDP port for Nebula traffic";
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
    # Ensure config directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0700 root root -"
    ];

    # Enrollment service (oneshot, runs once if enrollment code provided)
    systemd.services.dnclient-enroll = mkIf (cfg.enrollmentCode != null || cfg.enrollmentCodeFile != null) {
      description = "Enroll Defined Networking host";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = cfg.configDir;
        ExecStartPre = pkgs.writeShellScript "dnclient-check-enrollment" ''
          # Skip enrollment if already enrolled (config exists)
          if [ -f "${cfg.configDir}/config.yml" ]; then
            echo "Host already enrolled, skipping..."
            exit 0
          fi
        '';
        ExecStart = pkgs.writeShellScript "dnclient-enroll" ''
          set -euo pipefail
          
          # Skip if already enrolled
          if [ -f "${cfg.configDir}/config.yml" ]; then
            exit 0
          fi
          
          # Get enrollment code
          ${if cfg.enrollmentCodeFile != null then ''
            if [ ! -f "${cfg.enrollmentCodeFile}" ]; then
              echo "Enrollment code file not found: ${cfg.enrollmentCodeFile}"
              exit 1
            fi
            ENROLL_CODE=$(cat "${cfg.enrollmentCodeFile}")
          '' else ''
            ENROLL_CODE="${cfg.enrollmentCode}"
          ''}
          
          if [ -z "$ENROLL_CODE" ]; then
            echo "No enrollment code provided"
            exit 1
          fi
          
          echo "Enrolling host with Defined Networking..."
          cd "${cfg.configDir}"
          ${cfg.package}/bin/dnclient enroll -code "$ENROLL_CODE"
          
          echo "Enrollment complete"
        '';
        ExecStartPost = mkIf (cfg.port != 4242) (pkgs.writeShellScript "dnclient-set-port" ''
          set -euo pipefail
          
          # Update the listen port in config.yml if non-default
          if [ -f "${cfg.configDir}/config.yml" ]; then
            echo "Configuring custom port ${toString cfg.port}..."
            
            # Update listen port using sed
            ${pkgs.gnused}/bin/sed -i 's/listen:.*$/listen: "0.0.0.0:${toString cfg.port}"/' "${cfg.configDir}/config.yml"
            
            echo "Port configuration updated"
          fi
        '');
        User = "root";
        Group = "root";
      };
    };

    # Main dnclient service
    systemd.services.dnclient = {
      description = "Defined Networking Nebula client";
      after = [ "network-online.target" ] 
        ++ optional (cfg.enrollmentCode != null || cfg.enrollmentCodeFile != null) "dnclient-enroll.service";
      wants = [ "network-online.target" ];
      requires = optionals (cfg.enrollmentCode != null || cfg.enrollmentCodeFile != null) [ "dnclient-enroll.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = cfg.configDir;
        ExecStartPre = pkgs.writeShellScript "dnclient-check-config" ''
          if [ ! -f "${cfg.configDir}/config.yml" ]; then
            echo "ERROR: dnclient not enrolled yet. Please provide enrollmentCode or enrollmentCodeFile."
            exit 1
          fi
          
          # Update port if non-default
          ${optionalString (cfg.port != 4242) ''
            echo "Ensuring port is set to ${toString cfg.port}..."
            ${pkgs.gnused}/bin/sed -i 's/listen:.*$/listen: "0.0.0.0:${toString cfg.port}"/' "${cfg.configDir}/config.yml"
          ''}
        '';
        ExecStart = "${cfg.package}/bin/dnclient start -f";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "always";
        RestartSec = "10s";
        User = "root";
        Group = "root";
        
        # Security hardening
        NoNewPrivileges = false; # dnclient needs to create network interfaces
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.configDir ];
        
        # Network capabilities
        AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      };
    };

      # Allow Nebula traffic through firewall
      networking.firewall.allowedUDPPorts = [ cfg.port ];
    })
  ]);
}

