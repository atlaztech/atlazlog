{ config, pkgs, ... }: {

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

  networking.nameservers = [ "1.1.1.1" ];
  services.resolved.enable = true;
  time.timeZone = "America/Fortalza";


  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    log-driver = "local";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    tcpdump
    wget
    curl
    wireshark-cli
  ];

  systemd.services.atlaz-autoupdate = {
    description = "AtlazLog auto-update";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/etc/nixos";
      ExecStart = pkgs.writeShellScript "atlaz-autoupdate" ''
        ${pkgs.nix}/bin/nix flake update --flake /etc/nixos
        ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake /etc/nixos#atlazlog
      '';
    };
  };

  systemd.timers.atlaz-autoupdate = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "0s";
      OnUnitActiveSec = "30min";
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };

  system.stateVersion = "25.11";

}
