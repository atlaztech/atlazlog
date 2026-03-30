{ ... }:
{
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      efiInstallAsRemovable = true;
    };
    # Nomes de iface estaveis (eth0/eth1) em VM; network-static.nix casa por MAC.
    kernelParams = [ "console=ttyS0,115200" "net.ifnames=0" "biosdevname=0" ];
    kernel.sysctl."vm.overcommit_memory" = 1;
  };

  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];
}
