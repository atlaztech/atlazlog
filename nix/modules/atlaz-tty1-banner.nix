{ config, pkgs, lib, ... }:
let
  genIssue = pkgs.writeShellScript "gen-tty1-issue.sh" ''
    set -euo pipefail
    DIR=/run/tty1-issue
    mkdir -p "$DIR"
    OUT="$DIR/issue"

    host=$(hostname -s 2>/dev/null || echo "?")
    cpus=$(nproc 2>/dev/null || echo "?")

    mem_total_kb=0
    mem_avail_kb=0
    read -r _ mem_total_kb _ < <(grep -E '^MemTotal:' /proc/meminfo 2>/dev/null || echo "MemTotal: 0 kB")
    read -r _ mem_avail_kb _ < <(grep -E '^MemAvailable:' /proc/meminfo 2>/dev/null || echo "MemAvailable: 0 kB")
    mt_gib=$(${pkgs.gawk}/bin/awk -v k="$mem_total_kb" 'BEGIN{printf "%.1f", k/1024/1024}')
    ma_gib=$(${pkgs.gawk}/bin/awk -v k="$mem_avail_kb" 'BEGIN{printf "%.1f", k/1024/1024}')
    mu_gib=$(${pkgs.gawk}/bin/awk -v t="$mt_gib" -v a="$ma_gib" 'BEGIN{printf "%.1f", t-a}')

    u_gib="?" f_gib="?" t_gib="?"
    if read -r _ size used avail _ < <(df -BG / 2>/dev/null | tail -1 | tr -s ' '); then
      u_gib=''${used%G}
      f_gib=''${avail%G}
      t_gib=''${size%G}
    fi

    ips_block=$(${pkgs.iproute2}/bin/ip -4 -o addr show 2>/dev/null | ${pkgs.gawk}/bin/awk '
      $2 != "lo" {
        split($4, a, "/");
        printf "  \\e[36m%-8s\\e[0m : %s/%s\n", $2, a[1], a[2];
      }' || true)
    [ -z "$ips_block" ] && ips_block="  \\e[2m(sem IPv4 / rede ainda)\\e[0m\n"

    gw_block=$(${pkgs.iproute2}/bin/ip route show default 2>/dev/null | ${pkgs.gnused}/bin/sed 's/^/  /' || true)
    [ -z "$gw_block" ] && gw_block="  \\e[2m(sem default route)\\e[0m\n"

    bar="--------------------------------------------------"

    {
      printf '\e[1;35m+%s+\e[0m\n' "$bar"
      printf '\e[1;35m|\e[0m \e[1;37m  %s\e[0m\n' "$host"
      printf '\e[1;35m+%s+\e[0m\n' "$bar"
      printf '\e[1;35m|\e[0m \e[33mHostname\e[0m : %s\n' "$host"
      printf '\e[1;35m|\e[0m \e[33mCPU     \e[0m : %s cores\n' "$cpus"
      printf '\e[1;35m|\e[0m \e[33mRAM     \e[0m : %s GiB usada / %s GiB total (%s GiB livre)\n' "$mu_gib" "$mt_gib" "$ma_gib"
      printf '\e[1;35m|\e[0m \e[33mDisco   \e[0m : %s GiB usado / %s GiB livre em /\n' "$u_gib" "$f_gib"
      printf '\e[1;35m+%s+\e[0m\n' "$bar"
      printf '\e[1;35m|\e[0m \e[1;32mIPs\e[0m\n'
      printf '%b' "$ips_block"
      printf '\e[1;35m+%s+\e[0m\n' "$bar"
      printf '\e[1;35m|\e[0m \e[1;32mGateways\e[0m\n'
      printf '%b' "$gw_block"
      printf '\e[1;35m+%s+\e[0m\n' "$bar"
      printf '\n'
    } > "$OUT"
  '';
in
lib.mkIf config.console.enable {
  systemd.services.tty1-issue = {
    description = "Gera /run/tty1-issue/issue antes do login no tty1";
    before = [ "autovt@tty1.service" ];
    requiredBy = [ "autovt@tty1.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = genIssue;
    };
  };

  # NixOS usa autovt@tty1, não getty@tty1, para consoles virtuais.
  systemd.services."autovt@tty1" = {
    after = [ "tty1-issue.service" ];
    requires = [ "tty1-issue.service" ];
    serviceConfig.ExecStart = lib.mkForce [
      ""
      "${lib.getExe' pkgs.util-linux "agetty"}"
      "--login-program"
      config.services.getty.loginProgram
      "--issue-file"
      "/run/tty1-issue/issue"
      "--noclear"
      "tty1"
      "linux"
    ];
  };
}
