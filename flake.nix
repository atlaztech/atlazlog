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
          boot.kernelParams = [ "systemd.ssh_auto=no" ];
          hardware.enableRedistributableFirmware = lib.mkForce false;
          hardware.firmware = lib.mkForce [];

          documentation.enable = false;
          documentation.man.enable = false;
          documentation.nixos.enable = false;

          environment.defaultPackages = lib.mkForce [];
          fonts.fontconfig.enable = lib.mkForce false;
          isoImage.squashfsCompression = null;
          networking.wireless.enable = lib.mkForce false;
          networking.useDHCP = lib.mkForce false;
          networking.dhcpcd.enable = lib.mkForce false;
          systemd.network.enable = lib.mkForce false;
          networking.networkmanager.enable = lib.mkForce false;
          services.udisks2.enable = lib.mkForce false;
          services.getty.autologinUser = lib.mkForce null;
          systemd.services."autovt@tty1".enable = lib.mkForce false;
          systemd.services."getty@tty1".enable = lib.mkForce false;

          systemd.settings.Manager.ShowStatus = false;

          systemd.services.autoinstall = {
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" ];
            path = with pkgs; [
              bash coreutils util-linux procps parted dosfstools e2fsprogs
              iproute2 iputils bind.dnsutils gnugrep gawk systemd
              dialog kbd
              nix nixos-install-tools git
            ];
            serviceConfig = {
              Type = "simple";
              TimeoutStartSec = "0";
              StandardInput = "tty-force";
              StandardOutput = "tty";
              StandardError = "journal";
              TTYPath = "/dev/tty12";
              TTYReset = true;
              TTYVHangup = true;
              ExecStartPre = [ "${pkgs.kbd}/bin/chvt 12" ];
            };
            script = ''
              set -euo pipefail

              [ -e /tmp/done ] && exit 0
              ${pkgs.coreutils}/bin/touch /tmp/done

              ${pkgs.coreutils}/bin/tput clear 2>/dev/null || ${pkgs.coreutils}/bin/true
              ${pkgs.coreutils}/bin/printf '\n%s\n\n' "Instalador no terminal 12 (Alt+F12). Sem mensagens do systemd nesta tela."

              cache_nixos_resolves() {
                local first_ip ns
                for ns in 8.8.8.8 1.1.1.1 208.67.222.222 208.67.220.220; do
                  first_ip=$(${pkgs.bind.dnsutils}/bin/dig +short A cache.nixos.org @"$ns" +time=1 +tries=1 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E '^[0-9.]+$' | ${pkgs.coreutils}/bin/head -n1)
                  [ -n "$first_ip" ] && return 0
                done
                return 1
              }

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
                local path iface list_file args=() choice
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
                while IFS= read -r iface; do
                  [ -z "$iface" ] && continue
                  mac=$(${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]' < "/sys/class/net/''${iface}/address" 2>/dev/null || echo "?")
                  args+=("$iface" "$iface - $mac")
                done < "$list_file"
                ${pkgs.coreutils}/bin/rm -f "$list_file"
                while true; do
                  if choice=$(TERM=linux ${pkgs.dialog}/bin/dialog --stdout --clear \
                    --menu "Interface de instalacao (WAN)" 20 72 10 "''${args[@]}" 2>/dev/tty) </dev/tty >/dev/tty; then
                    [ -n "$choice" ] && [ -e "/sys/class/net/''${choice}" ] || continue
                    INSTALL_IFACE="$choice"
                    echo "Interface: ''${INSTALL_IFACE}"
                    return 0
                  fi
                  echo "Selecione uma interface (Cancel nao encerra o instalador)."
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

              restore_resolv_and_nss() {
                local iface="$INSTALL_IFACE"
                ${pkgs.systemd}/bin/resolvectl dns "$iface" 8.8.8.8 1.1.1.1 208.67.222.222 208.67.220.220 2>/dev/null || true
                ${pkgs.systemd}/bin/resolvectl flush-caches 2>/dev/null || true
                ${pkgs.systemd}/bin/systemctl stop systemd-resolved 2>/dev/null || true
                ${pkgs.coreutils}/bin/rm -f /etc/resolv.conf
                ${pkgs.coreutils}/bin/printf '%s\n' \
                  'nameserver 8.8.8.8' \
                  'nameserver 1.1.1.1' \
                  'nameserver 208.67.222.222' \
                  'nameserver 208.67.220.220' \
                  > /etc/resolv.conf
                if [ -r /etc/nsswitch.conf ]; then
                  NSS_TMP=$(${pkgs.coreutils}/bin/mktemp)
                  ${pkgs.gawk}/bin/awk '/^hosts:/ { print "hosts: files dns"; next } { print }' /etc/nsswitch.conf > "$NSS_TMP"
                  ${pkgs.util-linux}/bin/mount --bind "$NSS_TMP" /etc/nsswitch.conf 2>/dev/null || ${pkgs.coreutils}/bin/cp -f "$NSS_TMP" /etc/nsswitch.conf 2>/dev/null || true
                fi
              }

              enforce_static_ipv4() {
                local d iface="$1" want="''${NET_IP}/''${NET_PREFIX}"
                for d in $(${pkgs.iproute2}/bin/ip -4 addr show dev "$iface" | ${pkgs.gawk}/bin/awk '/inet / { print $2 }'); do
                  [ "$d" = "$want" ] && continue
                  ${pkgs.iproute2}/bin/ip addr del "$d" dev "$iface" 2>/dev/null || true
                done
                while ${pkgs.iproute2}/bin/ip route show default 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'proto dhcp'; do
                  ${pkgs.iproute2}/bin/ip route del default proto dhcp 2>/dev/null || break
                done
                ${pkgs.iproute2}/bin/ip route replace default via "''${NET_GW}" dev "$iface" src "''${NET_IP}" metric 10
              }

              stop_dhcp_stack() {
                ${pkgs.systemd}/bin/systemctl stop NetworkManager.service 2>/dev/null || true
                ${pkgs.systemd}/bin/systemctl stop "dhcpcd@''${INSTALL_IFACE}.service" 2>/dev/null || true
                ${pkgs.systemd}/bin/systemctl stop dhcpcd.service 2>/dev/null || true
                ${pkgs.systemd}/bin/systemctl stop systemd-networkd.service 2>/dev/null || true
                ${pkgs.systemd}/bin/systemctl mask --runtime \
                  "dhcpcd@''${INSTALL_IFACE}.service" dhcpcd.service systemd-networkd.service NetworkManager.service \
                  2>/dev/null || true
                ${pkgs.procps}/bin/pkill -f 'dhcpcd|dhclient|udhcpc' 2>/dev/null || true
              }

              apply_static_iface_and_dns() {
                local iface="$INSTALL_IFACE"
                if [ ! -e "/sys/class/net/''${iface}" ]; then
                  echo "ERRO: interface ''${iface} nao existe."
                  return 1
                fi
                stop_dhcp_stack
                ${pkgs.iproute2}/bin/ip link set "$iface" up
                ${pkgs.iproute2}/bin/ip route flush default 2>/dev/null || true
                ${pkgs.iproute2}/bin/ip addr flush dev "$iface"
                ${pkgs.iproute2}/bin/ip addr add "''${NET_IP}/''${NET_PREFIX}" dev "$iface"
                ${pkgs.iproute2}/bin/ip route replace default via "''${NET_GW}" dev "$iface" src "''${NET_IP}" metric 10
                enforce_static_ipv4 "$iface"
                restore_resolv_and_nss
                local dns_ok=0
                for _ in $(seq 1 3); do
                  enforce_static_ipv4 "$iface"
                  if cache_nixos_resolves; then
                    dns_ok=1
                    break
                  fi
                  ${pkgs.coreutils}/bin/sleep 1
                done
                if [ "$dns_ok" -ne 1 ]; then
                  echo "Falha: cache.nixos.org nao resolve."
                  return 1
                fi
                echo "DNS OK (cache.nixos.org)."
                ${pkgs.iproute2}/bin/ip -br addr show dev "$iface"
                ${pkgs.iproute2}/bin/ip route show default
                echo "(So nesta sessao do ISO; apos reboot a rede e network-static.nix por MAC.)"
                return 0
              }

              echo "[0/10] configuracao de rede (dialog: interface, IP/CIDR, gateway)"
              NET_CIDR=""
              NET_GW=""
              NET_IP=""
              NET_PREFIX=""
              if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
                echo "ERRO: terminal interativo indisponivel em /dev/tty." >&2
                exit 1
              fi
              while true; do
                while true; do
                  if v=$(TERM=linux ${pkgs.dialog}/bin/dialog --stdout --clear \
                    --inputbox "IPv4 com mascara CIDR (ex: 192.168.1.10/24)" 10 55 "" 2>/dev/tty) </dev/tty >/dev/tty; then
                    v="''${v//[[:space:]]/}"
                    if validate_cidr "$v"; then
                      NET_CIDR="$v"
                      break
                    fi
                    ${pkgs.dialog}/bin/dialog --clear --msgbox "Formato invalido. Ex: 192.168.1.10/24" 8 50 2>/dev/tty || true
                  else
                    prompt_read NET_CIDR "IPv4 com mascara CIDR (ex: 192.168.1.10/24): "
                    NET_CIDR="''${NET_CIDR//[[:space:]]/}"
                    validate_cidr "$NET_CIDR" && break
                    echo "Formato invalido."
                  fi
                done
                NET_IP="''${NET_CIDR%/*}"
                NET_PREFIX="''${NET_CIDR#*/}"
                while true; do
                  if v=$(TERM=linux ${pkgs.dialog}/bin/dialog --stdout --clear \
                    --inputbox "Gateway IPv4 (ex: 192.168.1.1)" 9 50 "" 2>/dev/tty) </dev/tty >/dev/tty; then
                    v="''${v//[[:space:]]/}"
                    if validate_ipv4 "$v"; then
                      NET_GW="$v"
                      break
                    fi
                    ${pkgs.dialog}/bin/dialog --clear --msgbox "Gateway IPv4 invalido." 7 40 2>/dev/tty || true
                  else
                    prompt_read NET_GW "Gateway IPv4 (ex: 192.168.1.1): "
                    NET_GW="''${NET_GW//[[:space:]]/}"
                    validate_ipv4 "$NET_GW" && break
                    echo "Gateway invalido."
                  fi
                done
                if TERM=linux ${pkgs.dialog}/bin/dialog --clear --yesno \
                  "Confirmar?\n\n''${NET_IP}/''${NET_PREFIX} via ''${NET_GW}\niface ''${INSTALL_IFACE}" 12 60 2>/dev/tty </dev/tty >/dev/tty; then
                  if apply_static_iface_and_dns; then
                    break
                  fi
                  ${pkgs.dialog}/bin/dialog --clear --msgbox "Ajuste valores ou rede e confirme de novo." 8 55 2>/dev/tty || true
                else
                  echo "Revise os dados."
                fi
              done

              echo "[1/10] detectando disco de instalacao"
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

              echo "[2/10] particionando disco $DISK"
              ${pkgs.parted}/bin/parted -s "$DISK" mklabel gpt
              ${pkgs.parted}/bin/parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
              ${pkgs.parted}/bin/parted -s "$DISK" set 1 esp on
              ${pkgs.parted}/bin/parted -s "$DISK" mkpart primary ext4 513MiB 100%

              echo "[3/10] aguardando particoes"
              for _ in $(seq 1 120); do
                ${pkgs.util-linux}/bin/partprobe "$DISK" 2>/dev/null || true
                [ -b "$PART1" ] && [ -b "$PART2" ] && break
                ${pkgs.coreutils}/bin/sleep 1
              done
              [ -b "$PART1" ]
              [ -b "$PART2" ]

              echo "[4/10] formatando particoes"
              ${pkgs.dosfstools}/bin/mkfs.vfat -F32 "$PART1"
              ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F "$PART2"

              echo "[5/10] montando sistema de arquivos"
              ${pkgs.util-linux}/bin/mount "$PART2" /mnt
              ${pkgs.coreutils}/bin/mkdir -p /mnt/boot
              ${pkgs.util-linux}/bin/mount "$PART1" /mnt/boot

              echo "[6/10] gerando hardware-configuration e copiando config do host"
              ${pkgs.nixos-install-tools}/bin/nixos-generate-config --root /mnt
              ${pkgs.coreutils}/bin/cp ${self}/nix/flake.nix /mnt/etc/nixos/flake.nix

              echo "[7/10] gravando network-static.nix (por MAC, nome da iface pode mudar apos reboot)"
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

              echo "[8/10] resolvendo flake.lock offline (via store paths)"
              ${pkgs.nix}/bin/nix flake lock /mnt/etc/nixos \
                --override-input atlaz-os path:${self} \
                --override-input nixpkgs path:${nixpkgs}

              echo "[9/10] instalando NixOS (debug verboso)"
              debug_pre_nixos_install() {
                echo "[debug] ===== $(date -Is) pre-nixos-install ====="
                echo "[debug] INSTALL_IFACE=$INSTALL_IFACE NET_IP=$NET_IP NET_PREFIX=$NET_PREFIX NET_GW=$NET_GW"
                echo "[debug] ip -br addr:"
                ${pkgs.iproute2}/bin/ip -br addr show 2>/dev/null || true
                echo "[debug] ip -4 route:"
                ${pkgs.iproute2}/bin/ip -4 route show 2>/dev/null || true
                echo "[debug] /etc/resolv.conf:"
                ${pkgs.coreutils}/bin/cat /etc/resolv.conf 2>/dev/null || echo "(ausente)"
                echo "[debug] dig cache.nixos.org (resolver padrao):"
                ${pkgs.bind.dnsutils}/bin/dig +short A cache.nixos.org +time=1 +tries=1 2>/dev/null || true
                echo "[debug] findmnt /mnt:"
                ${pkgs.util-linux}/bin/findmnt /mnt 2>/dev/null || true
                echo "[debug] ls -la /mnt/etc/nixos:"
                ${pkgs.coreutils}/bin/ls -la /mnt/etc/nixos 2>/dev/null || true
                echo "[debug] test -f /mnt/etc/nixos/flake.nix:" $(${pkgs.coreutils}/bin/test -f /mnt/etc/nixos/flake.nix && echo sim || echo nao)
                echo "[debug] test -f /mnt/etc/nixos/network-static.nix:" $(${pkgs.coreutils}/bin/test -f /mnt/etc/nixos/network-static.nix && echo sim || echo nao)
                echo "[debug] nix --version:" $(${pkgs.nix}/bin/nix --version 2>/dev/null || echo "?")
                echo "[debug] nix flake metadata /mnt/etc/nixos (curto):"
                { ${pkgs.nix}/bin/nix flake metadata /mnt/etc/nixos 2>&1 | ${pkgs.coreutils}/bin/head -n 30; } || true
                echo "[debug] env NIX_*:"
                ${pkgs.coreutils}/bin/env | ${pkgs.gnugrep}/bin/grep -E '^NIX_' 2>/dev/null || true
                echo "[debug] ===== fim snapshot ====="
              }
              debug_pre_nixos_install

              set -x
              stop_dhcp_stack
              enforce_static_ipv4 "$INSTALL_IFACE"
              restore_resolv_and_nss
              dns_ok_preinstall=0
              for _ in $(seq 1 3); do
                enforce_static_ipv4 "$INSTALL_IFACE"
                if cache_nixos_resolves; then
                  dns_ok_preinstall=1
                  break
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done
              echo "[debug] dns_ok_preinstall=$dns_ok_preinstall"
              if [ "$dns_ok_preinstall" -ne 1 ]; then
                set +x
                debug_pre_nixos_install
                echo "ERRO: cache.nixos.org nao resolve antes do nixos-install (DNS/rede; rede pode ter sido alterada apos particionar)." >&2
                exit 1
              fi
              set +e
              ${pkgs.nixos-install-tools}/bin/nixos-install --root /mnt --flake /mnt/etc/nixos#atlazlog --no-root-passwd --no-channel-copy --show-trace
              ec_install=$?
              set -e
              set +x
              echo "[debug] nixos-install exit code: $ec_install"

              echo "[10/10] removendo flake.lock (proximo rebuild resolve via GitHub)"
              ${pkgs.coreutils}/bin/rm -f /mnt/etc/nixos/flake.lock
              echo "[debug] flake.lock em /mnt removido se existia"
              echo "Instalação finalizada, você por reiniciar a máquina agora"
              [ "$ec_install" -eq 0 ] || exit "$ec_install"
            '';
          };
        })
      ];
    };

  };
}
