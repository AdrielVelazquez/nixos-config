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
  studioDisplayCriteria = "Apple Computer Inc StudioDisplay *";
  studioDisplayOutput = {
    criteria = studioDisplayCriteria;
    status = "enable";
    scale = kanshiCfg.studioDisplayScale;
  };
  mkIgnoredStudioDisplayOutput = criteria: {
    inherit criteria;
    status = "disable";
  };
  mkCompanionStudioDisplayOutput = criteria: {
    inherit criteria;
    status = "enable";
    scale = kanshiCfg.defaultExternalScale;
  };
  studioDisplayOptionalOutputs =
    map mkIgnoredStudioDisplayOutput kanshiCfg.studioDisplayIgnoredOutputCriteria
    ++ map mkCompanionStudioDisplayOutput kanshiCfg.studioDisplayCompanionOutputCriteria;
  outputCombinations =
    outputs:
    if outputs == [ ] then
      [ [ ] ]
    else
      let
        first = lib.head outputs;
        rest = outputCombinations (lib.tail outputs);
      in
      rest ++ map (outputSet: [ first ] ++ outputSet) rest;
  isWildcardOutput = output: (output.criteria or null) == "*";
  isStudioDisplayOutput = output: (output.criteria or null) == studioDisplayCriteria;
  hasWildcardOutput = outputs: lib.any isWildcardOutput outputs;
  hasStudioDisplayOutput = outputs: lib.any isStudioDisplayOutput outputs;
  addStudioDisplayProfiles =
    profileConfig:
    let
      profile = profileConfig.profile or { };
      outputs = profile.outputs or [ ];
      namedOutputs = lib.filter (output: !isWildcardOutput output) outputs;
      profileName = profile.name or "profile";
      mkStudioDisplayProfile =
        index: extraOutputs:
        profileConfig
        // {
          profile = profile // {
            name =
              if extraOutputs == [ ] then
                "${profileName}-studio-display"
              else
                "${profileName}-studio-display-known-${toString index}";
            outputs = namedOutputs ++ [ studioDisplayOutput ] ++ extraOutputs;
          };
        };
    in
    if
      kanshiCfg.studioDisplayScale != null
      && profileConfig ? profile
      && hasWildcardOutput outputs
      && !hasStudioDisplayOutput outputs
    then
      (lib.imap0 mkStudioDisplayProfile (outputCombinations studioDisplayOptionalOutputs))
      ++ [ profileConfig ]
    else
      [ profileConfig ];
  expandedProfiles = lib.concatMap addStudioDisplayProfiles kanshiCfg.profiles;
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
          exec =
            (profile.exec or [ ])
            ++ lib.optional (kanshiCfg.reapplyWallpaper && wallpaperServiceEnabled) wallpaperExec;
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
    defaultExternalScale = lib.mkOption {
      type = lib.types.float;
      default = 1.2;
      description = "Scale for generic wildcard external outputs in generated Kanshi profiles.";
    };
    studioDisplayScale = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = 1.0;
      description = "Scale to apply to Apple Studio Display outputs when expanding wildcard Kanshi profiles. Set to null to disable.";
    };
    studioDisplayIgnoredOutputCriteria = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Unknown Unknown Unknown" ];
      description = "Output criteria to disable when present with an Apple Studio Display.";
    };
    studioDisplayCompanionOutputCriteria = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Dell Inc* *" ];
      description = "Known companion display criteria to enable at the default external scale when present with an Apple Studio Display.";
    };
  };

  config = lib.mkIf (cfg.enable && kanshiCfg.enable && kanshiCfg.profiles != [ ]) {
    services.kanshi = {
      enable = true;
      settings = map addWallpaperExec expandedProfiles;
    };
  };
}
