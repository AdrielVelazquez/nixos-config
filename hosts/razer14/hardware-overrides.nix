# hosts/razer14/hardware-overrides.nix
{ lib, ... }:

{
  # USB boot support
  boot.initrd.availableKernelModules = [
    "usb_storage"
    "sd_mod"
  ];

  # Reduce disk writes
  fileSystems."/".options = [ "noatime" ];

  # Low priority so zram is preferred
  swapDevices = lib.mkForce [
    {
      device = "/dev/mapper/cryptswap";
      priority = 1;
    }
  ];
}
