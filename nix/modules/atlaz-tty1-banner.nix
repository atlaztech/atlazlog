{ config, pkgs, lib, ... }:
let
  cfg = config.services.getty;
  issuePath = "/run/console-issue/issue";
  issueDir = "/run/console-issue";

  hasSerialConsole = lib.any (p: lib.hasInfix "console=ttyS0" p) config.boot.kernelParams;

  agettyExe = lib.getExe' pkgs.util-linux "agetty";

  autovtExec = lib.escapeShellArgs [
    agettyExe
    "--login-program"
    (toString cfg.loginProgram)
    "--issue-file"
    issuePath
    "--noclear"
    "tty1"
    "linux"
  ];

  serialExec = "${lib.escapeShellArgs [
    agettyExe
    "--login-program"
    (toString cfg.loginProgram)
    "--issue-file"
    issuePath
    "ttyS0"
    "--keep-baud"
  ]} $TERM";

  genIssue = pkgs.writeShellScript "gen-console-issue.sh" ''
    set -euo pipefail
    DIR=${issueDir}
    mkdir -p "$DIR"
    OUT=${issuePath}

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

  consoleIssueDeps =
    [ "autovt@tty1.service" ]
    ++ lib.optionals hasSerialConsole [ "serial-getty@ttyS0.service" ];
in
lib.mkIf config.console.enable {
  systemd.services.console-issue = {
    description = "Gera issue dinâmico antes do login (tty1 / serial)";
    before = consoleIssueDeps;
    requiredBy = consoleIssueDeps;
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = genIssue;
    };
  };

  systemd.services."autovt@tty1" = {
    after = [ "console-issue.service" ];
    requires = [ "console-issue.service" ];
    serviceConfig.ExecStart = lib.mkForce [
      ""
      autovtExec
    ];
  };

  systemd.services."serial-getty@ttyS0" = lib.mkIf hasSerialConsole {
    after = [ "console-issue.service" ];
    requires = [ "console-issue.service" ];
    serviceConfig.ExecStart = lib.mkForce [
      ""
      serialExec
    ];
  };
}
