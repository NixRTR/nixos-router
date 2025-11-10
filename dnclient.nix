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
      sha256 = "sha256-Cup1BFOQo1NTZWfk5lVhtODZ+K9tLrklMceUCgMsovw=";
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
    # Note: Enrollment must happen AFTER dnclient daemon is started
    systemd.services.dnclient-enroll = mkIf (cfg.enrollmentCode != null || cfg.enrollmentCodeFile != null) {
      description = "Enroll Defined Networking host";
      after = [ "network-online.target" "dnclient.service" ];
      requires = [ "dnclient.service" ];
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
          
          # Create config directory if it doesn't exist
          mkdir -p "${cfg.configDir}"
          cd "${cfg.configDir}"
          
          # Wait for dnclient daemon to be ready
          for i in {1..30}; do
            if [ -S /var/run/dnclient.sock ]; then
              echo "dnclient daemon is ready"
              break
            fi
            if [ $i -eq 30 ]; then
              echo "ERROR: dnclient daemon socket not found after 30 seconds"
              exit 1
            fi
            echo "Waiting for dnclient daemon... ($i/30)"
            sleep 1
          done
          
          # Run enrollment - requires running daemon
          echo "Running enrollment command..."
          ${cfg.package}/bin/dnclient enroll -code "$ENROLL_CODE"
          
          # Verify config was created
          if [ ! -f "${cfg.configDir}/config.yml" ] || [ ! -s "${cfg.configDir}/config.yml" ]; then
            echo "ERROR: Enrollment completed but valid config.yml not found"
            exit 1
          fi
          
          echo "Enrollment complete - restarting dnclient with new config"
          # Restart dnclient to use the new configuration
          ${pkgs.systemd}/bin/systemctl restart dnclient.service
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
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = cfg.configDir;
        ExecStartPre = pkgs.writeShellScript "dnclient-check-config" ''
          # If not enrolled and enrollment code provided, create a dummy config to allow service to start
          if [ ! -f "${cfg.configDir}/config.yml" ]; then
            ${optionalString (cfg.enrollmentCode != null || cfg.enrollmentCodeFile != null) ''
              echo "Creating placeholder config for initial enrollment..."
              cat > "${cfg.configDir}/config.yml" <<EOF
# Placeholder config - will be replaced by enrollment
EOF
            ''}
            ${optionalString (cfg.enrollmentCode == null && cfg.enrollmentCodeFile == null) ''
              echo "ERROR: dnclient not enrolled yet. Please provide enrollmentCode or enrollmentCodeFile."
              exit 1
            ''}
          fi
          
          # Update port if non-default and config exists
          if [ -s "${cfg.configDir}/config.yml" ] && [ "$(wc -l < "${cfg.configDir}/config.yml")" -gt 1 ]; then
            ${optionalString (cfg.port != 4242) ''
              echo "Ensuring port is set to ${toString cfg.port}..."
              ${pkgs.gnused}/bin/sed -i 's/listen:.*$/listen: "0.0.0.0:${toString cfg.port}"/' "${cfg.configDir}/config.yml"
            ''}
          fi
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

