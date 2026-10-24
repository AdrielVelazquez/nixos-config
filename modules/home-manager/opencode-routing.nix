{
  lib,
  config,
  ...
}:

let
  cfg = config.local.opencode.routing;
  modelRef = lib.types.strMatching "[^/#]+/[^#]+(#[^#]+)?";
in
{
  options.local.opencode.routing = {
    enable = lib.mkEnableOption "per-agent OpenCode model routing and the scout subagent";

    agents = lib.mkOption {
      type = lib.types.attrsOf modelRef;
      default = { };
      example = {
        plan = "provider/model#xhigh";
        explore = "provider/model#low";
      };
      description = ''
        Model per OpenCode agent as `provider/model` with an optional `#variant`.
        Agents that are not listed inherit the session model. Leave `compaction`
        unrouted: another model cannot reuse the session's warm prompt cache, so it
        re-reads the whole context at the uncached input price.
      '';
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings.agents = lib.recursiveUpdate {
      scout = {
        description = "Researches external documentation, libraries, and repositories on the web without modifying anything.";
        mode = "subagent";
        system = "You are a read-only research scout. Gather facts from documentation, web pages, and referenced repositories. Return findings with source links and say plainly when something could not be verified. Do not modify files or run shell commands.";
        permissions = [
          {
            action = "edit";
            resource = "*";
            effect = "deny";
          }
          {
            action = "shell";
            resource = "*";
            effect = "deny";
          }
        ];
      };
    } (lib.mapAttrs (_: model: { inherit model; }) cfg.agents);
  };
}
