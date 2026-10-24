{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.lsp;
  json = pkgs.formats.json { };
  language = extensions: languageId: { inherit extensions languageId; };
  python = [ (language [ ".py" ".pyi" ] "python") ];
  defaults = {
    gopls = {
      package = pkgs.gopls;
      command = "gopls";
      runtimeInputs = [ pkgs.go ];
      languages = [
        (language [ ".go" ] "go")
        (language [ ".mod" ] "go.mod")
        (language [ ".sum" ] "go.sum")
      ];
      rootMarkers = [
        "go.mod"
        "go.work"
        "go.sum"
      ];
      environment = {
        GOTOOLCHAIN = "local";
        GOTELEMETRY = "off";
        GOPROXY = "off";
        GOSUMDB = "off";
      };
      settings.gopls = {
        analyses = {
          unusedparams = true;
          fieldalignment = true;
          inferTypeArgs = true;
        };
        hints = lib.genAttrs [
          "assignVariableTypes"
          "compositeLiteralFields"
          "compositeLiteralTypes"
          "constantValues"
          "functionTypeParameters"
          "parameterNames"
          "rangeVariableTypes"
        ] (_: true);
        staticcheck = true;
        gofumpt = true;
        semanticTokens = true;
      };
    };
    typescript = {
      package = pkgs.typescript-language-server;
      command = "typescript-language-server";
      args = [ "--stdio" ];
      languages = [
        (language [ ".ts" ".mts" ".cts" ] "typescript")
        (language [ ".tsx" ] "typescriptreact")
        (language [ ".js" ".mjs" ".cjs" ] "javascript")
        (language [ ".jsx" ] "javascriptreact")
      ];
      rootMarkers = [
        "tsconfig.json"
        "jsconfig.json"
        "package.json"
      ];
      initializationOptions = {
        disableAutomaticTypingAcquisition = true;
        tsserver.path = "${pkgs.typescript_5}/lib/node_modules/typescript/lib/tsserver.js";
      };
    };
    nixd = {
      package = pkgs.nixd;
      command = "nixd";
      languages = [ (language [ ".nix" ] "nix") ];
      rootMarkers = [
        "flake.nix"
        ".git"
      ];
    };
    basedpyright = {
      package = pkgs.basedpyright;
      command = "basedpyright-langserver";
      args = [ "--stdio" ];
      languages = python;
      rootMarkers = [
        "pyproject.toml"
        "setup.py"
        "setup.cfg"
        "requirements.txt"
        "Pipfile"
        "pyrightconfig.json"
        ".git"
      ];
      settings.basedpyright.analysis = {
        autoSearchPaths = true;
        useLibraryCodeForTypes = true;
        diagnosticMode = "openFilesOnly";
      };
    };
    ruff = {
      package = pkgs.ruff;
      command = "ruff";
      args = [ "server" ];
      languages = python;
      rootMarkers = [
        "pyproject.toml"
        "ruff.toml"
        ".ruff.toml"
        ".git"
      ];
    };
    pyrefly = {
      package = pkgs.pyrefly;
      command = "pyrefly";
      args = [ "lsp" ];
      languages = python;
      rootMarkers = [
        "pyrefly.toml"
        "pyproject.toml"
        "setup.py"
        "setup.cfg"
        "requirements.txt"
        "Pipfile"
        ".git"
        "poetry.toml"
      ];
    };
    bash = {
      package = pkgs.bash-language-server;
      command = "bash-language-server";
      args = [ "start" ];
      runtimeInputs = [ pkgs.shellcheck ];
      languages = [ (language [ ".sh" ".bash" ] "shellscript") ];
      rootMarkers = [ ".git" ];
    };
    rust = {
      package = pkgs.rust-analyzer;
      command = "rust-analyzer";
      environment.CARGO_NET_OFFLINE = "true";
      languages = [ (language [ ".rs" ] "rust") ];
      rootMarkers = [
        "Cargo.toml"
        "rust-project.json"
      ];
    };
    lua = {
      package = pkgs.lua-language-server;
      command = "lua-language-server";
      languages = [ (language [ ".lua" ] "lua") ];
      rootMarkers = [
        ".luarc.json"
        ".luarc.jsonc"
      ];
    };
    marksman = {
      package = pkgs.marksman;
      command = "marksman";
      args = [ "server" ];
      languages = [ (language [ ".md" ".markdown" ".mdx" ] "markdown") ];
      rootMarkers = [
        ".marksman.toml"
        ".git"
      ];
    };
    json = {
      package = pkgs.vscode-json-languageserver;
      command = "vscode-json-languageserver";
      args = [ "--stdio" ];
      initializationOptions.handledSchemaProtocols = [ "file" ];
      settings.json.validate.enable = true;
      languages = [
        (language [ ".json" ] "json")
        (language [ ".jsonc" ] "jsonc")
      ];
      rootMarkers = [ ".git" ];
    };
    terraform = {
      package = pkgs.terraform-lsp;
      command = "terraform-lsp";
      languages = [
        (language [ ".tf" ".tfvars" ] "terraform")
        (language [ ".hcl" ] "hcl")
      ];
      rootMarkers = [
        ".terraform"
        ".git"
      ];
    };
    zls = {
      package = pkgs.zls;
      command = "zls";
      languages = [ (language [ ".zig" ".zon" ] "zig") ];
      rootMarkers = [
        "build.zig"
        "build.zig.zon"
        ".git"
      ];
    };
  };
  serverType = lib.types.submodule (
    { name, ... }:
    let
      d = defaults.${name} or { };
      inherit (piLib) option;
    in
    {
      options = {
        enable = option lib.types.bool true;
        package = option (lib.types.nullOr lib.types.package) (d.package or null);
        command = option lib.types.str (d.command or "");
        args = option (lib.types.listOf lib.types.str) (d.args or [ ]);
        languages = option (lib.types.listOf (
          lib.types.submodule {
            options = {
              extensions = option (lib.types.listOf lib.types.str) [ ];
              languageId = option lib.types.str "";
            };
          }
        )) (d.languages or [ ]);
        rootMarkers = option (lib.types.listOf lib.types.str) (d.rootMarkers or [ ]);
        requireRootMarker = option lib.types.bool false;
        initializationOptions = option json.type (d.initializationOptions or { });
        settings = option json.type (d.settings or { });
        environment = option (lib.types.attrsOf (lib.types.nullOr lib.types.str)) (d.environment or { });
        runtimeInputs = option (lib.types.listOf lib.types.package) (d.runtimeInputs or [ ]);
      };
    }
  );
  enabled = lib.filterAttrs (_: server: server.enable) cfg.servers;
  render = name: server: {
    command = piLib.withRuntimeInputs "pi-lsp-${name}" server;
    inherit (server)
      args
      languages
      rootMarkers
      requireRootMarker
      initializationOptions
      settings
      environment
      ;
  };
  entry = pkgs.writeText "pi-lsp.ts" ''
    import { createLspStatus } from "${piLib.extensionPath "lsp-status"}";
    import upstream from "${cfg.package}/${cfg.package.packageRoot}/src/index.ts";
    export default pi => createLspStatus(pi, upstream, { enabled: ${builtins.toJSON cfg.status.enable} });
  '';
in
{
  options.local.pi.lsp = {
    enable = piLib.mkFeatureEnable "managed language servers and fresh post-edit diagnostics";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../packages/pi-lsp.nix { };
    };
    status.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    servers = lib.mkOption {
      type = lib.types.attrsOf serverType;
      default = { };
    };
    timeouts = lib.mkOption {
      type = json.type;
      default = {
        initializeMs = 45000;
        requestMs = 10000;
        workspaceRequestMs = 15000;
        diagnosticsMs = 15000;
        shutdownMs = 5000;
      };
    };
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { lsp = "${entry}"; });
  };
  config = lib.mkMerge [
    { local.pi.lsp.servers = lib.genAttrs (builtins.attrNames defaults) (_: { }); }
    (lib.mkIf (config.local.pi.enable && cfg.enable) {
      assertions = piLib.assertRunnable "local.pi.lsp.servers" "servers" enabled;
      local.pi.extraSettings = {
        extensions = [ "${entry}" ];
        lsp = {
          includeHintDiagnostics = false;
          inherit (cfg) timeouts;
          servers = lib.mapAttrs render enabled;
        };
      };
    })
  ];
}
