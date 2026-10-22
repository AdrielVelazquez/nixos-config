{
  config,
  lib,
  pkgs,
  ...
}:
let
  generated = pkgs.runCommand "openspec-pi-files-${pkgs.openspec.version}" { } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export OPENSPEC_TELEMETRY=0
    export CI=true
    mkdir -p "$HOME"
    ${lib.getExe pkgs.openspec} init "$TMPDIR/client" --tools pi --profile core --force --no-animation
    mkdir -p "$out"
    cp -R "$TMPDIR/client/.pi/"{skills,prompts} "$out/"
  '';
in
{
  options.local.pi.openspec.enable = lib.mkEnableOption "OpenSpec skills and prompt commands for Pi";
  config = lib.mkIf (config.local.pi.enable && config.local.pi.openspec.enable) {
    home.packages = [ pkgs.openspec ];
    local.pi.extraSettings = {
      skills = [ "${generated}/skills" ];
      prompts = [ "${generated}/prompts" ];
    };
  };
}
