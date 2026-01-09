# hosts/razer14/disko.nix
# Declarative disk partitioning for razer14
# Run with: nix run github:nix-community/disko -- --mode disko --flake .#razer14
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00";
              label = "EFI";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
                extraArgs = [
                  "-n"
                  "RAZER-BOOT"
                ];
              };
            };

            root = {
              priority = 2;
              end = "-104G"; # Leave space for swap (96G) + writeback (8G)
              label = "root";
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  allowDiscards = true;
                };
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = [ "noatime" ];
                  extraArgs = [
                    "-L"
                    "root"
                  ];
                };
              };
            };

            swap = {
              priority = 3;
              size = "96G";
              label = "swap";
              content = {
                type = "luks";
                name = "cryptswap";
                content = {
                  type = "swap";
                  extraArgs = [
                    "-L"
                    "swap"
                  ];
                };
              };
            };

            writeback = {
              priority = 4;
              size = "8G";
              label = "writeback";
              # Raw partition for zram writeback - no filesystem
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = [
                  "-L"
                  "writeback"
                ];
              };
            };
          };
        };
      };
    };
  };
}
