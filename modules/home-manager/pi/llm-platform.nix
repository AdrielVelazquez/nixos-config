{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.llmPlatform;
  input =
    if cfg.package == null then
      throw "Select a pinned Pi Reddit provider source before enabling local.pi.llmPlatform"
    else
      cfg.package;
  source = lib.cleanSourceWith {
    src = input;
    name = "pi-reddit-provider-source";
    filter =
      path: _type:
      let
        root = toString input;
        relative = lib.removePrefix "${root}/" (toString path);
      in
      toString path == root
      || relative == "package.json"
      || lib.any (prefix: relative == prefix || lib.hasPrefix "${prefix}/" relative) [
        "src"
        "extensions"
      ];
  };
  entry = pkgs.writeText "pi-managed-llm-platform.ts" ''
    import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
    import { readConfig } from "../src/config.ts";
    import { registerExtension } from "../src/extension.ts";
    import { withLlmPlatformProxy } from "${piLib.extensionPath "headroom-llm-platform"}";
    export default async function (pi: ExtensionAPI): Promise<void> {
      const config = await readConfig({ diagnostic: code => console.error(`LLM Platform: ''${code}`) });
      return withLlmPlatformProxy(${
        builtins.toJSON (
          config.local.headroom.pi.enable && config.local.headroom.pi.providers.llm-platform.enable
        )
      },
        () => registerExtension(pi, config));
    }
  '';
  package = pkgs.runCommand "pi-reddit-provider" { } ''
    # Old provider revisions silently ignore proxy configuration. Refuse them
    # before they can become an apparently Headroom-enabled installation.
    test -f ${source}/src/inference-proxy.ts
    test -f ${source}/src/reddit-ui.ts
    mkdir -p "$out"
    cp -R ${source}/. "$out/"
    chmod u+w "$out/extensions"
    cp --remove-destination ${entry} "$out/extensions/llm-platform.ts"
  '';
in
{
  options.local.pi.llmPlatform = {
    enable = lib.mkEnableOption "Reddit's Pi provider and Tool Registry hub";
    package = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.package);
      default = null;
      description = "Complete pinned provider source, normally a non-flake Git input; never a runtime installer.";
    };
    runtimePackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if config.local.pi.enable && cfg.enable then package else null;
      readOnly = true;
      internal = true;
      description = "Filtered, immutable provider package installed into Pi.";
    };
    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "gpt-6.1-sol";
      description = "Model ID within llm-platform; null leaves native provider selection unchanged.";
    };
    upstreamOrigin = lib.mkOption {
      type = lib.types.strMatching "https://[a-zA-Z0-9.-]+(:[0-9]+)?";
      default = "https://llm-platform.snooguts.net";
      description = "Headroom allowlist origin, not an override of the provider's trusted production root.";
    };
    cli = {
      enable = lib.mkEnableOption "the existing llmp CLI alongside Pi";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../../packages/llmp.nix { };
        description = "LLM Platform CLI; private Go sources/credentials remain runtime-only.";
      };
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    home.packages = lib.optionals cfg.cli.enable [ cfg.cli.package ];
    local.pi.extraSettings = {
      packages = [ "${package}" ];
      defaultProvider = "llm-platform";
    }
    // lib.optionalAttrs (cfg.defaultModel != null) { defaultModel = cfg.defaultModel; };
    local.pi.requiredChildExtensions = [
      {
        id = "reddit-provider";
        path = "${package}/extensions/llm-platform.ts";
      }
    ];
  };
}
