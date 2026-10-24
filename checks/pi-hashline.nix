{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  fixture =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [
        {
          local.pi.enable = lib.mkForce true;
          local.pi.hashline.enable = lib.mkForce true;
          local.pi.format.enable = lib.mkForce true;
          local.pi.lsp.enable = lib.mkForce true;
          # The writer children also load rtk's extension, which warns on stderr when rtk is not on PATH; `pi-rtk`
          # covers it, and this check asserts a silent stderr.
          local.pi.rtk.enable = lib.mkForce false;
        }
      ];
    }).config;
  entry = fixture.local.pi.hashline.entry;
  roleText =
    name:
    lib.attrByPath [ "${fixture.local.pi.agentDir}/agents/${name}.md" "text" ] "" fixture.home.file;
  hasLine = name: line: lib.elem line (lib.splitString "\n" (roleText name));
  # The writer roles load every writer extension (hashline, rtk, ...) from one comma-separated frontmatter line.
  loadsWriter =
    name:
    lib.any (
      line:
      lib.hasPrefix "subagentOnlyExtensions: " line
      && lib.elem entry (lib.splitString ", " (lib.removePrefix "subagentOnlyExtensions: " line))
    ) (lib.splitString "\n" (roleText name));
  subagents = fixture.local.pi.routing.package;
  subagentsRoot = "${subagents}/${subagents.packageRoot or "node_modules/pi-subagents"}";
  # What `pi-routing.nix` does for the managed policy, for the loopback provider only: the children must load
  # the fixture provider, because their own `extensions: []` list disables every ambient extension.
  childHost = pkgs.writeText "pi-hashline-child-host.ts" ''
    import { requireIntegrations } from "${../dotfiles/pi/extensions/required-integrations.ts}";
    import { registerRequiredChildExtensions } from "${subagentsRoot}/src/api/required-child-extensions.js";
    export default pi => requireIntegrations(pi, registerRequiredChildExtensions,
      [{ id: "fixture-provider", path: process.env.HASHLINE_PROVIDER }]);
  '';
  sessionFixture = pkgs.writeText "pi-hashline-fixture.json" (
    builtins.toJSON {
      hashlineEntry = entry;
      subagentsEntry = "${subagentsRoot}/index.js";
      childHostEntry = "${childHost}";
      roles = lib.genAttrs [ "build" "plan" "explore" ] roleText;
      formatEntry = fixture.local.pi.format.entries.format;
      lspEntry = fixture.local.pi.lsp.entries.lsp;
      settings = fixture.local.pi.extraSettings.lsp;
    }
  );
in
{
  pi-hashline =
    # Interactive session: a plain extension entry, not a required child extension.
    assert lib.elem entry fixture.programs.pi-coding-agent.settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    # Children: only the file-writing roles load it, through their own frontmatter, and keep the empty
    # ambient list; scout, explore and title stay native.
    assert lib.all (name: loadsWriter name && hasLine name "extensions: []") [
      "build"
      "plan"
    ];
    assert lib.all (name: roleText name != "" && !lib.hasInfix "subagentOnlyExtensions" (roleText name))
      [
        "scout"
        "explore"
        "title"
      ];
    pkgs.runCommand "pi-hashline-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME" "$out"
      cd ${../.}
      timeout 600s python3 -E tests/pi/hashline-session.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/session.txt"
    '';
}
