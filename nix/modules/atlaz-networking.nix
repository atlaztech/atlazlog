{ lib, ... }:
{
  networking = {
    hostName = "atlaz";
    useDHCP = lib.mkDefault false;
    useNetworkd = true;
    nameservers = [ "208.67.222.222" "208.67.220.220" ];
    firewall = {
      allowedTCPPorts = [ 8000 ];
      allowedUDPPorts = [ 2055 ];
    };
    wg-quick.interfaces.wg0 = {
      autostart = true;
      configFile = "/var/lib/atlaz/wg0.conf";
    };
  };
}
