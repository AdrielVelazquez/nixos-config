# modules/home-manager/opencode-format.nix
#
# OpenCode's built-in formatter support, with the same formatters Pi runs (modules/home-manager/pi/format.nix)
# converted to OpenCode's in-place `$FILE` contract. Marker-gated formatters (shfmt, biome) are wrapped so they
# skip (exit 1) when their project marker is absent, letting OpenCode try the next matching formatter.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.format;
  jsonFormat = pkgs.formats.json { };

  markerWrapper =
    name: markers: inner:
    pkgs.writeShellScriptBin "opencode-fmt-${name}" ''
      file=$1
      dir=$(CDPATH= cd -- "$(dirname -- "$file")" && pwd)
      while :; do
        for marker in ${lib.concatStringsSep " " markers}; do
          if [ -e "$dir/$marker" ]; then
            exec ${inner} "$file"
          fi
        done
        [ "$dir" = / ] && exit 1
        dir=$(dirname -- "$dir")
      done
    '';

  jqWrapper = pkgs.writeShellScriptBin "opencode-fmt-jq" ''
    set -eu
    file=$1
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    ${lib.getExe pkgs.jq} . "$file" > "$tmp"
    mv "$tmp" "$file"
  '';

  defaults = {
    gofumpt = {
      package = pkgs.gofumpt;
      program = "gofumpt";
      args = [ "-w" ];
      extensions = [ ".go" ];
    };
    jq = {
      package = pkgs.jq;
      wrapper = jqWrapper;
      args = [ ];
      extensions = [ ".json" ];
    };
    nixfmt = {
      package = pkgs.nixfmt;
      program = "nixfmt";
      args = [ ];
      extensions = [ ".nix" ];
    };
    ruff = {
      package = pkgs.ruff;
      program = "ruff";
      args = [ "format" ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    stylua = {
      package = pkgs.stylua;
      program = "stylua";
      args = [ ];
      extensions = [ ".lua" ];
    };
    shfmt = {
      package = pkgs.shfmt;
      program = "shfmt";
      args = [ "-w" ];
      extensions = [
        ".sh"
        ".bash"
      ];
      markers = [ ".editorconfig" ];
    };
    rustfmt = {
      package = pkgs.rustfmt;
      program = "rustfmt";
      args = [ ];
      extensions = [ ".rs" ];
    };
    zig = {
      package = pkgs.zig;
      program = "zig";
      args = [ "fmt" ];
      extensions = [
        ".zig"
        ".zon"
      ];
    };
    tofu = {
      package = pkgs.opentofu;
      program = "tofu";
      args = [ "fmt" ];
      extensions = [
        ".tf"
        ".tfvars"
      ];
    };
    biome = {
      package = pkgs.biome;
      program = "biome";
      args = [ "format" "--write" ];
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
      markers = [
        "biome.json"
        "biome.jsonc"
      ];
    };
  };

  formatterType = lib.types.submodule (
    { name, ... }:
    let
      d = defaults.${name} or { };
    in
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run this formatter for its extensions.";
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = d.package or null;
          description = "Nix package providing the formatter binary.";
        };
        program = lib.mkOption {
          type = lib.types.str;
          default = d.program or "";
          description = "Binary name inside the package.";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = d.args or [ ];
          description = "Arguments before the file path.";
        };
        extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = d.extensions or [ ];
          description = "File extensions (with the leading dot) this formatter handles.";
        };
        markers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = d.markers or [ ];
          description = "If non-empty, only run when one of these files exists above the target file.";
        };
        wrapper = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = d.wrapper or null;
          description = "Custom in-place wrapper for formatters without a direct command (jq).";
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = d.environment or { };
          description = "Environment variables set while the formatter runs.";
        };
      };
    }
  );

  enabled = lib.filterAttrs (_: formatter: formatter.enable) cfg.formatters;
  runnable = lib.filterAttrs (_: formatter: formatter.wrapper != null || (formatter.package != null && formatter.program != "")) enabled;

  markerWrapperFor =
    name: formatter:
    if formatter.markers == [ ] then
      null
    else
      markerWrapper name formatter.markers (
        lib.concatStringsSep " " ([ (lib.escapeShellArg (lib.getExe' formatter.package formatter.program)) ] ++ map lib.escapeShellArg formatter.args)
      );

  render =
    name: formatter:
    let
      direct = lib.getExe' formatter.package formatter.program;
      inner = lib.concatStringsSep " " ([ (lib.escapeShellArg direct) ] ++ map lib.escapeShellArg formatter.args);
      cmd0 =
        if formatter.wrapper != null then
          "${formatter.wrapper}/bin/opencode-fmt-${name}"
        else if formatter.markers != [ ] then
          "${markerWrapper name formatter.markers inner}/bin/opencode-fmt-${name}"
        else
          direct;
    in
    {
      command = [ cmd0 ] ++ (if formatter.wrapper != null || formatter.markers != [ ] then [ ] else formatter.args) ++ [ "$FILE" ];
      inherit (formatter) extensions;
    }
    // lib.optionalAttrs (formatter.environment != { }) { environment = formatter.environment; };

  disabled = builtins.listToAttrs (map (name: lib.nameValuePair name { disabled = true; }) cfg.disabledBuiltins);

  runtimePath = lib.concatLists (
    lib.mapAttrsToList (
      name: formatter:
      if formatter.wrapper != null then
        [ formatter.wrapper ]
      else if formatter.markers != [ ] then
        [ (markerWrapper name formatter.markers (lib.concatStringsSep " " ([ (lib.escapeShellArg (lib.getExe' formatter.package formatter.program)) ] ++ map lib.escapeShellArg formatter.args))) ]
      else
        [ formatter.package ]
    ) runnable
  );
in
{
  options.local.opencode.format = {
    enable = lib.mkEnableOption "OpenCode's built-in formatting of files written or edited by the agent" // {
      default = true;
      example = false;
    };
    formatters = lib.mkOption {
      type = lib.types.attrsOf formatterType;
      default = { };
      description = "Formatters by name. A name OpenCode knows overrides its built-in; a new name adds a formatter.";
    };
    disabledBuiltins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "gofmt"
        "terraform"
      ];
      description = "OpenCode built-in formatters to disable; the explicit formatters above replace them.";
    };
  };

  config = lib.mkMerge [
    { local.opencode.format.formatters = lib.genAttrs (builtins.attrNames defaults) (_: { }); }
    (lib.mkIf (config.local.opencode.enable && cfg.enable) {
      assertions = lib.mapAttrsToList (name: formatter: {
        assertion =
          formatter.wrapper != null || (formatter.package != null && formatter.program != "");
        message = "local.opencode.format.formatters.${name}: an enabled formatter needs a package and a program, or a wrapper";
      }) enabled;

      local.opencode.extraSettings.formatter = (lib.mapAttrs render runnable) // disabled;
      programs.opencode.extraPackages = runtimePath;
    })
  ];
}
