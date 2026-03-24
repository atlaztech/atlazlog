{ config, pkgs, ... }: {

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

  networking.nameservers = [ "8.8.8.8" ];
  services.resolved.enable = true;
  time.timeZone = "UTC";

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    log-driver = "local";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.11";

}
