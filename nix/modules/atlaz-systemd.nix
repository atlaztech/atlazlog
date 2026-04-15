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

      atlaz-docker-prune = {
        description = "Remove unused Docker images";
        after = [ "docker.service" ];
        wants = [ "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.docker}/bin/docker image prune -af";
        };
      };

      atlaz-autoupdate = {
        description = "AtlazLog auto-update";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/etc/nixos";
          ExecStart = pkgs.writeShellScript "atlaz-autoupdate" ''
            ${pkgs.systemd}/bin/systemctl reset-failed nixos-rebuild-switch-to-configuration.service 2>/dev/null || true
            ${pkgs.nix}/bin/nix flake update --flake /etc/nixos
            ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake /etc/nixos#atlazlog
          '';
          RestartSec = "60s";
          Restart = "on-failure";
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

    timers.atlaz-docker-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 09:00:00";
        Persistent = true;
      };
    };

    timers.atlaz-autoupdate = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}
