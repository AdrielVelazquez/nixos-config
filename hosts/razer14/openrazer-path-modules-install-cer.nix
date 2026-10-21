# hosts/razer14/openrazer-path-modules-install-cer.nix
#
# Temporary local port of nixpkgs PR #576293 (merged to master as
# 965f876a780c1fad7f14b9f817e093e40ea5d5e5, not yet in nixos-unstable).
#
# Since nixpkgs PR #571181, `aggregateModules` concatenates a `<module>.ko.cer`
# certificate for every external kernel module. openrazer installed its .ko files
# with a hand-written `cp`, so no .cer files existed and the
# `linux-*-modules` derivation failed with
# `cat: kernel/drivers/hid/razerkbd.ko.cer: No such file or directory`.
# Installing through the kernel's `modules_install` makes it generate them.
#
# Remove this file (and its import) once nixos-unstable contains 965f876.
# Tracking: nixpkgs issue #575192, see TODO.md.
{
  config,
  pkgs,
  ...
}:
{
  hardware.openrazer.packages.kernel = config.boot.kernelPackages.openrazer.overrideAttrs (old: {
    makeFlags = old.makeFlags ++ [
      "INSTALL_MOD_PATH=${placeholder "out"}"
      "INSTALL_MOD_DIR=kernel/drivers/hid"
      "INSTALL_MOD_STRIP=1"
      "DEPMOD=true"
    ];

    installTargets = [ "modules_install" ];

    installFlags = [
      "-C"
      "${config.boot.kernelPackages.kernel.dev}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/build"
      "M=$(PWD)/driver"
    ];

    # The default installPhase runs `make install` with installTargets/installFlags.
    installPhase = null;

    postInstall = ''
      RAZER_MOUNT_OUT="$out/bin/razer_mount"
      RAZER_RULES_OUT="$out/etc/udev/rules.d/99-razer.rules"
      install -m 644 -v -D install_files/udev/99-razer.rules $RAZER_RULES_OUT
      install -m 755 -v -D install_files/udev/razer_mount $RAZER_MOUNT_OUT
      substituteInPlace $RAZER_RULES_OUT \
        --replace razer_mount $RAZER_MOUNT_OUT \
        --replace plugdev openrazer
      substituteInPlace $RAZER_MOUNT_OUT \
        --replace /usr/bin/logger ${pkgs.util-linux}/bin/logger \
        --replace chgrp ${pkgs.coreutils}/bin/chgrp \
        --replace "PATH='/sbin:/bin:/usr/sbin:/usr/bin'" "" \
        --replace plugdev openrazer
    '';
  });
}
