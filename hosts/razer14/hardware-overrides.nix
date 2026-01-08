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
      device = "/dev/mapper/luks-02e42960-4936-4e3f-8af3-77e80135dd9f";
      priority = 1;
    }
  ];
}
