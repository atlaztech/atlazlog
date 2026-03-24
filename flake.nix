{
  description = "AtlazLog – NixOS base module + installer ISO";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
  in {

    nixosModules.atlaz-os = import ./modules/atlaz-os.nix;

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

          environment.defaultPackages = lib.mkForce [];
          fonts.fontconfig.enable = lib.mkForce false;
          isoImage.squashfsCompression = null;
          networking.wireless.enable = lib.mkForce false;
          services.udisks2.enable = lib.mkForce false;
          services.getty.autologinUser = lib.mkForce null;
          systemd.services."autovt@tty1".enable = lib.mkForce false;
          systemd.services."getty@tty1".enable = lib.mkForce false;

          systemd.services.autoinstall = {
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" "network-online.target" ];
            wants = [ "network-online.target" ];
            path = with pkgs; [
              bash coreutils util-linux parted dosfstools e2fsprogs
              nix nixos-install-tools git
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = "0";
              StandardOutput = "journal+console";
              StandardError = "journal+console";
            };
            script = ''
              set -euxo pipefail
              PS4='+ [$(date -Is)] line ''${LINENO}: '

              [ -e /tmp/done ] && exit 0
              ${pkgs.coreutils}/bin/touch /tmp/done

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

              echo "[6/9] gerando hardware-configuration e copiando config do host"
              ${pkgs.nixos-install-tools}/bin/nixos-generate-config --root /mnt
              ${pkgs.coreutils}/bin/cp ${self}/host/flake.nix /mnt/etc/nixos/flake.nix
              ${pkgs.coreutils}/bin/cp ${self}/host/configuration.nix /mnt/etc/nixos/configuration.nix

              echo "[7/9] resolvendo flake.lock offline (via store paths)"
              ${pkgs.nix}/bin/nix flake lock /mnt/etc/nixos \
                --override-input atlaz-os path:${self} \
                --override-input nixpkgs path:${nixpkgs}

              echo "[8/9] instalando NixOS"
              ${pkgs.nixos-install-tools}/bin/nixos-install --root /mnt --flake /mnt/etc/nixos#atlazlog --no-root-passwd --no-channel-copy

              echo "[9/9] removendo flake.lock (proximo rebuild resolve via GitHub)"
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
