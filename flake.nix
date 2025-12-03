{
  description = "NixOS router configuration with sops-nix secrets management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    router-webui = {
      url = "github:NixRTR/webui";
      flake = false;
    };
    router-docs = {
      url = "github:NixRTR/docs";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      formatter.${system} = pkgs.nixfmt-rfc-style;

      nixosConfigurations.router = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          age
          sops
          nixfmt-rfc-style
          nixos-rebuild
        ];
      };
    };
}

