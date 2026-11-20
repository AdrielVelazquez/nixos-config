{ lib, pkgs, ... }:

{
  imports = [ ../adriel-work ];
  home.packages = [ pkgs.codex ];

  local.pi.modelRoles = {
    roles = lib.mapAttrs (_: lib.mkOverride 90) {
      task = "llm-platform/gpt-6.2-sol:medium";
      advisor = "llm-platform/gpt-6.2-sol:high";
      vision = "llm-platform/gpt-6.2-sol:high";
    };
    taskAgents.reviewer = "llm-platform/gpt-6.2-sol:high";
  };

  local.niri.useSystemHyprlock = true;
}
