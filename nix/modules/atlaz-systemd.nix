{ pkgs, lib, ... }:
{
  systemd = {
    services = {
      "serial-getty@ttyS0".enable = true;
      "systemd-networkd-wait-online".enable = lib.mkForce false;

      # Não puxar wg-quick no boot (o arquivo ainda não existe). Só o .path abaixo inicia o serviço.
      "wg-quick-wg0" = {
        wantedBy = lib.mkForce [ ];
        unitConfig.ConditionPathExists = "/var/lib/atlaz/wg0.conf";
      };

      "docker-clickhouse" = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

      "docker-atlazlog" = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

      atlaz-autoupdate = {
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
    };

    network.enable = true;

    tmpfiles.rules = [
      "d /var/lib/atlaz 0755 root root -"
    ];

    paths.wg-quick-wg0-activate = {
      wantedBy = [ "paths.target" ];
      after = [ "docker.service" ];
      wants = [ "docker.service" ];
      pathConfig = {
        PathExists = "/var/lib/atlaz/wg0.conf";
        Unit = "wg-quick-wg0.service";
      };
    };

    timers.atlaz-autoupdate = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "0s";
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };
}
