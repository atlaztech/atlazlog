{
  description = "AtlazLog – NixOS base module + installer ISO";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
  in {

    nixosModules.atlaz-os = import ./nix/atlaz-os.nix;

    # ISO de instalação automática
    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ({ modulesPath, lib, pkgs, ... }: {
          imports = [
            (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
          ];

          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          boot.supportedFilesystems.zfs = lib.mkForce false;
          hardware.enableRedistributableFirmware = lib.mkForce false;
          hardware.firmware = lib.mkForce [];

          documentation.enable = false;
          documentation.man.enable = false;
          documentation.nixos.enable = false;

          boot.kernelParams = [ "net.ifnames=0" "biosdevname=0" ];

          environment.defaultPackages = lib.mkForce [];
          fonts.fontconfig.enable = lib.mkForce false;
          isoImage.squashfsCompression = null;
          networking.useDHCP = lib.mkDefault false;
          networking.useNetworkd = true;
          networking.wireless.enable = lib.mkForce false;
          services.udisks2.enable = lib.mkForce false;
          systemd.network.enable = true;
          services.getty.autologinUser = lib.mkForce null;
          systemd.services."autovt@tty1".enable = lib.mkForce false;
          systemd.services."getty@tty1".enable = lib.mkForce false;
          services.cloud-init = {
            enable = true;
            network.enable = true;
            settings = {
              datasource_list = [ "NoCloud" "ConfigDrive" ];
              system_info = {
                distro = "nixos";
                network.renderers = [ "networkd" ];
              };
              cloud_init_modules = [ "seed_random" ];
              cloud_config_modules = [ ];
              cloud_final_modules = [ ];
            };
          };
          systemd.services.cloud-init.wantedBy = lib.mkForce [ ];
          systemd.services.cloud-config.wantedBy = lib.mkForce [ ];
          systemd.services.cloud-final.wantedBy = lib.mkForce [ ];

          systemd.services.autoinstall = {
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" "cloud-init-local.service" "network-online.target" ];
            wants = [ "cloud-init-local.service" "network-online.target" ];
            requires = [ "cloud-init-local.service" ];
            path = with pkgs; [
              bash coreutils util-linux parted dosfstools e2fsprogs
              nix nixos-install-tools git
            ];
            serviceConfig = {
              Type = "simple";
              TimeoutStartSec = "0";
              StandardInput = "tty-force";
              StandardOutput = "tty";
              StandardError = "journal+console";
              TTYPath = "/dev/tty1";
              TTYReset = true;
              TTYVHangup = true;
            };
            script = ''
              set -euo pipefail

              [ -e /tmp/done ] && exit 0
              ${pkgs.coreutils}/bin/touch /tmp/done

              internet_ok() {
                ${pkgs.iputils}/bin/ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && return 0
                ${pkgs.iputils}/bin/ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && return 0
                ${pkgs.curl}/bin/curl -fsSI --connect-timeout 5 https://cache.nixos.org >/dev/null 2>&1 && return 0
                return 1
              }

              echo "[0/8] verificando conectividade apos cloud-init"
              if internet_ok; then
                echo "Conectividade com a internet OK."
              else
                ${pkgs.coreutils}/bin/printf '\033[1;31m' >/dev/tty
                echo "ALERTA: o cloud-init aplicou a rede, mas a VM ainda esta sem internet." >/dev/tty
                echo "Revise gateway, rota padrao, bridge/NAT e regras do Proxmox." >/dev/tty
                echo "Estado atual da rede:" >/dev/tty
                ${pkgs.iproute2}/bin/ip -brief addr >/dev/tty || true
                ${pkgs.iproute2}/bin/ip route >/dev/tty || true
                ${pkgs.coreutils}/bin/printf '\033[0m' >/dev/tty
                echo "Abortando a instalacao antes de particionar o disco." >/dev/tty
                exit 1
              fi

              echo "[1/8] detectando disco de instalacao"
              DISK=""
              for _ in $(seq 1 60); do
                for d in /dev/vda /dev/sda /dev/nvme0n1; do
                  if [ -b "$d" ]; then
                    DISK="$d"
                    break 2
                  fi
                done
                ${pkgs.coreutils}/bin/sleep 1
              done
              [ -n "$DISK" ] || { echo "ERRO: nenhum disco encontrado"; exit 1; }
              echo "disco detectado: $DISK"

              if [[ "$DISK" == /dev/nvme* ]]; then
                PART1="''${DISK}p1"
                PART2="''${DISK}p2"
              else
                PART1="''${DISK}1"
                PART2="''${DISK}2"
              fi

              echo "[2/8] particionando disco $DISK"
              ${pkgs.parted}/bin/parted -s "$DISK" mklabel gpt
              ${pkgs.parted}/bin/parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
              ${pkgs.parted}/bin/parted -s "$DISK" set 1 esp on
              ${pkgs.parted}/bin/parted -s "$DISK" mkpart primary ext4 513MiB 100%

              echo "[3/8] aguardando particoes"
              for _ in $(seq 1 120); do
                ${pkgs.util-linux}/bin/partprobe "$DISK" 2>/dev/null || true
                [ -b "$PART1" ] && [ -b "$PART2" ] && break
                ${pkgs.coreutils}/bin/sleep 1
              done
              [ -b "$PART1" ]
              [ -b "$PART2" ]

              echo "[4/8] formatando particoes"
              ${pkgs.dosfstools}/bin/mkfs.vfat -F32 "$PART1"
              ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F "$PART2"

              echo "[5/8] montando sistema de arquivos"
              ${pkgs.util-linux}/bin/mount "$PART2" /mnt
              ${pkgs.coreutils}/bin/mkdir -p /mnt/boot
              ${pkgs.util-linux}/bin/mount "$PART1" /mnt/boot

              echo "[6/8] gerando hardware-configuration e copiando config do host"
              ${pkgs.nixos-install-tools}/bin/nixos-generate-config --root /mnt
              ${pkgs.coreutils}/bin/cp ${self}/nix/flake.nix /mnt/etc/nixos/flake.nix

              echo "[6b/8] rede do sistema final sera configurada pelo cloud-init do Proxmox"

              echo "[7/8] resolvendo flake.lock offline (via store paths)"
              ${pkgs.nix}/bin/nix flake lock /mnt/etc/nixos \
                --override-input atlaz-os path:${self} \
                --override-input nixpkgs path:${nixpkgs}

              echo "[8/8] instalando NixOS"
              ${pkgs.nixos-install-tools}/bin/nixos-install --root /mnt --flake /mnt/etc/nixos#atlazlog --no-root-passwd --no-channel-copy --show-trace
              
              echo "[final] removendo flake.lock (proximo rebuild resolve via GitHub)"
              ${pkgs.coreutils}/bin/rm -f /mnt/etc/nixos/flake.lock
              echo "[final] reiniciando sistema"
              ${pkgs.systemd}/bin/systemctl reboot
            '';
          };
        })
      ];
    };

  };
}
