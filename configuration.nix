{ config, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

  networking.hostName = "atlazlog";
  networking.nameservers = [ "8.8.8.8" ];
  services.resolved.enable = true;
  time.timeZone = "America/Fortaleza";

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  users.users.root.hashedPassword = "$y$j9T$2oH4LFkNDPoMx6UPrcw0g.$RupKkWamcUJdr4qFAiZ7nE/mtq3G42PcBghpRTQnBSD";

}
