{ config, pkgs, lib, ... }:
let
  masterPassword = "be4e224c-b18e-49b1-aac9-ca27190ea819";
in {

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      efiInstallAsRemovable = true;
    };
    # Nomes de iface estaveis (eth0/eth1) em VM; network-static.nix casa por MAC.
    kernelParams = [ "console=ttyS0,115200" "net.ifnames=0" "biosdevname=0" ];
    kernel.sysctl."vm.overcommit_memory" = 1;
  };

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

  networking = {
    hostName = "atlaz";
    useDHCP = lib.mkDefault false;
    useNetworkd = true;
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    firewall = {
      allowedTCPPorts = [ 8000 ];
      allowedUDPPorts = [ 2055 ];
    };
    wg-quick.interfaces.wg0 = {
      autostart = true;
      configFile = "/var/lib/atlaz/wg0.conf";
    };
  };

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

      "docker-netflow" = {
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

  services = {
    resolved.enable = true;
    openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };
  };

  time.timeZone = "UTC";

  virtualisation = {
    docker = {
      enable = true;
      daemon.settings.log-driver = "local";
    };

    oci-containers = {
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
  };

  system = {
    activationScripts.restart-containers-after-switch = {
      deps = [ "etc" ];
      text = ''
        if [ -z "''${NIXOS_ACTION:-}" ] || [ "''${NIXOS_ACTION}" = "switch" ]; then
          ${pkgs.systemd}/bin/systemctl try-restart docker-clickhouse.service || true
          ${pkgs.systemd}/bin/systemctl try-restart docker-netflow.service || true
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

  environment.systemPackages = with pkgs; [
    tcpdump
    wget
    curl
    wireshark-cli
  ];

}
