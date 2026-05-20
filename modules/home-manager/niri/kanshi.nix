# modules/home-manager/niri/kanshi.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  kanshiCfg = cfg.kanshi;
  # Reapply the wallpaper after outputs change so newly enabled monitors
  # don't keep the solid-color background from the initial session startup.
  wallpaperExec = ''${pkgs.bash}/bin/bash -lc "sleep 0.5; ${pkgs.systemd}/bin/systemctl --user restart swaybg.service"'';
  wallpaperServiceEnabled = cfg.wallpaperService.enable || cfg.awww.enable || cfg.swww.enable;
  addWallpaperExec =
    profileConfig:
    profileConfig
    // {
      profile =
        let
          profile = profileConfig.profile or { };
        in
        profile
        // {
          exec = (profile.exec or [ ]) ++ lib.optional (kanshiCfg.reapplyWallpaper && wallpaperServiceEnabled) wallpaperExec;
        };
    };
in
{
  options.local.niri.kanshi = {
    enable = lib.mkEnableOption "kanshi daemon";
    profiles = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Host-specific Kanshi profiles using the Home Manager services.kanshi.settings shape.";
    };
    reapplyWallpaper = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Append a wallpaper refresh command to each Kanshi profile.";
    };
  };

  config = lib.mkIf (cfg.enable && kanshiCfg.enable && kanshiCfg.profiles != [ ]) {
    services.kanshi = {
      enable = true;
      settings = map addWallpaperExec kanshiCfg.profiles;
    };
  };
}
