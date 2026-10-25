{
  config,
  lib,
  pkgs,
  piLib,
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
      inherit (piLib) option;
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
    command = piLib.commandOf formatter;
    inherit (formatter)
      args
      extensions
      rootMarkers
      requireRootMarker
      ;
  };
  entry = piLib.mkEntry {
    name = "pi-format-on-write.ts";
    module = "format-on-write";
    factory = "createFormatOnWrite";
    args = {
      formatters = lib.mapAttrsToList render enabled;
      inherit (cfg)
        timeoutMs
        maxFileBytes
        maxDiffLines
        afterBash
        ;
      maxOutputBytes = 4 * cfg.maxFileBytes;
    };
  };
in
{
  options.local.pi.format = {
    enable = piLib.mkFeatureEnable "formatting of files the model writes, with the formatters below";
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
    afterBash = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Also name, and format, the files a successful bash command changed (a heredoc, `sed -i`, a generator); git stamps before and after find them, so it needs a repository and adds one `git status` either side of every command.";
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
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { format = "${entry}"; });
  };
  config = lib.mkMerge [
    { local.pi.format.formatters = lib.genAttrs (builtins.attrNames defaults) (_: { }); }
    (lib.mkIf (config.local.pi.enable && cfg.enable) {
      assertions = piLib.assertRunnable "local.pi.format.formatters" "formatters" enabled;
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
