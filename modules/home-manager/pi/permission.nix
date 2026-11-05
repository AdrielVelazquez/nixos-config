# modules/home-manager/pi/permission.nix
#
# Permission boundary for the interactive session and every native child: @gotgenes/pi-permission-system, pinned in
# packages/pi-permission-system.nix. It is a decision layer, not a sandbox. It loads before rtk (settings.json order),
# so allow and deny patterns match the command as the model typed it, not rtk's rewrite.
{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.permission;
  json = pkgs.formats.json { };
  root = "${cfg.package}/${cfg.package.passthru.packageRoot}";
  entry = pkgs.writeText "pi-permission-system.ts" ''
    export { default } from "${root}/src/index.ts";
  '';
  policy = {
    permission = {
      # Unknown or unlisted tools ask, so a new extension tool cannot run silently.
      "*" = "ask";
      path = {
        "*" = "allow";
        "*.env" = "deny";
        "*.env.*" = "deny";
        "*.env.example" = "allow";
        "~/.ssh/*" = "deny";
        "~/.gnupg/*" = "deny";
      };
      read = "allow";
      grep = "allow";
      find = "allow";
      ls = "allow";
      write = "allow";
      edit = "allow";
      bash = {
        "*" = "ask";
        "git status*" = "allow";
        "git diff*" = "allow";
        "git log*" = "allow";
        "git show*" = "allow";
        "rtk git status*" = "allow";
        "rtk git diff*" = "allow";
        "rtk git log*" = "allow";
        "rtk ls*" = "allow";
        "rtk read*" = "allow";
        "rtk grep*" = "allow";
        "rtk find*" = "allow";
        "rtk err*" = "allow";
        "ls*" = "allow";
        "cat *" = "allow";
        "head *" = "allow";
        "tail *" = "allow";
        "wc *" = "allow";
        "rg *" = "allow";
        "grep *" = "allow";
        "find *" = "allow";
        "pwd" = "allow";
        "nix eval*" = "allow";
        "nix build*" = "allow";
        "nix flake check*" = "allow";
        "nix flake show*" = "allow";
        "nix flake metadata*" = "allow";
        "nix flake lock --update-input*" = "allow";
        "npm test*" = "allow";
        "go test*" = "allow";
        "cargo test*" = "allow";
        "pytest*" = "allow";
        "rm -rf *" = "deny";
        "sudo *" = "deny";
        "cd *" = "allow";
        "sed -n *" = "allow";
        "echo *" = "allow";
        "git ls-files*" = "allow";
        "git rev-parse*" = "allow";
        "llmp model list*" = "allow";
        "rtk proxy git*" = "allow";
        "rtk proxy ls*" = "allow";
      };
      eval = "allow";
      codemode = "allow";
      subagent = "allow";
      todo = "allow";
      question = "allow";
      web_search = "allow";
      fetch_content = "allow";
      get_search_content = "allow";
      skill = "allow";
      bg_status = "allow";
      external_directory = {
        "*" = "ask";
        "/tmp/*" = "allow";
        "/nix/store/*" = "allow";
      };
      external_directory_read = {
        "*" = "ask";
        "/tmp/*" = "allow";
        "/home/adriel/src/*" = "allow";
      };
      mcp = {
        "*" = "ask";
        mcp_status = "allow";
        mcp_list = "allow";
      };
    };
  };
in
{
  options.local.pi.permission = {
    enable = piLib.mkFeatureEnable "deny-preserving allow/ask/deny gate over tools, bash, paths and external directories";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../packages/pi-permission-system.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../packages/pi-permission-system.nix { }";
    };
    policy = lib.mkOption {
      type = json.type;
      readOnly = true;
      internal = true;
      default = policy;
    };
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    local.pi.extraSettings.extensions = [ "${entry}" ];
    local.pi.requiredChildExtensions = [
      {
        id = "permission-system";
        path = "${entry}";
      }
    ];
    home.file."${config.local.pi.agentDir}/extensions/pi-permission-system/config.json" = {
      source = json.generate "pi-permission-system-config.json" policy;
      force = true;
    };
  };
}
