# hosts/razer14/hardware-overrides.nix
# Hardware overrides that won't be affected by nixos-generate-config
{ lib, ... }:

{
  # ============================================================================
  # Initrd Modules
  # ============================================================================
  # Add USB boot support (allows booting from USB rescue drives)
  boot.initrd.availableKernelModules = [
    "usb_storage" # USB flash drives
    "sd_mod" # SCSI disk support (used by USB storage)
  ];

  # ============================================================================
  # Filesystem Optimizations
  # ============================================================================
  # Add noatime to root - reduces disk writes by not updating access times
  fileSystems."/".options = [ "noatime" ];

  # ============================================================================
  # Swap Configuration
  # ============================================================================
  # Override hardware-configuration.nix to set low priority (1)
  # so zram (priority 5) is preferred over disk swap
  swapDevices = lib.mkForce [
    {
      device = "/dev/mapper/luks-cd21de89-443f-44ff-afb5-18fd412dc80c";
      priority = 1;
    }
  ];
}
