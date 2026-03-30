{ ... }:
{
  services = {
    resolved.enable = true;
    openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };
  };
}
