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
              iproute2 iputils bind.dnsutils
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

              prompt_read() {
                local __var_name="$1"
                local __prompt="$2"
                local __value=""
                local __status=0
                if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
                  echo "ERRO: terminal interativo indisponivel em /dev/tty." >&2
                  return 1
                fi
                ${pkgs.coreutils}/bin/printf '\033[0;32m%s\n\033[0m' "$__prompt" >/dev/tty
                ${pkgs.coreutils}/bin/printf '\033[1;37m' >/dev/tty
                read -r __value </dev/tty || __status=$?
                ${pkgs.coreutils}/bin/printf '\033[0m' >/dev/tty
                [ "$__status" -eq 0 ] || return "$__status"
                printf -v "$__var_name" '%s' "$__value"
              }

              choose_install_iface() {
                local path iface i choice list_file
                list_file=$(${pkgs.coreutils}/bin/mktemp)
                for path in /sys/class/net/*; do
                  iface="''${path##*/}"
                  case "$iface" in
                    lo|docker*|virbr*|veth*|br-*|tun*|tap*|wg*) continue ;;
                  esac
                  printf '%s\n' "$iface"
                done | ${pkgs.coreutils}/bin/sort -u > "$list_file"
                if [ ! -s "$list_file" ]; then
                  ${pkgs.coreutils}/bin/rm -f "$list_file"
                  echo "ERRO: nenhuma interface de rede utilizavel foi encontrada." >&2
                  return 1
                fi
                ${pkgs.coreutils}/bin/printf '\033[0;36m%s\n' "Interfaces de rede (escolha antes de informar o IP):"
                i=1
                while IFS= read -r iface; do
                  [ -z "$iface" ] && continue
                  mac=$(${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]' < "/sys/class/net/''${iface}/address" 2>/dev/null || echo "?")
                  ${pkgs.coreutils}/bin/printf '  %s) %s  (MAC: %s)\n' "''${i}" "''${iface}" "''${mac}"
                  i=$((i+1))
                done < "$list_file"
                ${pkgs.coreutils}/bin/printf '\033[0m\n'
                while true; do
                  prompt_read choice "Numero da lista (1, 2, ...): "
                  choice="''${choice//[[:space:]]/}"
                  [ -z "$choice" ] && { echo "Informe o numero da lista."; continue; }
                  case "$choice" in
                    *[!0-9]*)
                      echo "Apenas o numero da lista (nao use o nome da interface)."
                      continue
                      ;;
                  esac
                  iface=""
                  i=0
                  while IFS= read -r line; do
                    i=$((i+1))
                    [ "$i" -eq "$choice" ] || continue
                    iface="$line"
                    break
                  done < "$list_file"
                  if [ -z "$iface" ] || [ ! -e "/sys/class/net/''${iface}" ]; then
                    echo "Numero invalido."
                    continue
                  fi
                  INSTALL_IFACE="$iface"
                  ${pkgs.coreutils}/bin/rm -f "$list_file"
                  echo "Interface selecionada: ''${INSTALL_IFACE}"
                  return 0
                done
              }

              octet_ok() {
                local n="$1"
                [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 0 ] && [ "$n" -le 255 ]
              }

              validate_ipv4() {
                local ip="$1" IFS=.
                [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}''$ ]] || return 1
                read -r o1 o2 o3 o4 <<<"$ip"
                octet_ok "$o1" && octet_ok "$o2" && octet_ok "$o3" && octet_ok "$o4"
              }

              validate_cidr() {
                local cidr="$1" ip prefix
                [[ "$cidr" == */* ]] || return 1
                ip="''${cidr%/*}"
                prefix="''${cidr#*/}"
                [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
                [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ] || return 1
                validate_ipv4 "$ip"
              }

              INSTALL_IFACE=""
              choose_install_iface || exit 1

              apply_static_iface_and_dns() {
                local iface="$INSTALL_IFACE"
                if [ ! -e "/sys/class/net/''${iface}" ]; then
                  echo "ERRO: interface ''${iface} nao existe (verifique o nome com ip link)."
                  return 1
                fi
                ${pkgs.iproute2}/bin/ip link set "$iface" up
                ${pkgs.iproute2}/bin/ip addr flush dev "$iface"
                ${pkgs.iproute2}/bin/ip addr add "''${NET_IP}/''${NET_PREFIX}" dev "$iface"
                ${pkgs.iproute2}/bin/ip route replace default via "''${NET_GW}" dev "$iface"
                ${pkgs.coreutils}/bin/sleep 1
                # Rede estatica nao preenche resolv.conf; sem isso o Nix nao resolve cache.nixos.org
                ${pkgs.coreutils}/bin/rm -f /etc/resolv.conf
                ${pkgs.coreutils}/bin/printf '%s\n' 'nameserver 1.1.1.1' 'nameserver 8.8.8.8' 'nameserver 208.67.222.222' 'nameserver 208.67.220.220' > /etc/resolv.conf
                if ! ${pkgs.bind.dnsutils}/bin/host cache.nixos.org >/dev/null 2>&1; then
                  echo "Falha: nao foi possivel resolver cache.nixos.org (DNS / resolv.conf)."
                  return 1
                fi
                echo "DNS OK (cache.nixos.org resolve)."
                echo ""
                echo "Estado atual (ip addr + rota default):"
                ${pkgs.iproute2}/bin/ip -br addr show dev "$iface"
                ${pkgs.iproute2}/bin/ip route show default
                echo "(Isso vale so nesta sessao do ISO; depois do reboot a rede e network-static.nix por MAC.)"
                return 0
              }

              echo "[0/9] configuracao de rede (IPv4 estatico em ''${INSTALL_IFACE})"
              NET_CIDR=""
              NET_GW=""
              while true; do
                while true; do
                  prompt_read NET_CIDR "Endereco IPv4 com mascara CIDR (ex: 192.168.1.10/24): "
                  NET_CIDR="''${NET_CIDR//[[:space:]]/}"
                  if validate_cidr "$NET_CIDR"; then
                    break
                  fi
                  echo "Formato invalido. Use algo como 192.168.1.10/24"
                done
                NET_IP="''${NET_CIDR%/*}"
                NET_PREFIX="''${NET_CIDR#*/}"
                while true; do
                  prompt_read NET_GW "Gateway IPv4 (ex: 192.168.1.1): "
                  NET_GW="''${NET_GW//[[:space:]]/}"
                  if validate_ipv4 "$NET_GW"; then
                    break
                  fi
                  echo "Gateway invalido."
                done
                echo ""
                echo "Resumo:"
                echo "  address = \"''${NET_IP}\";"
                echo "  prefixLength = ''${NET_PREFIX};"
                echo "  defaultGateway = \"''${NET_GW}\";"
                echo "  interface = ''${INSTALL_IFACE} (sem DHCP nesta interface)"
                echo "  MAC = $(tr '[:upper:]' '[:lower:]' < "/sys/class/net/''${INSTALL_IFACE}/address")"
                echo ""
                prompt_read ans "Confirmar e continuar a instalacao? [s/N]: "
                ans="''${ans//[[:space:]]/}"
                case "''${ans,,}" in
                  s|sim|y|yes)
                    echo "Testando DNS (resolve cache.nixos.org)..."
                    if apply_static_iface_and_dns; then
                      break
                    fi
                    echo "Ajuste IP/gateway ou a rede e confirme de novo."
                    echo ""
                    ;;
                  *)
                    echo "Tente novamente."
                    echo ""
                    ;;
                esac
              done

              echo "[1/9] detectando disco de instalacao"
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

              echo "[2/9] particionando disco $DISK"
              ${pkgs.parted}/bin/parted -s "$DISK" mklabel gpt
              ${pkgs.parted}/bin/parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
              ${pkgs.parted}/bin/parted -s "$DISK" set 1 esp on
              ${pkgs.parted}/bin/parted -s "$DISK" mkpart primary ext4 513MiB 100%

              echo "[3/9] aguardando particoes"
              for _ in $(seq 1 120); do
                ${pkgs.util-linux}/bin/partprobe "$DISK" 2>/dev/null || true
                [ -b "$PART1" ] && [ -b "$PART2" ] && break
                ${pkgs.coreutils}/bin/sleep 1
              done
              [ -b "$PART1" ]
              [ -b "$PART2" ]

              echo "[4/9] formatando particoes"
              ${pkgs.dosfstools}/bin/mkfs.vfat -F32 "$PART1"
              ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F "$PART2"

              echo "[5/9] montando sistema de arquivos"
              ${pkgs.util-linux}/bin/mount "$PART2" /mnt
              ${pkgs.coreutils}/bin/mkdir -p /mnt/boot
              ${pkgs.util-linux}/bin/mount "$PART1" /mnt/boot

              echo "[6/9] gerando hardware-configuration e copiando config do host"
              ${pkgs.nixos-install-tools}/bin/nixos-generate-config --root /mnt
              ${pkgs.coreutils}/bin/cp ${self}/nix/flake.nix /mnt/etc/nixos/flake.nix

              echo "[6b/9] gravando network-static.nix (por MAC, nome da iface pode mudar apos reboot)"
              NIC_MAC=$(tr '[:upper:]' '[:lower:]' < "/sys/class/net/''${INSTALL_IFACE}/address" | tr -d '[:space:]')
              [ -n "$NIC_MAC" ] || { echo "ERRO: nao foi possivel ler MAC de ''${INSTALL_IFACE}"; exit 1; }
              {
                ${pkgs.coreutils}/bin/printf '%s\n' '{ lib, ... }:'
                ${pkgs.coreutils}/bin/printf '%s\n' '{'
                ${pkgs.coreutils}/bin/printf '%s\n' '  networking.useDHCP = lib.mkForce false;'
                ${pkgs.coreutils}/bin/printf '%s\n' '  networking.useNetworkd = true;'
                ${pkgs.coreutils}/bin/printf '%s\n' '  systemd.network.enable = true;'
                ${pkgs.coreutils}/bin/printf '%s\n' '  systemd.network.networks."10-atlaz-wan" = {'
                ${pkgs.coreutils}/bin/printf '    matchConfig.MACAddress = "%s";\n' "$NIC_MAC"
                ${pkgs.coreutils}/bin/printf '    networkConfig.Address = "%s/%s";\n' "''${NET_IP}" "''${NET_PREFIX}"
                ${pkgs.coreutils}/bin/printf '    networkConfig.Gateway = "%s";\n' "''${NET_GW}"
                ${pkgs.coreutils}/bin/printf '%s\n' '    linkConfig.RequiredForOnline = "yes";'
                ${pkgs.coreutils}/bin/printf '%s\n' '  };'
                ${pkgs.coreutils}/bin/printf '%s\n' '}'
              } > /mnt/etc/nixos/network-static.nix

              echo "[7/9] resolvendo flake.lock offline (via store paths)"
              ${pkgs.nix}/bin/nix flake lock /mnt/etc/nixos \
                --override-input atlaz-os path:${self} \
                --override-input nixpkgs path:${nixpkgs}

              echo "[8/9] instalando NixOS"
              if ! ${pkgs.bind.dnsutils}/bin/host cache.nixos.org >/dev/null 2>&1; then
                echo "ERRO: cache.nixos.org nao resolve antes do nixos-install (DNS/rede)." >&2
                exit 1
              fi
              ${pkgs.nixos-install-tools}/bin/nixos-install --root /mnt --flake /mnt/etc/nixos#atlazlog --no-root-passwd --no-channel-copy --show-trace

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
