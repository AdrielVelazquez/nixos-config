{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.capabilities;
  json = pkgs.formats.json { };
  root = package: "${package}/${package.packageRoot}";
  visualEntry = pkgs.writeText "pi-visuals.ts" ''
    import { installVisuals } from "${../../dotfiles/pi/extensions/visuals.ts}";
    import zentui from "${root cfg.editor.package}/extensions/zentui/index.ts";
    export default pi => installVisuals(pi, zentui);
  '';
  astConfig = pkgs.writeText "pi-ast-grep-config.yml" "ruleDirs: []\n";
  astEntry = pkgs.writeText "pi-readonly-ast.ts" ''
    import { installReadOnlyAst } from "${../../dotfiles/pi/extensions/ast-readonly.ts}";
    import { createAstGrepTools } from "${root cfg.ast.package}/src/tools.ts";
    export default pi => installReadOnlyAst(pi, createAstGrepTools, "${lib.getExe pkgs.ast-grep}", "${astConfig}");
  '';
  webPolicy = {
    webSearch.enabled = false;
    commands = lib.genAttrs [ "websearch" "curator" "google-account" "search" ] (_: {
      enabled = false;
    });
    toolActivation = "eager";
    fetch = {
      defaultMode = "readable";
      allowedModes = [
        "readable"
        "raw"
      ];
    };
    fetchRouting = {
      providers = [ "http" ];
      allowRemoteHostedProviders = false;
    };
    fetchContent.redirects = "same-origin";
    pdf = {
      enabled = false;
      provider = "unpdf";
    };
    video.enabled = false;
    image.enabled = false;
    youtube.enabled = false;
    githubClone.enabled = false;
    githubPrIssue.enabled = false;
    allowBrowserCookies = false;
    authFetch = { };
    ssrf = {
      allowRanges = [ ];
      trustEnvProxy = false;
    };
    workflow = "none";
    autoOpenBrowser = false;
    maxInlineContentChars = 10000;
  };
  webEntry = pkgs.writeText "pi-fetch-only.ts" ''
    import { installFetchOnly } from "${../../dotfiles/pi/extensions/web-fetch.ts}";
    import upstream from "${root cfg.web.package}/dist/index.js";
    export default pi => installFetchOnly(pi, upstream, ${builtins.toJSON webPolicy});
  '';
  entries =
    lib.optionalAttrs cfg.editor.enable {
      editor = "${visualEntry}";
    }
    // lib.optionalAttrs cfg.ast.enable { ast = "${astEntry}"; }
    // lib.optionalAttrs cfg.web.enable { web = "${webEntry}"; };
in
{
  options.local.pi.capabilities = {
    editor = {
      enable = lib.mkEnableOption "the managed OpenCode-style theme and Zentui visual layer";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../packages/pi-zentui.nix { };
      };
    };
    ast = {
      enable = lib.mkEnableOption "read-only structural search with pinned ast-grep";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../packages/pi-ast-grep.nix { };
      };
    };
    web = {
      enable = lib.mkEnableOption "deterministic public-page fetch and retrieval only";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../packages/pi-web-fetch.nix { };
      };
      policy = lib.mkOption {
        type = json.type;
        readOnly = true;
        internal = true;
        default = webPolicy;
      };
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      internal = true;
      default = entries;
    };
  };
  config = lib.mkIf config.local.pi.enable (
    lib.mkMerge [
      { local.pi.extraSettings.extensions = builtins.attrValues entries; }
      (lib.mkIf cfg.editor.enable {
        local.pi.extraSettings = {
          theme = "managed-opencode";
          quietStartup = "header";
          themes = [ "${../../dotfiles/pi/themes/managed-opencode.json}" ];
        };
        home.file."${config.local.pi.agentDir}/zentui.json".source = json.generate "pi-zentui.json" {
          projectRefreshIntervalMs = 0;
          icons.mode = "ascii";
          components = {
            editor = {
              enabled = true;
              style = "opencode";
              colorSource = "theme";
              codexQuota = false;
              styles.opencode = {
                completionMenu = "native";
                metadataFormat = "$model  $provider(  $thinking)";
              };
            };
            userMessages = {
              enabled = true;
              style = "framed-copy-friendly";
              colorSource = "theme";
            };
            selectorBorders.enabled = false;
            toolDisplay = {
              enabled = true;
              style = "balanced";
              registerToolOverrides = lib.genAttrs [
                "read"
                "write"
                "edit"
                "bash"
                "grep"
                "find"
                "ls"
              ] (_: true);
              builtinRendererOverrides = { };
              customToolOverrides = { };
              previewLines = 6;
              diffViewMode = "auto";
            };
            thinkingSteps.enabled = false;
            workingLine = {
              enabled = false;
              turnSummary = false;
            };
            footer = {
              style = "native";
              codexQuota = false;
            };
            extensionStatuses = {
              defaultVisibility = "show";
              visibility = { };
            };
          };
        };
      })
      (lib.mkIf cfg.ast.enable {
        home.packages = [ pkgs.ast-grep ];
        local.pi.requiredChildExtensions = [
          {
            id = "readonly-ast";
            path = entries.ast;
          }
        ];
      })
      (lib.mkIf cfg.web.enable {
        home.file."${config.local.pi.agentDir}/web-search.json".source =
          json.generate "pi-web-search.json" webPolicy;
        local.pi.requiredChildExtensions = [
          {
            id = "fetch-only";
            path = entries.web;
          }
        ];
      })
    ]
  );
}
