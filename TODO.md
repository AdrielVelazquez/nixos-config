Pinned exceptions to revisit:

- `nixpkgs-kernel-7_0_6` in `flake.nix`: keeps `razer14` on Linux 7.0.6 because Linux 7.0.8/7.0.9 regress the MediaTek Bluetooth adapter with `btmtk: Failed to send wmt func ctrl (-22)`. Recheck upstream kernel/nixpkgs status before removing.
- `nixpkgs-1password` in `flake.nix`: follows `NixOS/nixpkgs/master` for `_1password-gui` so upstream repackages are available before they reach `nixos-unstable`. Recheck the main `nixpkgs` input before removing.
- `nixpkgs-antigravity` in `flake.nix`: pins a nixpkgs commit for `antigravity-cli` while the package is not available in the main pinned `nixpkgs` input. Recheck nixpkgs upstream before removing.
