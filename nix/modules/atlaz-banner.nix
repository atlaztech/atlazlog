{ pkgs, ... }:
{
  systemd.services = {
    atlaz-login-banner = {
      description = "Generate Atlaz pre-login banner";
      wantedBy = [ "multi-user.target" ];
      before = [
        "getty.target"
        "getty@tty1.service"
        "serial-getty@ttyS0.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "atlaz-login-banner" ''
          set -eu

          issue_dir=/run/issue.d
          issue_file="$issue_dir/10-atlaz.issue"

          mkdir -p "$issue_dir"

          cpu_count="$(${pkgs.coreutils}/bin/nproc)"
          cpu_model="$(${pkgs.gnugrep}/bin/grep -m1 'model name' /proc/cpuinfo | ${pkgs.coreutils}/bin/cut -d: -f2 | ${pkgs.coreutils}/bin/tr -s ' ' | ${pkgs.coreutils}/bin/cut -c2-)"
          cpu_freq="$(${pkgs.gawk}/bin/awk '/^cpu MHz/ { printf "%.2f GHz", $4/1000; exit }' /proc/cpuinfo)"
          mem_total_kb="$(${pkgs.gnugrep}/bin/grep '^MemTotal:' /proc/meminfo | ${pkgs.coreutils}/bin/tr -s ' ' | ${pkgs.coreutils}/bin/cut -d' ' -f2)"
          mem_total_gib="$(${pkgs.gawk}/bin/awk "BEGIN { printf \"%.1f\", ${"$"}mem_total_kb / 1024 / 1024 }")"
          ip_addr="$(${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP 'src \K\S+' || echo 'N/A')"
          gateway="$(${pkgs.iproute2}/bin/ip -4 route show default 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP 'via \K\S+' || echo 'N/A')"

          GREEN=$'\033[32m'
          RESET=$'\033[0m'

          cat > "$issue_file" <<EOF
AtlazOS
CPU: $cpu_model ($cpu_count vCPUs @ $cpu_freq)
RAM: $mem_total_gib GiB
IP: $ip_addr
Gateway: $gateway

Acesse no navegador: ''${GREEN}http://$ip_addr:8000''${RESET}

EOF
        '';
      };
    };

    "serial-getty@ttyS0".serviceConfig.ExecStart = [
      ""
      "${pkgs.util-linux}/bin/agetty --login-program ${pkgs.shadow}/bin/login --keep-baud --noclear --issue-file /etc/issue:/etc/issue.d:/run/issue.d:/usr/lib/issue.d %I 115200,38400,9600 vt220"
    ];
  };
}
