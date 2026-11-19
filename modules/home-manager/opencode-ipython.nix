# modules/home-manager/opencode-ipython.nix
#
# Persistent Python for OpenCode through the pinned ipython-mcp server (packages/ipython-mcp.nix): ipython_execute keeps
# variables between calls within a named session, and ipython_list_sessions, ipython_reset, ipython_interrupt and
# ipython_shutdown manage the sessions. codemode = false exposes the tools directly. Sessions run with the server's own
# interpreter (env = None), which has ipykernel, so no other environment is configured here.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.ipython;
in
{
  options.local.opencode.ipython = {
    enable =
      lib.mkEnableOption "a persistent Python kernel for OpenCode through the ipython-mcp server"
      // {
        default = true;
        example = false;
      };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/ipython-mcp.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/ipython-mcp.nix { }";
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings.mcp.servers.ipython = {
      type = "local";
      command = [ (lib.getExe cfg.package) ];
      codemode = false;
    };
  };
}
