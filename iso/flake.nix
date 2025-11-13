
{
  description = "NixOS Router - Custom Installation ISO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: {
    # ISO image for x86_64 systems
    nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        {
          # Additional ISO-specific settings
          nixpkgs.config.allowUnfree = true;
        }
      ];
    };

    # Convenience output for building
    packages.x86_64-linux.default = self.nixosConfigurations.iso.config.system.build.isoImage;
  };
}

