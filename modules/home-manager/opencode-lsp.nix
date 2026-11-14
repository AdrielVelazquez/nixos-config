# modules/home-manager/opencode-lsp.nix
#
# OpenCode's built-in LSP support, enabled with the same servers Pi runs (modules/home-manager/pi/lsp.nix):
# diagnostics after every edit, in place of Pi's own post-edit pipeline. Commands are absolute store paths;
# each server's runtimeInputs (go, node, shellcheck) reach them through programs.opencode.extraPackages, which
# Home Manager puts on the wrapped binary's PATH.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.lsp;
  jsonFormat = pkgs.formats.json { };

  defaults = {
    gopls = {
      package = pkgs.gopls;
      program = "gopls";
      runtimeInputs = [ pkgs.go ];
      extensions = [ ".go" ];
      env = {
        GOTOOLCHAIN = "local";
        GOTELEMETRY = "off";
        GOPROXY = "off";
        GOSUMDB = "off";
      };
    };
    typescript = {
      package = pkgs.typescript-language-server;
      program = "typescript-language-server";
      args = [ "--stdio" ];
      runtimeInputs = [
        pkgs.nodejs
        pkgs.typescript_5
      ];
      extensions = [
        ".ts"
        ".tsx"
        ".js"
        ".jsx"
        ".mts"
        ".cts"
        ".mjs"
        ".cjs"
      ];
      initialization = {
        disableAutomaticTypingAcquisition = true;
        tsserver.path = "${pkgs.typescript_5}/lib/node_modules/typescript/lib/tsserver.js";
      };
    };
    nixd = {
      package = pkgs.nixd;
      program = "nixd";
      extensions = [ ".nix" ];
    };
    basedpyright = {
      package = pkgs.basedpyright;
      program = "basedpyright-langserver";
      args = [ "--stdio" ];
      runtimeInputs = [ pkgs.nodejs ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    ruff = {
      package = pkgs.ruff;
      program = "ruff";
      args = [ "server" ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    pyrefly = {
      package = pkgs.pyrefly;
      program = "pyrefly";
      args = [ "lsp" ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    bash = {
      package = pkgs.bash-language-server;
      program = "bash-language-server";
      args = [ "start" ];
      runtimeInputs = [
        pkgs.nodejs
        pkgs.shellcheck
      ];
      extensions = [
        ".sh"
        ".bash"
      ];
    };
    rust = {
      package = pkgs.rust-analyzer;
      program = "rust-analyzer";
      extensions = [ ".rs" ];
      env.CARGO_NET_OFFLINE = "true";
    };
    lua-ls = {
      package = pkgs.lua-language-server;
      program = "lua-language-server";
      extensions = [ ".lua" ];
    };
    marksman = {
      package = pkgs.marksman;
      program = "marksman";
      args = [ "server" ];
      extensions = [
        ".md"
        ".markdown"
        ".mdx"
      ];
    };
    json = {
      package = pkgs.vscode-json-languageserver;
      program = "vscode-json-languageserver";
      args = [ "--stdio" ];
      runtimeInputs = [ pkgs.nodejs ];
      extensions = [
        ".json"
        ".jsonc"
      ];
      initialization.handledSchemaProtocols = [ "file" ];
    };
    terraform = {
      package = pkgs.terraform-lsp;
      program = "terraform-lsp";
      extensions = [
        ".tf"
        ".tfvars"
        ".hcl"
      ];
    };
    zls = {
      package = pkgs.zls;
      program = "zls";
      extensions = [
        ".zig"
        ".zon"
      ];
    };
  };

  serverType = lib.types.submodule (
    { name, ... }:
    let
      d = defaults.${name} or { };
    in
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Start this server for its file extensions.";
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = d.package or null;
          description = "Nix package providing the server binary.";
        };
        program = lib.mkOption {
          type = lib.types.str;
          default = d.program or "";
          description = "Binary name inside the package.";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = d.args or [ ];
          description = "Arguments after the binary name.";
        };
        extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = d.extensions or [ ];
          description = "File extensions (with the leading dot) this server handles.";
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = d.env or { };
          description = "Environment variables set while the server runs.";
        };
        initialization = lib.mkOption {
          type = jsonFormat.type;
          default = d.initialization or { };
          description = "LSP initialize options sent at startup.";
        };
        runtimeInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = d.runtimeInputs or [ ];
          description = "Packages the server needs on PATH at runtime.";
        };
      };
    }
  );

  enabled = lib.filterAttrs (_: server: server.enable) cfg.servers;
  runnable = lib.filterAttrs (_: server: server.package != null && server.program != "") enabled;

  render =
    name: server:
    {
      command = [ (lib.getExe' server.package server.program) ] ++ server.args;
      inherit (server) extensions;
    }
    // lib.optionalAttrs (server.env != { }) { inherit (server) env; }
    // lib.optionalAttrs (server.initialization != { }) { inherit (server) initialization; };

  # A `lsp` object keeps OpenCode's built-ins enabled, so every name below is disabled explicitly;
  # the servers above own their file types.
  disabled = builtins.listToAttrs (
    map (name: lib.nameValuePair name { disabled = true; }) cfg.disabledBuiltins
  );

  runtimePath = lib.concatLists (
    lib.mapAttrsToList (_: server: [ server.package ] ++ server.runtimeInputs) runnable
  );
in
{
  options.local.opencode.lsp = {
    enable = lib.mkEnableOption "OpenCode's built-in LSP support with the servers below" // {
      default = true;
      example = false;
    };
    servers = lib.mkOption {
      type = lib.types.attrsOf serverType;
      default = { };
      description = "Language servers by name. A name OpenCode knows overrides its built-in; a new name adds a server.";
    };
    disabledBuiltins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "astro"
        "clangd"
        "clojure-lsp"
        "csharp"
        "dart"
        "deno"
        "elixir-ls"
        "eslint"
        "fsharp"
        "gleam"
        "haskell-language-server"
        "jdtls"
        "julials"
        "kotlin-ls"
        "ocaml-lsp"
        "oxlint"
        "php"
        "prisma"
        "pyright"
        "razor"
        "ruby-lsp"
        "sourcekit-lsp"
        "svelte"
        "tinymist"
        "vue"
        "yaml-ls"
      ];
      description = "OpenCode built-in servers to disable; the explicit servers above replace them.";
    };
  };

  config = lib.mkMerge [
    { local.opencode.lsp.servers = lib.genAttrs (builtins.attrNames defaults) (_: { }); }
    (lib.mkIf (config.local.opencode.enable && cfg.enable) {
      assertions = lib.mapAttrsToList (name: server: {
        assertion = server.package != null && server.program != "";
        message = "local.opencode.lsp.servers.${name}: an enabled server needs a package and a program";
      }) enabled;

      local.opencode.extraSettings.lsp = (lib.mapAttrs render runnable) // disabled;
      programs.opencode.extraPackages = runtimePath;
    })
  ];
}
