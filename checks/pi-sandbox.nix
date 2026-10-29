{
  lib,
  pkgs,
  homeConfigurations,
  razerHome,
  ...
}:
let
  base = homeConfigurations.cachyos-framework13;
  off =
    (base.extendModules {
      modules = [ { local.pi.sandbox.enable = lib.mkForce false; } ];
    }).config;
  on =
    (base.extendModules {
      modules = [ { local.pi.sandbox.enable = lib.mkForce true; } ];
    }).config;
  sandbox = on.local.pi.sandbox;
  guestArgs = {
    inherit lib pkgs;
    managedFiles = { };
    homeDirectory = "/home/fixture";
    agentDirectory = "/home/fixture/.pi/agent";
    piPackage = pkgs.hello;
    runtimePackages = [
      pkgs.bash
      pkgs.coreutils
    ];
  };
  originalRoot = import ../packages/pi-sandbox-guest.nix guestArgs;
  changedRoot = import ../packages/pi-sandbox-guest.nix (
    guestArgs
    // {
      pkgs = pkgs // {
        writeTextDir = name: text: pkgs.writeTextDir name (text + "\n# changed root fixture\n");
      };
    }
  );
in
{
  pi-sandbox =
    assert lib.assertMsg (
      originalRoot.imagePackage.drvPath != changedRoot.imagePackage.drvPath
      && originalRoot.imageTag != changedRoot.imageTag
    ) "Root-filesystem-only changes must invalidate the sandbox image cache";
    assert lib.assertMsg (
      !razerHome.local.pi.sandbox.enable
    ) "Razer must not enable the experimental sandbox";
    assert lib.assertMsg (
      off.local.pi.sandbox.launcherPackage == null
    ) "Disabled sandbox must install no launcher";
    assert lib.assertMsg (
      toString off.programs.pi-coding-agent.package == toString on.programs.pi-coding-agent.package
    ) "Sandbox must not replace ordinary Pi";
    assert lib.assertMsg (
      off.programs.pi-coding-agent.settings == on.programs.pi-coding-agent.settings
    ) "Sandbox must not mutate host settings";
    assert lib.assertMsg (
      sandbox.secretBindings == { }
    ) "Host credentials must not be forwarded by default";
    assert lib.assertMsg (
      sandbox.networkPolicy == "public" && sandbox.ports == [ ]
    ) "Host/private networking must not be opened implicitly";
    assert lib.assertMsg (
      builtins.hasAttr "settings.json" sandbox.guestFiles
      && builtins.hasAttr "mcp.json" sandbox.guestFiles
      && builtins.hasAttr "agents/build.md" sandbox.guestFiles
    ) "Managed settings, MCP and native agents must reach the guest";
    assert lib.assertMsg (
      !(builtins.hasAttr "auth.json" sandbox.guestFiles)
      && !(builtins.hasAttr "mcp-auth.json" sandbox.guestFiles)
      && !(builtins.hasAttr "extensions/tuios-agent-state.ts" sandbox.guestFiles)
      && !(builtins.hasAttr "extensions/tuios-outcomes.ts" sandbox.guestFiles)
    ) "Guest must not import host credentials or Tuios control";
    pkgs.runCommand "pi-sandbox-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export PI_SANDBOX_TEST_SOURCE=${../packages/pi-sandbox.py}
        python3 -B ${../tests/pi/sandbox.py}
        export PI_SANDBOX_GUEST_TEST_SOURCE=${../packages/pi-sandbox-guest.py}
        python3 -B ${../tests/pi/sandbox-guest.py}
        touch "$out"
      '';
  pi-sandbox-image =
    pkgs.runCommand "pi-sandbox-image-check" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 - ${sandbox.imagePackage} <<'PY'
        import json
        import sys
        import tarfile
        with tarfile.open(sys.argv[1], mode="r:") as archive:
            manifest = json.load(archive.extractfile("manifest.json"))
            config = json.load(archive.extractfile(manifest[0]["Config"]))
            assert config["config"]["WorkingDir"] == "/workspace"
            assert config["config"]["Entrypoint"] == []
            has_env = False
            for layer in manifest[0]["Layers"]:
                with tarfile.open(fileobj=archive.extractfile(layer), mode="r:") as filesystem:
                    has_env = has_env or any(name.removeprefix("./") == "usr/bin/env" for name in filesystem.getnames())
            assert has_env, "Project shebangs require /usr/bin/env in the guest root"
        PY
        touch "$out"
      '';
}
