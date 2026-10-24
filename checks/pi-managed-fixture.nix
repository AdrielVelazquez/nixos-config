# The Framework Pi configuration with its network-bound integrations removed, plus the exact files
# the switch installs, for checks that run real Pi in the Nix sandbox.
{
  lib,
  pkgs,
  homeConfigurations,
}:
let
  fixture =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [
        {
          local.pi.llmPlatform.enable = lib.mkForce false;
          # Roles default to llmPlatform.enable; this fixture routes through its own fixture models.
          local.pi.modelRoles.enable = lib.mkForce true;
          local.headroom.pi.enable = lib.mkForce false;
          local.tuios.integrations.pi.enable = lib.mkForce false;
          local.pi.modelRoles.roles = lib.mkForce {
            default = "fixture/primary:high";
            smol = "fixture/small:low";
            slow = "fixture/strong:high";
            plan = "fixture/strong:high";
            commit = "fixture/small:low";
            memory = "fixture/small:low";
            widget = "fixture/small:low";
            tiny = "fixture/tiny:off";
            task = "fixture/primary:high";
            advisor = "fixture/strong:high";
            vision = "fixture/vision:high";
          };
        }
      ];
    }).config;
  agentPrefix = "${fixture.local.pi.agentDir}/";
  installer = pkgs.callPackage ../packages/pi-install-settings.nix { };
in
{
  inherit fixture;
  contract = pkgs.writeText "pi-managed-fixture.json" (
    builtins.toJSON {
      # settings.json is installed by the switch from this exact generated file; every other
      # managed file is a store symlink.
      settingsFile = toString fixture.home.file."${agentPrefix}settings.json".source;
      installer = lib.getExe installer;
      files = lib.mapAttrs' (
        name: file: lib.nameValuePair (lib.removePrefix agentPrefix name) (toString file.source)
      ) (lib.filterAttrs (name: file: file.enable && lib.hasPrefix agentPrefix name) fixture.home.file);
      enabled = {
        ui = fixture.local.pi.ui.enable;
        lsp = fixture.local.pi.lsp.enable;
        ghostText = fixture.local.pi.ghostText.enable;
        modelRoles = fixture.local.pi.modelRoles.enable;
        ast = fixture.local.pi.capabilities.ast.enable;
        web = fixture.local.pi.capabilities.web.enable;
        stats = fixture.local.pi.stats.enable;
      };
    }
  );
}
