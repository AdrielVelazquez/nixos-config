{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.format;
  # Mirrors the conform.nvim set in dotfiles/nvim (gofumpt, jq, nixfmt, ruff, stylua) and adds the
  # languages that have a Pi language server. Every formatter reads the file on stdin and prints the
  # result; `{file}` and `{cargoEdition}` are filled in per call.
  defaults = {
    gofumpt = {
      package = pkgs.gofumpt;
      command = "gofumpt";
      extensions = [ ".go" ];
    };
    jq = {
      package = pkgs.jq;
      command = "jq";
      args = [ "." ];
      extensions = [ ".json" ];
    };
    nixfmt = {
      package = pkgs.nixfmt;
      command = "nixfmt";
      args = [ "--filename={file}" ];
      extensions = [ ".nix" ];
    };
    ruff = {
      package = pkgs.ruff;
      command = "ruff";
      args = [
        "format"
        "--stdin-filename={file}"
        "-"
      ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    stylua = {
      package = pkgs.stylua;
      command = "stylua";
      args = [
        "--stdin-filepath={file}"
        "-"
      ];
      extensions = [ ".lua" ];
    };
    # Defaults indent with tabs: run only where the project says how (.editorconfig).
    shfmt = {
      package = pkgs.shfmt;
      command = "shfmt";
      args = [ "--filename={file}" ];
      extensions = [
        ".sh"
        ".bash"
      ];
      rootMarkers = [ ".editorconfig" ];
      requireRootMarker = true;
    };
    rustfmt = {
      package = pkgs.rustfmt;
      command = "rustfmt";
      args = [
        "--edition={cargoEdition}"
        "--emit=stdout"
      ];
      extensions = [ ".rs" ];
    };
    zig = {
      package = pkgs.zig;
      command = "zig";
      args = [
        "fmt"
        "--stdin"
      ];
      extensions = [
        ".zig"
        ".zon"
      ];
    };
    # OpenTofu's fmt matches `terraform fmt` and is not BUSL-licensed.
    opentofu = {
      package = pkgs.opentofu;
      command = "tofu";
      args = [
        "fmt"
        "-"
      ];
      extensions = [
        ".tf"
        ".tfvars"
      ];
    };
    # Biome's defaults (tabs, double quotes) would rewrite Prettier projects: require its config.
    biome = {
      package = pkgs.biome;
      command = "biome";
      args = [
        "format"
        "--stdin-file-path={file}"
      ];
      extensions = [
        ".ts"
        ".tsx"
        ".mts"
        ".cts"
        ".js"
        ".jsx"
        ".mjs"
        ".cjs"
      ];
      rootMarkers = [
        "biome.json"
        "biome.jsonc"
      ];
      requireRootMarker = true;
    };
  };
  formatterType = lib.types.submodule (
    { name, ... }:
    let
      d = defaults.${name} or { };
      option = type: default: lib.mkOption { inherit type default; };
    in
    {
      options = {
        enable = option lib.types.bool true;
        package = option (lib.types.nullOr lib.types.package) (d.package or null);
        command = option lib.types.str (d.command or "");
        args = option (lib.types.listOf lib.types.str) (d.args or [ ]);
        extensions = option (lib.types.listOf lib.types.str) (d.extensions or [ ]);
        rootMarkers = option (lib.types.listOf lib.types.str) (d.rootMarkers or [ ]);
        requireRootMarker = option lib.types.bool (d.requireRootMarker or false);
      };
    }
  );
  enabled = lib.filterAttrs (_: formatter: formatter.enable) cfg.formatters;
  render = name: formatter: {
    inherit name;
    command =
      if lib.hasPrefix "/" formatter.command then
        formatter.command
      else
        lib.getExe' formatter.package formatter.command;
    inherit (formatter)
      args
      extensions
      rootMarkers
      requireRootMarker
      ;
  };
  entry = pkgs.writeText "pi-format-on-write.ts" ''
    import { createFormatOnWrite } from "${../../../dotfiles/pi/extensions}/format-on-write.ts";
    export default pi => createFormatOnWrite(pi, ${
      builtins.toJSON {
        formatters = lib.mapAttrsToList render enabled;
        inherit (cfg) timeoutMs maxFileBytes maxDiffLines;
        maxOutputBytes = 4 * cfg.maxFileBytes;
      }
    });
  '';
in
{
  options.local.pi.format = {
    enable = lib.mkEnableOption "formatting of files the model writes, with the formatters below" // {
      default = true;
      example = false;
    };
    timeoutMs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5000;
      description = "Deadline for one formatter run; a slower formatter is killed and the file is left as written.";
    };
    maxFileBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1048576;
      description = "Larger files are never formatted.";
    };
    maxDiffLines = lib.mkOption {
      type = lib.types.ints.positive;
      default = 40;
      description = "Diff lines reported to the model after a reformat; the rest is summarised.";
    };
    formatters = lib.mkOption {
      type = lib.types.attrsOf formatterType;
      default = { };
      description = "Formatters by name. Each reads the file on stdin and prints the result; `{file}` and `{cargoEdition}` expand in args.";
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      internal = true;
      default = lib.optionalAttrs cfg.enable { format = "${entry}"; };
    };
  };
  config = lib.mkMerge [
    { local.pi.format.formatters = lib.genAttrs (builtins.attrNames defaults) (_: { }); }
    (lib.mkIf (config.local.pi.enable && cfg.enable) {
      assertions = lib.mapAttrsToList (name: formatter: {
        assertion =
          formatter.command != "" && (formatter.package != null || lib.hasPrefix "/" formatter.command);
        message = "local.pi.format.formatters.${name}: enabled formatters require package and command, or an absolute executable command";
      }) enabled;
      # Load before the LSP extension so its post-edit diagnostics see the formatted file.
      local.pi.extraSettings.extensions = lib.mkOrder 900 [ (toString entry) ];
      # Native build/plan children write files too.
      local.pi.requiredChildExtensions = [
        {
          id = "format-on-write";
          path = toString entry;
        }
      ];
    })
  ];
}
