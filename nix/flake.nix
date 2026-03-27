{
  description = "AtlazLog – Host local";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    atlaz-os = {
      url = "github:atlaztech/atlazlog";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, atlaz-os }: {
    nixosConfigurations.atlazlog = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        atlaz-os.nixosModules.atlaz-os
        ./hardware-configuration.nix
      ] ++ nixpkgs.lib.optionals (builtins.pathExists ./network-static.override.nix) [
        ./network-static.override.nix
      ];
    };
  };
}
