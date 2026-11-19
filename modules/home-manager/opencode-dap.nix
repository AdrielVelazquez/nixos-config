# modules/home-manager/opencode-dap.nix
#
# Debugging for OpenCode through the pinned mcp-dap server (packages/mcp-dap.nix): dap_debug_launch, _set_breakpoints,
# _continue, _step_over, _step_into, _step_out, _get_stack_trace, _get_variables, _evaluate and _disconnect, among others.
# codemode = false exposes the tools directly. The Python adapter (debugpy) is the only one wired here; the server's Go,
# Rust and Java adapters need their own binaries on the server's PATH and are not configured.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.dap;
in
{
  options.local.opencode.dap = {
    enable = lib.mkEnableOption "debugging for OpenCode through the mcp-dap server" // {
      default = true;
      example = false;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/mcp-dap.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/mcp-dap.nix { }";
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings.mcp.servers.dap = {
      type = "local";
      command = [ (lib.getExe cfg.package) ];
      codemode = false;
    };
  };
}
