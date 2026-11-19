# modules/home-manager/opencode-ast-grep.nix
#
# ast-grep structural search and rewrite for OpenCode, through the pinned ast-grep MCP server (packages/ast-grep-mcp.nix).
# codemode = false exposes its tools directly (ast-grep_ast_grep_search, _scan, _test, _version) instead of through
# Code Mode. The server finds ast-grep through AST_GREP_BIN, set to nixpkgs' ast-grep so its bundled binary is unused.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.astGrep;
in
{
  options.local.opencode.astGrep = {
    enable =
      lib.mkEnableOption "ast-grep structural search and rewrite for OpenCode through the ast-grep MCP server"
      // {
        default = true;
        example = false;
      };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/ast-grep-mcp.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/ast-grep-mcp.nix { }";
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings.mcp.servers.ast-grep = {
      type = "local";
      command = [ (lib.getExe cfg.package) ];
      codemode = false;
      environment.AST_GREP_BIN = lib.getExe pkgs.ast-grep;
    };
  };
}
