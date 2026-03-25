{ config, pkgs, ... }: {

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  boot.kernelParams = [ "console=ttyS0,115200" ];
  systemd.services."serial-getty@ttyS0".enable = true;

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

  networking.hostName = "atlaz";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  networking.firewall.allowedTCPPorts = [ 8000 8123 9000 5432 6379 ];
  networking.firewall.allowedUDPPorts = [ 2055 ];
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
        CLICKHOUSE_PASSWORD = "be4e224c-b18e-49b1-aac9-ca27190ea819";
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
        DB_HOST = "127.0.0.1";
        DB_USERNAME = "laravel";
        DB_DATABASE = "laravel";
        DB_PASSWORD = "be4e224c-b18e-49b1-aac9-ca27190ea819";
        REDIS_CLIENT = "phpredis";
        REDIS_HOST = "127.0.0.1";
        REDIS_PASSWORD = "be4e224c-b18e-49b1-aac9-ca27190ea819";
        REDIS_PORT = "6379";
        CACHE_STORE = "redis";
        CLICKHOUSE_URL = "http://127.0.0.1:8123";
        CLICKHOUSE_HOST = "127.0.0.1";
        CLICKHOUSE_DATABASE = "laravel";
        CLICKHOUSE_USERNAME = "laravel";
        CLICKHOUSE_PASSWORD = "be4e224c-b18e-49b1-aac9-ca27190ea819";
      };
      volumes = [
        "pg_data:/var/lib/postgresql/data"
      ];
      dependsOn = [ "clickhouse" ];
      extraOptions = [ "--network=host" "--pull=always" "--privileged" ];
    };
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
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };

  system.stateVersion = "25.11";

}
