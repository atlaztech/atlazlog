{ config, pkgs, lib, ... }:
let
  masterPassword = "be4e224c-b18e-49b1-aac9-ca27190ea819";
in {

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  boot.kernelParams = [ "console=ttyS0,115200" ];
  systemd.services."serial-getty@ttyS0".enable = true;

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

  networking.hostName = "atlaz";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  networking.firewall.allowedTCPPorts = [ 8000 ];
  networking.firewall.allowedUDPPorts = [ 2055 ];

  systemd.services."systemd-networkd-wait-online".enable = lib.mkForce false;

  systemd.tmpfiles.rules = [
    "d /var/lib/atlaz 0755 root root -"
  ];

  networking.wg-quick.interfaces.wg0 = {
    autostart = true;
    configFile = "/var/lib/atlaz/wg0.conf";
  };

  # Não puxar wg-quick no boot (o arquivo ainda não existe). Só o .path abaixo inicia o serviço.
  systemd.services."wg-quick-wg0".wantedBy = lib.mkForce [ ];
  systemd.services."wg-quick-wg0".unitConfig.ConditionPathExists = "/var/lib/atlaz/wg0.conf";

  systemd.paths.wg-quick-wg0-activate = {
    wantedBy = [ "paths.target" ];
    after = [ "docker.service" ];
    wants = [ "docker.service" ];
    pathConfig = {
      PathExists = "/var/lib/atlaz/wg0.conf";
      Unit = "wg-quick-wg0.service";
    };
  };
  services.resolved.enable = true;
  time.timeZone = "UTC";


  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    log-driver = "local";
  };

  virtualisation.oci-containers = {
    backend = "docker";

    containers.clickhouse = {
      image = "clickhouse/clickhouse-server:latest";
      environment = {
        CLICKHOUSE_DB = "laravel";
        CLICKHOUSE_USER = "laravel";
        CLICKHOUSE_PASSWORD = masterPassword;
        LISTEN_HOST = "0.0.0.0";
      };
      volumes = [
        "clickhouse_data:/var/lib/clickhouse"
        "clickhouse_logs:/var/log/clickhouse-server"
        "${./clickhouse_config.xml}:/etc/clickhouse-server/config.d/custom.xml:ro"
      ];
      extraOptions = [ "--network=host" ];
    };

    containers.netflow = {
      image = "atlaztech/netflow:latest";
      environment = {
        APP_ENV = "production";
        APP_DEBUG = "false";
        DB_PASSWORD = masterPassword;
        REDIS_PASSWORD = masterPassword;
        CLICKHOUSE_PASSWORD = masterPassword;
      };
      volumes = [
        "pg_data:/var/lib/postgresql/data"
        "/var/lib/atlaz:/var/lib/atlaz"
      ];
      dependsOn = [ "clickhouse" ];
      extraOptions = [ "--network=host" "--pull=always" "--privileged" ];
    };
  };

  systemd.services."docker-clickhouse" = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ config.system.build.toplevel ];
  };

  systemd.services."docker-netflow" = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ config.system.build.toplevel ];
  };

  users.users.root.hashedPassword = "$y$j9T$2oH4LFkNDPoMx6UPrcw0g.$RupKkWamcUJdr4qFAiZ7nE/mtq3G42PcBghpRTQnBSD";

  boot.kernel.sysctl."vm.overcommit_memory" = 1;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    download-buffer-size = 1073741824;
  };

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
      OnCalendar = "*-*-* 06:00:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };

  system.stateVersion = "25.11";

}
