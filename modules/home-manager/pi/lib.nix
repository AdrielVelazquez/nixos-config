# modules/home-manager/pi/lib.nix
#
# Helpers the Pi modules share: the first-party extension directory, the entry modules that bind an
# extension to its Nix-generated configuration, and the option shapes every feature repeats.
#
# Use as `piLib = import ./lib.nix { inherit lib pkgs; };`.
{ lib, pkgs }:
let
  # Interpolated as a whole directory, never as a single file: a store path made from one file drops the
  # sibling modules it imports (docs/solutions/integration-issues/nix-single-file-path-interpolation-drops-sibling-imports-in-pi-extension-entries.md).
  extensions = ../../../dotfiles/pi/extensions;
in
rec {
  # Path of a first-party extension (`dotfiles/pi/extensions/<module>.ts`) as a string, ready for settings.json
  # or for an `import` inside an entry module.
  extensionPath = module: "${extensions}/${module}.ts";

  # The entry module Pi loads for a feature that needs configuration: it imports the extension's factory and
  # calls it with `args`, which is serialised as JSON.
  mkEntry =
    {
      name,
      module,
      factory,
      args,
    }:
    pkgs.writeText name ''
      import { ${factory} } from "${extensionPath module}";
      export default pi => ${factory}(pi, ${builtins.toJSON args});
    '';

  # The entry module of a feature whose extension needs no configuration.
  mkReexport =
    { name, module }:
    pkgs.writeText name ''
      export { default } from "${extensionPath module}";
    '';

  # `enable` of a standalone feature: on whenever Pi is, off only where a host opts out.
  mkFeatureEnable =
    description:
    lib.mkEnableOption description
    // {
      default = true;
      example = false;
    };

  # Read-only attribute set of the entry points a feature installs, for checks and for other modules.
  mkEntriesOption =
    default:
    lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      internal = true;
      inherit default;
    };

  # `option type default`: the plain `mkOption` every tool submodule spells out for each field.
  option = type: default: lib.mkOption { inherit type default; };

  # What runs for a tool: an absolute `command` as given, else `command` from its Nix `package`.
  commandOf =
    tool:
    if lib.hasPrefix "/" tool.command then
      tool.command
    else if tool.package != null then
      lib.getExe' tool.package tool.command
    else
      tool.command;

  # The same command, started with the tool's `runtimeInputs` on PATH when it has any.
  withRuntimeInputs =
    name: tool:
    if tool.runtimeInputs == [ ] then
      commandOf tool
    else
      toString (
        pkgs.writeShellScript name ''
          export PATH=${lib.makeBinPath tool.runtimeInputs}:"$PATH"
          exec ${lib.escapeShellArg (commandOf tool)} "$@"
        ''
      );

  # One assertion per enabled tool that names neither a package nor an absolute command.
  assertRunnable =
    optionPath: noun: tools:
    lib.mapAttrsToList (name: tool: {
      assertion = tool.command != "" && (tool.package != null || lib.hasPrefix "/" tool.command);
      message = "${optionPath}.${name}: enabled ${noun} require a package and a command, or an absolute executable command";
    }) tools;
}
