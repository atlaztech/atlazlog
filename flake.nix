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

              echo "[1/8] aguardando disco /dev/vda"
              for _ in $(seq 1 60); do
                [ -b /dev/vda ] && break
                ${pkgs.coreutils}/bin/sleep 1
              done
              [ -b /dev/vda ]

              echo "[2/8] particionando disco"
              ${pkgs.parted}/bin/parted -s /dev/vda mklabel gpt
              ${pkgs.parted}/bin/parted -s /dev/vda mkpart ESP fat32 1MiB 513MiB
              ${pkgs.parted}/bin/parted -s /dev/vda set 1 esp on
              ${pkgs.parted}/bin/parted -s /dev/vda mkpart primary ext4 513MiB 100%

              echo "[3/8] aguardando particoes"
              for _ in $(seq 1 120); do
                ${pkgs.util-linux}/bin/partprobe /dev/vda 2>/dev/null || true
                [ -b /dev/vda1 ] && [ -b /dev/vda2 ] && break
                ${pkgs.coreutils}/bin/sleep 1
              done
              [ -b /dev/vda1 ]
              [ -b /dev/vda2 ]

              echo "[4/8] formatando particoes"
              ${pkgs.dosfstools}/bin/mkfs.vfat -F32 /dev/vda1
              ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F /dev/vda2

              echo "[5/8] montando sistema de arquivos"
              ${pkgs.util-linux}/bin/mount /dev/vda2 /mnt
              ${pkgs.coreutils}/bin/mkdir -p /mnt/boot
              ${pkgs.util-linux}/bin/mount /dev/vda1 /mnt/boot

              echo "[6/8] gerando hardware-configuration e copiando flake do host"
              ${pkgs.nixos-install-tools}/bin/nixos-generate-config --root /mnt
              ${pkgs.coreutils}/bin/cp ${self}/host/flake.nix /mnt/etc/nixos/flake.nix
              ${pkgs.coreutils}/bin/cp ${self}/host/configuration.nix /mnt/etc/nixos/configuration.nix

              echo "[7/8] atualizando flake.lock"
              ${pkgs.nix}/bin/nix flake lock /mnt/etc/nixos

              echo "[8/8] instalando NixOS"
              ${pkgs.nixos-install-tools}/bin/nixos-install --root /mnt --flake /mnt/etc/nixos#atlazlog --no-root-passwd --no-channel-copy
              echo "[final] reiniciando sistema"
              ${pkgs.systemd}/bin/systemctl reboot
            '';
          };
        })
      ];
    };

  };
}
