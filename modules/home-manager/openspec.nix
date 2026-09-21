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
  workflows = [
    "propose"
    "explore"
    "apply"
    "update"
    "sync"
    "archive"
  ];
  generated = pkgs.runCommand "openspec-agent-files-${pkgs.openspec.version}" { } ''
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export OPENSPEC_TELEMETRY=0
    export CI=true

    ${lib.getExe pkgs.openspec} init "$TMPDIR/clients" \
      --tools codex,opencode,gemini,cursor --profile core --force --no-animation
    # Antigravity CLI exposes skills as commands. Use upstream's skills-only
    # template so its handoffs refer to /openspec-* rather than IDE workflows.
    ${lib.getExe pkgs.openspec} init "$TMPDIR/antigravity" \
      --tools agents --profile core --force --no-animation

    mkdir -p "$out/clients" "$out/antigravity"
    cp -R "$TMPDIR/clients/"{.agents,.opencode,.gemini,.cursor} "$out/clients/"
    cp -R "$TMPDIR/antigravity/.agents" "$out/antigravity/"
  '';
  skillRoots = {
    ".codex/skills" = "clients/.agents/skills";
    ".config/opencode/skills" = "clients/.opencode/skills";
    ".gemini/skills" = "clients/.gemini/skills";
    ".gemini/antigravity-cli/skills" = "antigravity/.agents/skills";
    ".cursor/skills" = "clients/.cursor/skills";
  };
  skillFiles = lib.concatMap (
    root:
    map (name: {
      name = "${root}/${name}";
      value = {
        source = "${generated}/${skillRoots.${root}}/${name}";
        recursive = true;
      };
    }) skillNames
  ) (lib.attrNames skillRoots);
  commandFiles = lib.concatMap (workflow: [
    {
      name = ".config/opencode/commands/opsx-${workflow}.md";
      value.source = "${generated}/clients/.opencode/commands/opsx-${workflow}.md";
    }
    {
      name = ".gemini/commands/opsx/${workflow}.toml";
      value.source = "${generated}/clients/.gemini/commands/opsx/${workflow}.toml";
    }
    {
      name = ".cursor/commands/opsx-${workflow}.md";
      value.source = "${generated}/clients/.cursor/commands/opsx-${workflow}.md";
    }
  ]) workflows;
in
{
  options.local.openspec.enable = lib.mkEnableOption "OpenSpec for the configured coding agents";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.openspec ];
    home.file = lib.listToAttrs (skillFiles ++ commandFiles);
  };
}
