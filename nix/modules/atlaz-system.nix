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

  users.users.root.hashedPassword = "$y$j9T$Vw1P3PHJs/thpjWZ.5I8x1$FQUDcXDBiCJpmOC4apB9vAfybOb6To1wS9f1/wAXi72";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    download-buffer-size = 1073741824;
  };
}
