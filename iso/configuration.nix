{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # ISO label and identification
  isoImage.isoName = "nixos-router-installer.iso";
  isoImage.volumeID = "NIXOS_ROUTER";
  
  # Make the ISO bootable on both UEFI and BIOS
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # Branding
  system.stateVersion = "25.05";
  
  # Add router installation scripts to the ISO
  environment.systemPackages = with pkgs; [
    # Essential tools
    git
    curl
    wget
    jq
    vim
    nano
    htop
    tmux
    
    # Networking tools
    iproute2
    ethtool
    tcpdump
    nmap
    
    # Disk tools
    parted
    gptfdisk
    
    # Custom script package
    (pkgs.writeScriptBin "router-menu" ''
      #!${pkgs.bash}/bin/bash
      exec ${pkgs.bash}/bin/bash /etc/nixos-router/auto-menu.sh "$@"
    '')
  ];

  # Copy the auto-menu script to the ISO
  environment.etc."nixos-router/auto-menu.sh" = {
    source = ./auto-menu.sh;
    mode = "0755";
  };

  # Create a helpful README on the ISO
  environment.etc."nixos-router/README.txt" = {
    text = ''
      ═══════════════════════════════════════════════════════════
           NixOS Router - Custom Installation ISO
      ═══════════════════════════════════════════════════════════

      This ISO contains everything needed to install or update
      your NixOS router configuration.

      QUICK START:
      ────────────

      The menu system will start automatically on boot.
      
      If you need to start it manually, run:
        $ sudo router-menu

      AUTOMATED INSTALLATION:
      ───────────────────────

      1. Create a router-config.nix file with your settings
      2. Copy it to the root of a USB drive
      3. Boot from this ISO with the USB drive inserted
      4. Select "Automated Installation" from the menu

      The installer will detect your configuration and proceed
      with minimal interaction.

      MANUAL INSTALLATION:
      ────────────────────

      Select "Guided Installation" from the menu to run the
      interactive installer.

      UPDATING EXISTING ROUTER:
      ─────────────────────────

      Boot your existing router from this ISO and select:
        - "Update Router Software" to update NixOS config
        - "Update Router Config" to modify router-config.nix

      DOCUMENTATION:
      ──────────────

      Visit: https://github.com/your-username/nixos-router/docs

      SUPPORT:
      ────────

      For issues or questions, see the project repository.

      ═══════════════════════════════════════════════════════════
    '';
    mode = "0644";
  };

  # Auto-login as nixos user
  services.getty.autologinUser = "nixos";

  # Auto-start the menu on login
  programs.bash.interactiveShellInit = ''
    # Only run menu on first login (tty1)
    if [ "$(tty)" = "/dev/tty1" ] && [ -z "$ROUTER_MENU_STARTED" ]; then
      export ROUTER_MENU_STARTED=1
      
      # Show welcome message
      echo ""
      echo "═══════════════════════════════════════════════════════════"
      echo "   Welcome to NixOS Router Installation System"
      echo "═══════════════════════════════════════════════════════════"
      echo ""
      echo "Starting router menu in 3 seconds..."
      echo "Press Ctrl+C to cancel and use shell directly."
      echo ""
      
      sleep 3
      
      # Run the menu as root
      sudo router-menu
    fi
  '';

  # Enable sudo without password for nixos user during installation
  security.sudo.wheelNeedsPassword = false;
  users.users.nixos.extraGroups = [ "wheel" ];

  # Network configuration - enable DHCP on all interfaces by default
  networking.useDHCP = true;
  networking.wireless.enable = false;  # We'll use wired connections

  # Enable SSH for remote installation (optional)
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Set a default password for nixos user (change this!)
  users.users.nixos.initialPassword = "nixos";

  # Helpful message on boot
  boot.kernelParams = [ "console=tty1" ];
  
  services.getty.helpLine = ''
    
    NixOS Router Installation System
    
    The automated menu will start automatically.
    Run 'sudo router-menu' to restart it if needed.
    
    Default login: nixos / nixos
    
  '';

  # Pre-configure some network settings for convenience
  environment.etc."network-setup-info.txt" = {
    text = ''
      Network Interface Detection:
      ───────────────────────────
      
      To list all network interfaces:
        ip link show
      
      To see interface details:
        ip addr show
      
      To check which interfaces have link:
        for iface in /sys/class/net/*; do
          name=$(basename $iface)
          if [ "$name" != "lo" ]; then
            echo -n "$name: "
            cat $iface/operstate
          fi
        done
    '';
    mode = "0644";
  };

  # Increase ISO size limit if needed
  isoImage.squashfsCompression = "zstd -Xcompression-level 15";
}

