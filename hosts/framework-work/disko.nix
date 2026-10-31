{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      # Replace only after checking the target disk from the NixOS installer.
      device = lib.mkDefault "/dev/disk/by-id/REPLACE-WITH-FRAMEWORK-INSTALL-DISK";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            priority = 2;
            size = "100%";
            content = {
              type = "luks";
              name = "cryptframework";
              settings.allowDiscards = true;
              content = {
                type = "lvm_pv";
                vg = "framework";
              };
            };
          };
        };
      };
    };
    lvm_vg.framework = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "80G";
          content = {
            type = "swap";
            resumeDevice = true;
            priority = 1;
          };
        };
        root = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
