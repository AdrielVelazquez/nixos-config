{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.dap;
  json = pkgs.formats.json { };
  pythonWithDebugpy = pkgs.python3.withPackages (python: [ python.debugpy ]);
  tcp = {
    type = "tcp";
    host = "127.0.0.1";
    port = 0;
  };
  # Debug adapters come from Nix by store path. The package has no adapter discovery or installer.
  # Languages mirror the editor setup: Go (delve, as nvim-dap-go), Dart (the SDK's own adapter, which
  # the Neovim environment already installs), plus Python, Node/TypeScript and native Rust/Zig/C.
  defaults = {
    delve = {
      package = pkgs.delve;
      command = "dlv";
      args = [
        "dap"
        "--listen=127.0.0.1:$PORT"
      ];
      transport = tcp;
      runtimeInputs = [ pkgs.go ];
      environment = {
        GOTOOLCHAIN = "local";
        GOTELEMETRY = "off";
      };
    };
    debugpy = {
      package = pythonWithDebugpy;
      command = "python";
      args = [
        "-m"
        "debugpy.adapter"
      ];
      transport = "stdio";
    };
    js-debug = {
      package = pkgs.vscode-js-debug;
      command = "js-debug";
      args = [
        "$PORT"
        "127.0.0.1"
      ];
      transport = tcp;
    };
    gdb = {
      package = pkgs.gdb;
      command = "gdb";
      args = [
        "--quiet"
        "--interpreter=dap"
      ];
      transport = "stdio";
    };
    dart = {
      package = pkgs.dart;
      command = "dart";
      args = [ "debug_adapter" ];
      transport = "stdio";
    };
  };
  profileDefaults = {
    go = {
      adapter = "delve";
      arguments = {
        request = "launch";
        mode = "debug";
      };
    };
    python = {
      adapter = "debugpy";
      arguments = {
        type = "python";
        request = "launch";
        console = "internalConsole";
        justMyCode = false;
      };
    };
    node = {
      adapter = "js-debug";
      arguments = {
        type = "pwa-node";
        console = "internalConsole";
      };
    };
    native = {
      adapter = "gdb";
      arguments = { };
    };
    dart = {
      adapter = "dart";
      arguments = {
        type = "dart";
      };
    };
  };
  adapterType = lib.types.submodule (
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
        transport = option json.type (d.transport or "stdio");
        runtimeInputs = option (lib.types.listOf lib.types.package) (d.runtimeInputs or [ ]);
        environment = option (lib.types.attrsOf (lib.types.nullOr lib.types.str)) (d.environment or { });
      };
    }
  );
  profileType = lib.types.submodule (
    { name, ... }:
    let
      d = profileDefaults.${name} or { };
    in
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        adapter = lib.mkOption {
          type = lib.types.str;
          default = d.adapter or "";
        };
        arguments = lib.mkOption {
          type = json.type;
          default = d.arguments or { };
        };
      };
    }
  );
  enabledAdapters = lib.filterAttrs (_: adapter: adapter.enable) cfg.adapters;
  enabledProfiles = lib.filterAttrs (_: profile: profile.enable) cfg.profiles;
  render =
    name: adapter:
    let
      executable =
        if lib.hasPrefix "/" adapter.command then
          adapter.command
        else
          lib.getExe' adapter.package adapter.command;
      wrapped = pkgs.writeShellScript "pi-dap-${name}" ''
        export PATH=${lib.makeBinPath adapter.runtimeInputs}:"$PATH"
        exec ${lib.escapeShellArg executable} "$@"
      '';
    in
    {
      command = if adapter.runtimeInputs == [ ] then executable else "${wrapped}";
      inherit (adapter) args transport environment;
    };
in
{
  options.local.pi.dap = {
    enable = lib.mkEnableOption "debug adapter sessions for the interactive Pi session" // {
      default = true;
      example = false;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../packages/pi-dap.nix { };
    };
    timeouts = lib.mkOption {
      type = json.type;
      default = {
        startupMs = 30000;
        requestMs = 30000;
        executionMs = 30000;
        shutdownMs = 5000;
      };
    };
    adapters = lib.mkOption {
      type = lib.types.attrsOf adapterType;
      default = { };
    };
    profiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = { };
    };
    entry = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = "${cfg.package}/${cfg.package.packageRoot}/src/index.ts";
    };
  };
  config = lib.mkMerge [
    {
      local.pi.dap.adapters = lib.genAttrs (builtins.attrNames defaults) (_: { });
      local.pi.dap.profiles = lib.genAttrs (builtins.attrNames profileDefaults) (_: { });
    }
    (lib.mkIf (config.local.pi.enable && cfg.enable) {
      assertions =
        lib.mapAttrsToList (name: adapter: {
          assertion = adapter.command != "" && (adapter.package != null || lib.hasPrefix "/" adapter.command);
          message = "local.pi.dap.adapters.${name}: enabled adapters require package and command, or an absolute executable command";
        }) enabledAdapters
        ++ lib.mapAttrsToList (name: profile: {
          assertion = enabledAdapters ? ${profile.adapter};
          message = "local.pi.dap.profiles.${name}: adapter `${profile.adapter}` is not an enabled local.pi.dap adapter";
        }) enabledProfiles;
      # Interactive session only: debugging runs program code, so the entry is deliberately not a required
      # child extension and native children never get dap_* tools.
      local.pi.extraSettings = {
        extensions = [ cfg.entry ];
        dap = {
          inherit (cfg) timeouts;
          adapters = lib.mapAttrs render enabledAdapters;
          profiles = lib.mapAttrs (_: profile: { inherit (profile) adapter arguments; }) enabledProfiles;
        };
      };
    })
  ];
}
