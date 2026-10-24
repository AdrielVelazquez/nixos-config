# modules/home-manager/pi/default.nix
#
# The Pi coding agent: `core.nix` owns the wrapper, settings.json, MCP declarations and the `local.pi` option
# surface; every other file is one feature that contributes extensions, tools or role files to it. See README.md
# for the map. The import order is part of the contract: Pi loads extensions in the order the modules
# contribute them, and `checks.pi-format` / `checks.pi-capabilities-contract` fail first if it changes.
{ ... }:

{
  imports = [
    ./headroom.nix
    ./headroom-providers.nix
    ./core.nix
    ./capabilities.nix
    ./ui.nix
    ./lsp.nix
    ./format.nix
    ./dap.nix
    ./hashline.nix
    ./eval.nix
    ./todo.nix
    ./ghost-text.nix
    ./model-roles.nix
    ./stats.nix
    ./llm-platform.nix
    ./routing.nix
    ./workflow.nix
    ./openspec.nix
  ];
}
