{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.openspec;
  skillNames = [
    "openspec-propose"
    "openspec-explore"
    "openspec-apply-change"
    "openspec-update-change"
    "openspec-sync-specs"
    "openspec-archive-change"
  ];
  generated = pkgs.runCommand "openspec-agent-files-${pkgs.openspec.version}" { } ''
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export OPENSPEC_TELEMETRY=0
    export CI=true

    ${lib.getExe pkgs.openspec} init "$TMPDIR/clients" \
      --tools opencode --profile core --force --no-animation
    mkdir -p "$out"
    cp -R "$TMPDIR/clients/.agents/skills" "$out/skills"
  '';

in
{
  options.local.openspec.enable = lib.mkEnableOption "OpenSpec for OpenCode";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.openspec ];
    programs.opencode.skills = lib.genAttrs skillNames (name: "${generated}/skills/${name}");
  };
}
