{ ... }:
{
  imports = [
    ./modules/atlaz-boot.nix
    ./modules/atlaz-networking.nix
    ./modules/atlaz-systemd.nix
    ./modules/atlaz-services.nix
    ./modules/atlaz-docker.nix
    ./modules/atlaz-system.nix
    ./modules/atlaz-packages.nix
    ./modules/atlaz-tty1-banner.nix
  ];
}
