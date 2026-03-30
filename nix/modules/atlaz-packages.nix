{ pkgs, ... }:
let
  net-snmp-atlaz = pkgs.runCommand "net-snmp-atlaz" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p "$out"
    cp -rs ${pkgs.net-snmp}/* "$out/"
    chmod -R u+w "$out"
    for cmd in snmpget snmpwalk snmpbulkget snmpbulkwalk; do
      rm -f "$out/bin/$cmd"
      makeWrapper ${pkgs.net-snmp}/bin/$cmd "$out/bin/$cmd" \
        --add-flags "-OQn -Ih -t 3 -r 3"
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    net-snmp-atlaz
    tcpdump
    wget
    curl
    wireshark-cli
  ];
}
