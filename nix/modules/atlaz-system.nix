{ pkgs, ... }:
{
  time.timeZone = "UTC";

  system = {
    activationScripts.restart-containers-after-switch = {
      deps = [ "etc" ];
      text = ''
        if [ -z "''${NIXOS_ACTION:-}" ] || [ "''${NIXOS_ACTION}" = "switch" ]; then
          ${pkgs.systemd}/bin/systemctl try-restart docker-clickhouse.service || true
          ${pkgs.systemd}/bin/systemctl try-restart docker-atlazlog.service || true
        fi
      '';
    };
    stateVersion = "25.11";
  };

  users.users.root.hashedPassword = "$y$j9T$2oH4LFkNDPoMx6UPrcw0g.$RupKkWamcUJdr4qFAiZ7nE/mtq3G42PcBghpRTQnBSD";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    download-buffer-size = 1073741824;
  };
}
