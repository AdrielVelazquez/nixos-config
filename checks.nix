# checks.nix
{
  inputs,
  lib,
  pkgs,
  system,
  src,
  nixosConfigurations,
  homeConfigurations,
  systemConfigs,
}:

let
  nixosOutputNames = builtins.attrNames nixosConfigurations;
  homeOutputNames = builtins.attrNames homeConfigurations;
  systemOutputNames = builtins.attrNames systemConfigs;
  sharedSubstituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://cuda-maintainers.cachix.org"
  ];
  sharedTrustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUPT9qbgf2oDZA7A3nU2X8="
  ];
  hasSharedSubstituters =
    settings: lib.all (substituter: builtins.elem substituter settings.substituters) sharedSubstituters;
  hasSharedTrustedPublicKeys =
    settings:
    lib.all (publicKey: builtins.elem publicKey settings.trusted-public-keys) sharedTrustedPublicKeys;
  hasNoNiriCache =
    settings:
    lib.all (substituter: !(lib.hasInfix "niri" substituter)) settings.substituters
    && lib.all (publicKey: !(lib.hasPrefix "niri" publicKey)) settings.trusted-public-keys;
  frameworkSystem = systemConfigs.cachyos-framework13.config;
  frameworkHomeOutput = homeConfigurations.cachyos-framework13;
  frameworkHome = frameworkHomeOutput.config;
  frameworkHomeFiles = frameworkHome.home.file;
  frameworkPortalPackages = map toString frameworkHome.xdg.portal.extraPortals;
  frameworkGraphics = frameworkSystem.system-graphics;
  razerSystemOutput = nixosConfigurations.razer14;
  razerSystem = razerSystemOutput.config;
  razerSysctl = razerSystem.boot.kernel.sysctl;
  razerHome = razerSystem.home-manager.users.adriel;
  razerHomeFiles = razerHome.home.file;
  niriUpstream = lib.attrByPath [ "packages" system "niri" ] null inputs.niri;
  nativeNiri = home: lib.attrByPath [ "wayland" "windowManager" "niri" ] { } home;
  razerNativeNiri = nativeNiri razerHome;
  frameworkNativeNiri = nativeNiri frameworkHome;
  enabledHomeNiriProfiles = [
    razerNativeNiri
    frameworkNativeNiri
  ];
  homeNiriUsesUpstream =
    niri: (niri.package or null) != null && toString niri.package == toString niriUpstream;
  homeNiriOwnsOnlyConfig =
    niri:
    (niri.checkConfig or false)
    && !(lib.attrByPath [ "systemd" "enable" ] true niri)
    && (niri.portalPackage or null) == null
    && (niri.xwaylandSatellitePackage or null) == null;
  integratedGpuEnv = {
    DRI_PRIME = "0";
    __NV_PRIME_RENDER_OFFLOAD = "0";
    __GLX_VENDOR_LIBRARY_NAME = "mesa";
    __VK_LAYER_NV_optimus = "non_NVIDIA_only";
  };
  hasNoIntegratedGpuSessionVariables =
    homeConfig:
    lib.all (name: !(builtins.hasAttr name homeConfig.home.sessionVariables)) (
      builtins.attrNames integratedGpuEnv
    );
  packagesNamed =
    pname: packages: builtins.filter (package: (package.pname or null) == pname) packages;
  hasExistingRecursiveHomeFile =
    files: target:
    builtins.hasAttr target files
    && files.${target}.recursive
    && builtins.pathExists files.${target}.source;
  linuxAiSkillRoots = [
    ".gemini/antigravity-cli/skills"
    ".gemini/skills"
    ".config/opencode/skills"
  ];
  compoundSkillRoot = "${inputs.compound-engineering}/skills";
  compoundSkillNames = lib.filter (
    name: builtins.pathExists "${compoundSkillRoot}/${name}/SKILL.md"
  ) (lib.attrNames (builtins.readDir compoundSkillRoot));
  hasPinnedCompoundSkills =
    files: root:
    let
      expected = map (name: "${root}/${name}") compoundSkillNames;
      actual = lib.filter (
        name: (name == root || lib.hasPrefix "${root}/" name) && !(lib.hasPrefix "${root}/openspec-" name)
      ) (builtins.attrNames files);
    in
    actual == expected
    && lib.all (
      name:
      hasExistingRecursiveHomeFile files "${root}/${name}"
      && toString files."${root}/${name}".source == "${compoundSkillRoot}/${name}"
    ) compoundSkillNames;
  openspecSkillNames = [
    "openspec-propose"
    "openspec-explore"
    "openspec-apply-change"
    "openspec-update-change"
    "openspec-sync-specs"
    "openspec-archive-change"
  ];
  openspecSkillRoots = linuxAiSkillRoots ++ [
    ".codex/skills"
    ".cursor/skills"
  ];
  openspecFiles =
    files:
    lib.filterAttrs (
      name: _:
      lib.any (root: lib.hasPrefix "${root}/openspec-" name) openspecSkillRoots
      || lib.hasPrefix ".config/opencode/commands/opsx-" name
      || lib.hasPrefix ".gemini/commands/opsx/" name
      || lib.hasPrefix ".cursor/commands/opsx-" name
    ) files;
  frameworkSystemDocker = packagesNamed "docker" frameworkSystem.environment.systemPackages;
  frameworkSystemSteam = packagesNamed "steam" frameworkSystem.environment.systemPackages;
  frameworkHomeDocker = packagesNamed "docker" frameworkHome.home.packages;
  frameworkHomeSteam = packagesNamed "steam" frameworkHome.home.packages;
  frameworkHeadroom = packagesNamed "headroom-ai" frameworkHome.home.packages;
  razerHeadroom = packagesNamed "headroom-ai" razerHome.home.packages;
  headroomPackage = if frameworkHeadroom == [ ] then null else builtins.head frameworkHeadroom;
  razerHeadroomPackage = if razerHeadroom == [ ] then null else builtins.head razerHeadroom;
  frameworkOpencode = builtins.head (packagesNamed "opencode" frameworkHome.home.packages);
  # Test the actual provider release configured for the host, including discovery
  # and refresh, rather than substituting a simplified registry plugin.
  llmPlatformPlugin = pkgs.fetchzip {
    name = "opencode-llm-platform-v2-0.1.1";
    url = lib.removePrefix "@reddit/opencode-llm-platform-v2@" frameworkHome.local.opencode.llmPlatform.plugin;
    hash = "sha256-Tc4erOdzMRbda77Z9qddmQDgAiTbpQa6FC6QB2ALUU8=";
  };
  headroomFixedPortModule = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ./modules/home-manager/headroom.nix
      (
        { lib, ... }:
        {
          options.home.packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };
          config.local.headroom = {
            enable = true;
            codexWsCompressionTimeoutSeconds = 12;
            wrapDefaults = {
              memory = true;
              codeGraph = true;
              port = 48789;
            };
          };
        }
      )
    ];
  };
  headroomFixedPortPackage = builtins.head headroomFixedPortModule.config.home.packages;
  headroomManagedOpencodeConfig = pkgs.writeText "headroom-managed-opencode.json" (
    builtins.toJSON {
      sentinel = "home-manager";
      mcp.servers.serena = {
        type = "local";
        command = [
          "uvx"
          "serena"
        ];
        disabled = false;
      };
    }
  );
  headroomFakeOpencode = pkgs.writeShellScriptBin "opencode" ''
    set -eu

    test "$HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS" = "''${HEADROOM_TEST_EXPECT_WS_TIMEOUT:-30}"
    test "$HEADROOM_OPENCODE_WRAPPED" = 1
    test "$1" = --standalone
    test "$(command -v opencode)" = "$HEADROOM_OPENCODE_REAL_BIN"
    test -n "''${OPENCODE_CONFIG:-}"
    test "$OPENCODE_CONFIG" != "$HOME/.config/opencode/opencode.json"
    test -w "$OPENCODE_CONFIG"
    case "$OPENCODE_CONFIG" in
      "$XDG_RUNTIME_DIR"/headroom-opencode.*/opencode.json) ;;
      *) exit 1 ;;
    esac
    test "$(${pkgs.coreutils}/bin/stat -c '%a' "$OPENCODE_CONFIG")" = 600
    ${pkgs.python3.interpreter} -c \
      'import fastapi, h2, httpx, magika, mcp, onnxruntime, openai, orjson, sqlite_vec, transformers, uvicorn, watchdog, websockets, zstandard'
    if [ "''${HEADROOM_TEST_EXPECT_PROXY_FEATURES:-0}" = 1 ]; then
      ${pkgs.python3.interpreter} -c 'import json, os, urllib.request; payload = json.load(urllib.request.urlopen("http://127.0.0.1:%s/health" % os.environ["HEADROOM_TEST_PORT"], timeout=2)); assert payload["config"]["memory"] is True, payload; assert payload["config"]["code_graph"] is True, payload'
    fi
    ${pkgs.jq}/bin/jq -e --arg baseURL "http://127.0.0.1:$HEADROOM_TEST_PORT/v1" '
      .sentinel == "home-manager"
      and .mcp.servers.headroom.type == "local"
      and .providers.headroom.settings.baseURL == $baseURL
      and (has("provider") | not)
    ' "$OPENCODE_CONFIG"
    if [ "''${HEADROOM_TEST_EXPECT_SERENA:-0}" = 1 ]; then
      command -v uvx >/dev/null
      ${pkgs.jq}/bin/jq -e '.mcp.servers.serena.command[0] == "uvx"' "$OPENCODE_CONFIG"
    else
      ${pkgs.jq}/bin/jq -e '.mcp.servers.serena.disabled == true' "$OPENCODE_CONFIG"
    fi
    ${pkgs.jq}/bin/jq -e --arg baseURL "http://127.0.0.1:$HEADROOM_TEST_PORT/v1" '
      .mcp.servers.headroom.type == "local"
      and .providers.headroom.settings.baseURL == $baseURL
      and (has("plugin") | not)
      and (has("provider") | not)
    ' <<EOF
    $OPENCODE_CONFIG_CONTENT
    EOF
    ${pkgs.coreutils}/bin/printf '%s\n' "$OPENCODE_CONFIG" > "$HEADROOM_TEST_CONFIG_CAPTURE"
  '';
  headroomFakeCodex = pkgs.writeShellScriptBin "codex" ''
    set -eu

    test "$HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS" = "''${HEADROOM_TEST_EXPECT_WS_TIMEOUT:-30}"
    if [ "''${HEADROOM_TEST_EXPECT_PROXY_FEATURES:-0}" = 1 ]; then
      ${pkgs.python3.interpreter} -c 'import json, os, urllib.request; payload = json.load(urllib.request.urlopen("http://127.0.0.1:%s/health" % os.environ["HEADROOM_TEST_PORT"], timeout=2)); assert payload["config"]["memory"] is True, payload; assert payload["config"]["code_graph"] is True, payload'
    fi
    ${pkgs.coreutils}/bin/printf '%s\n' "$OPENAI_BASE_URL" >> "$HEADROOM_TEST_CODEX_CAPTURE"
    if [ -n "''${HEADROOM_TEST_CODEX_RELEASE_FILE:-}" ]; then
      while [ ! -e "$HEADROOM_TEST_CODEX_RELEASE_FILE" ]; do
        ${pkgs.coreutils}/bin/sleep 0.1
      done
    fi
  '';
  razerLlama = packagesNamed "llama-cpp" razerHome.home.packages;
  cudaArchitectureFlags =
    package:
    builtins.filter (flag: lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" flag) (package.cmakeFlags or [ ]);
  targetsOnlySm120 =
    package: cudaArchitectureFlags package == [ "-DCMAKE_CUDA_ARCHITECTURES:STRING=120" ];
  waybarAudio = razerHome.programs.waybar.settings.mainBar.pulseaudio;

  frameworkServices = frameworkSystem.systemd.services;
  frameworkTimers = frameworkSystem.systemd.timers;
  frameworkGcService = frameworkServices.nix-gc or { };
  frameworkOptimiseService = frameworkServices.nix-optimise or { };
  frameworkGcTimer = frameworkTimers.nix-gc or { };
  frameworkOptimiseTimer = frameworkTimers.nix-optimise or { };
  isIdleMaintenanceService =
    service:
    lib.attrByPath [ "serviceConfig" "Type" ] null service == "oneshot"
    && lib.attrByPath [ "serviceConfig" "Nice" ] null service == 19
    && lib.attrByPath [ "serviceConfig" "CPUSchedulingPolicy" ] null service == "idle"
    && lib.attrByPath [ "serviceConfig" "IOSchedulingClass" ] null service == "idle";
  frameworkAssertions = frameworkSystem.system-manager.preActivationAssertions;
  falconDropIn =
    frameworkSystem.environment.etc."systemd/system/falcon-sensor.service.d/50-resource-limits.conf".text;
  orbitDropIn =
    frameworkSystem.environment.etc."systemd/system/orbit.service.d/50-resource-limits.conf".text;
  duoDropIn =
    frameworkSystem.environment.etc."systemd/system/duo-desktop.service.d/50-resource-limits.conf".text;
  greetdConfig = frameworkSystem.environment.etc."greetd/config.toml".text;
  greetdUnit = frameworkSystem.systemd.units."greetd.service".text;
  frameworkNiriServiceSource = lib.attrByPath [
    "environment"
    "etc"
    "systemd/user/niri.service"
    "source"
  ] null frameworkSystem;
  frameworkNiriShutdownSource = lib.attrByPath [
    "environment"
    "etc"
    "systemd/user/niri-shutdown.target"
    "source"
  ] null frameworkSystem;
  hasFleetInput = inputs ? nixpkgs-fleet;
  primaryLinuxPackages = inputs.nixpkgs.legacyPackages.${system};
  fleetLinuxPackages =
    if hasFleetInput then
      import inputs.nixpkgs-fleet {
        inherit system;
        config.allowUnfree = true;
      }
    else
      { };
  orbitSecretPathContract = import ./tests/orbit-secret-path-contract.nix {
    inherit lib;
    pkgs = fleetLinuxPackages;
  };
  snoocertService = frameworkServices.snoocert-trust;
  snoocertPath = frameworkSystem.systemd.paths.snoocert-trust;
  snoocertExecStart = toString snoocertService.serviceConfig.ExecStart;
  snoocertExecStartParts = lib.splitString " " snoocertExecStart;
  snoocertScript = builtins.head snoocertExecStartParts;
  snoocertConfiguredTrustExecutable =
    if builtins.length snoocertExecStartParts > 2 then builtins.elemAt snoocertExecStartParts 1 else "";
  frameworkOrbitCredential = builtins.head (
    frameworkServices.orbit.serviceConfig.LoadCredential or [ "" ]
  );
  configurationContract =
    let
      failed = map (check: check.message) (
        lib.filter (check: !check.assertion) [
          {
            assertion = nixosOutputNames == [ "razer14" ];
            message = "NixOS must expose only the active razer14 host";
          }
          {
            assertion = homeOutputNames == [ "cachyos-framework13" ];
            message = "Home Manager must expose only the active standalone Framework configuration";
          }
          {
            assertion = systemOutputNames == [ "cachyos-framework13" ];
            message = "system-manager must expose only cachyos-framework13";
          }
          {
            assertion = !(systemConfigs ? default);
            message = "systemConfigs.default must not alias the Framework configuration";
          }
          {
            assertion = (razerSystem.nix.settings.download-buffer-size or 1048576) == 1048576;
            message = "Linux must use the upstream 1 MiB Nix download buffer default";
          }
          {
            assertion = frameworkSystem.nix.settings.trusted-users == [ "root" ];
            message = "Framework Nix trusted-users must use the root-only default";
          }
          {
            assertion = hasSharedSubstituters frameworkSystem.nix.settings;
            message = "Framework must use the shared binary-cache list";
          }
          {
            assertion = hasSharedTrustedPublicKeys frameworkSystem.nix.settings;
            message = "Framework must trust the shared binary-cache keys";
          }
          {
            assertion =
              hasSharedSubstituters razerSystem.nix.settings
              && hasSharedTrustedPublicKeys razerSystem.nix.settings;
            message = "Razer must retain the shared binary-cache policy";
          }
          {
            assertion = hasNoNiriCache frameworkSystem.nix.settings && hasNoNiriCache razerSystem.nix.settings;
            message = "No managed host may trust a Niri fork binary cache";
          }
          {
            assertion =
              razerSysctl."vm.dirty_background_bytes" == 268435456
              && razerSysctl."vm.dirty_bytes" == 1073741824
              && !(builtins.hasAttr "vm.dirty_background_ratio" razerSysctl)
              && !(builtins.hasAttr "vm.dirty_ratio" razerSysctl);
            message = "Razer dirty-page tuning must use byte thresholds without ratio writes";
          }
          {
            assertion =
              razerSysctl."fs.inotify.max_user_watches" == 524288
              && razerSysctl."fs.inotify.max_user_instances" == 524288;
            message = "Razer must retain the pinned NixOS inotify defaults";
          }
          {
            assertion = frameworkGraphics.enable32Bit;
            message = "Framework Steam must have the 32-bit system graphics tree enabled";
          }
          {
            assertion =
              toString frameworkGraphics.package == toString primaryLinuxPackages.mesa
              && toString frameworkGraphics.package32 == toString primaryLinuxPackages.pkgsi686Linux.mesa;
            message = "system-manager graphics must use the non-deprecated Mesa package paths";
          }
          {
            assertion = lib.attrByPath [ "local" "nix-maintenance" "enable" ] false frameworkSystem;
            message = "Framework must enable bounded Nix maintenance";
          }
          {
            assertion =
              (frameworkGcService.startAt or [ ]) == [ "Sun *-*-* 03:00:00" ]
              && lib.hasInfix "nix-collect-garbage --delete-older-than 14d" (frameworkGcService.script or "");
            message = "Framework GC must run weekly with 14-day generation retention";
          }
          {
            assertion =
              (frameworkOptimiseService.startAt or [ ]) == [ "Sun *-*-* 05:00:00" ]
              && lib.hasInfix "nix-store --optimise" (frameworkOptimiseService.script or "");
            message = "Framework store optimisation must run on its separate weekly schedule";
          }
          {
            assertion =
              isIdleMaintenanceService frameworkGcService && isIdleMaintenanceService frameworkOptimiseService;
            message = "Framework Nix maintenance must use idle CPU and I/O priority";
          }
          {
            assertion =
              lib.attrByPath [ "timerConfig" "Persistent" ] false frameworkGcTimer
              && lib.attrByPath [ "timerConfig" "Persistent" ] false frameworkOptimiseTimer
              && lib.attrByPath [ "timerConfig" "RandomizedDelaySec" ] null frameworkGcTimer == "1h"
              && lib.attrByPath [ "timerConfig" "RandomizedDelaySec" ] null frameworkOptimiseTimer == "1h";
            message = "Framework Nix maintenance timers must persist with randomized delay";
          }
          {
            assertion = builtins.length frameworkSystemDocker == 1 && frameworkHomeDocker == [ ];
            message = "Docker daemon and CLI must be owned only by system-manager";
          }
          {
            assertion = frameworkSystemSteam == [ ] && builtins.length frameworkHomeSteam == 1;
            message = "Steam must be owned only by Framework Home Manager";
          }
          {
            assertion = hasFleetInput && inputs.nixpkgs.outPath != inputs.nixpkgs-fleet.outPath;
            message = "primary nixpkgs and the Fleet package fork must remain separate inputs";
          }
          {
            assertion = hasFleetInput && (fleetLinuxPackages.fleet-orbit.version or null) == "1.59.0";
            message = "nixpkgs-fleet must provide Fleet Orbit 1.59.0";
          }
          {
            assertion = hasFleetInput && inputs.system-manager.inputs.nixpkgs.rev == inputs.nixpkgs.rev;
            message = "system-manager must follow primary nixpkgs";
          }
          {
            assertion =
              inputs.niri.inputs.nixpkgs.outPath == inputs.nixpkgs.outPath
              && !(inputs.niri.inputs ? rust-overlay);
            message = "Official Niri must follow primary nixpkgs without retaining rust-overlay";
          }
          {
            assertion =
              toString frameworkSystem.local.orbit.package == toString fleetLinuxPackages.fleet-orbit
              &&
                toString frameworkSystem.local.orbit.desktop.package == toString fleetLinuxPackages.fleet-desktop;
            message = "Framework Orbit packages must come only from nixpkgs-fleet";
          }
          {
            assertion = !(frameworkServices ? setup-greetd);
            message = "system-manager must not install greetd from a boot service";
          }
          {
            assertion = !(frameworkServices ? setup-bolt);
            message = "system-manager must not install bolt from a boot service";
          }
          {
            assertion = snoocertService.wantedBy == [ "multi-user.target" ];
            message = "Snoocert trust must run once when the system target starts";
          }
          {
            assertion = snoocertConfiguredTrustExecutable == "/usr/bin/trust";
            message = "Snoocert must use CachyOS's host-native trust integration";
          }
          {
            assertion =
              builtins.attrNames snoocertPath.pathConfig == [ "PathChanged" ]
              && snoocertPath.pathConfig.PathChanged == frameworkSystem.local.snoocert.certPath;
            message = "Snoocert must watch certificate changes without a persistent PathExists loop";
          }
          {
            assertion = !(frameworkServices ? remove-native-orbit);
            message = "system-manager must not remove native Orbit from a boot service";
          }
          {
            assertion = frameworkAssertions.orbitNativePackageConflict.enable or false;
            message = "Orbit must reject native Fleet package conflicts before activation";
          }
          {
            assertion =
              frameworkOrbitCredential == "enroll-secret:/run/secrets/fleet_enroll_secret"
              && !(lib.hasInfix "/nix/store/" frameworkOrbitCredential);
            message = "Framework Orbit must load its enrollment secret from the runtime SOPS path";
          }
          {
            assertion =
              lib.hasInfix "/usr/bin/pacman -Q" (frameworkAssertions.orbitNativePackageConflict.script or "")
              && lib.hasInfix "just migrate-cachyos-orbit" (
                frameworkAssertions.orbitNativePackageConflict.script or ""
              );
            message = "the Orbit conflict assertion must identify the explicit migration";
          }
          {
            assertion = frameworkAssertions.niriNativePackages.enable or false;
            message = "Niri must verify its native CachyOS prerequisites before activation";
          }
          {
            assertion = frameworkAssertions.boltNativePackage.enable or false;
            message = "Bolt must verify its native CachyOS prerequisite before activation";
          }
          {
            assertion = lib.hasInfix ''user = "greeter"'' greetdConfig;
            message = "tuigreet must run as the native greeter account";
          }
          {
            assertion = lib.hasInfix "X-RestartIfChanged=false" greetdUnit;
            message = "Framework greetd must not restart during system-manager activation";
          }
          {
            assertion =
              lib.all (niri: niri.enable or false) enabledHomeNiriProfiles && razerSystem.programs.niri.enable;
            message = "Niri must be enabled only for the Razer and Framework Linux consumers";
          }
          {
            assertion = lib.all homeNiriOwnsOnlyConfig enabledHomeNiriProfiles;
            message = "Home Manager Niri must validate KDL without overlapping systemd, portal, or Xwayland ownership";
          }
          {
            assertion =
              frameworkHome.xdg.portal.enable
              && builtins.elem (toString frameworkHomeOutput.pkgs.xdg-desktop-portal-gnome) frameworkPortalPackages
              && builtins.elem (toString frameworkHomeOutput.pkgs.xdg-desktop-portal-gtk) frameworkPortalPackages;
            message = "Framework Niri must publish the GNOME screen-cast and GTK fallback portal backends";
          }
          {
            assertion =
              !(lib.attrByPath [ "programs" "niri" "useNautilus" ] true razerSystem)
              && !(lib.attrByPath [
                "systemd"
                "user"
                "services"
                "niri"
                "restartIfChanged"
              ] true razerSystem);
            message = "NixOS Niri must retain GTK portal and session-safe restart policy";
          }
          {
            assertion =
              lib.hasInfix "MemoryHigh=256M" falconDropIn
              && lib.hasInfix "MemoryMax=512M" falconDropIn
              && lib.hasInfix "MemorySwapMax=0" falconDropIn;
            message = "Falcon must use the 256 MiB soft and 512 MiB hard memory limits";
          }
          {
            assertion =
              lib.hasInfix "CPUWeight=100" orbitDropIn
              && lib.hasInfix "CPUQuota=20%" orbitDropIn
              && lib.hasInfix "MemoryHigh=480M" orbitDropIn
              && lib.hasInfix "MemoryMax=500M" orbitDropIn;
            message = "Orbit resource controls must remain at the measured policy";
          }
          {
            assertion =
              lib.hasInfix "CPUWeight=1" duoDropIn
              && lib.hasInfix "CPUQuota=0.25%" duoDropIn
              && lib.hasInfix "MemoryHigh=80M" duoDropIn
              && lib.hasInfix "MemoryMax=96M" duoDropIn;
            message = "Duo resource controls must remain at the measured policy";
          }
          {
            assertion = razerSystem.local.apple-studio-display-brightness.enable;
            message = "the Razer host must explicitly enable Studio Display brightness support";
          }
          {
            assertion = frameworkSystem.local.apple-studio-display-brightness.enable;
            message = "the Framework host must explicitly enable Studio Display brightness support";
          }
          {
            assertion = lib.attrByPath [
              "local"
              "niri"
              "appleStudioDisplay"
              "enable"
            ] false razerHome;
            message = "the Razer Home Manager config must enable Studio Display behavior";
          }
          {
            assertion = lib.attrByPath [
              "local"
              "niri"
              "appleStudioDisplay"
              "enable"
            ] false frameworkHome;
            message = "the Framework Home Manager config must enable Studio Display behavior";
          }
          {
            assertion =
              niriUpstream != null
              && lib.all homeNiriUsesUpstream enabledHomeNiriProfiles
              && toString razerSystem.programs.niri.package == toString niriUpstream;
            message = "Every enabled Linux Niri consumer must share the official upstream derivation";
          }
          {
            assertion =
              niriUpstream != null
              && toString frameworkNiriServiceSource == "${niriUpstream}/lib/systemd/user/niri.service"
              && toString frameworkNiriShutdownSource == "${niriUpstream}/lib/systemd/user/niri-shutdown.target";
            message = "system-manager must install CachyOS Niri units from the official package";
          }
          {
            assertion =
              razerNativeNiri.settings.xwayland-satellite.path
              == lib.getExe razerSystemOutput.pkgs.xwayland-satellite
              &&
                frameworkNativeNiri.settings.xwayland-satellite.path
                == lib.getExe frameworkHomeOutput.pkgs.xwayland-satellite;
            message = "Xwayland Satellite must come from each Home Manager output's primary nixpkgs package set";
          }
          {
            assertion =
              razerNativeNiri.package.doCheck
              && frameworkNativeNiri.package.doCheck
              && razerSystem.programs.niri.package.doCheck;
            message = "Niri packages must retain their upstream check setting";
          }
          {
            assertion = lib.versionAtLeast razerSystemOutput.pkgs.rtk.version "0.44.0";
            message = "Home Manager must use upstream RTK 0.44.0 or newer";
          }
          {
            assertion = builtins.length frameworkHeadroom == 1 && builtins.length razerHeadroom == 1;
            message = "Framework and Razer Home Manager must each install the Headroom CLI exactly once";
          }
          {
            assertion =
              compoundSkillNames != [ ]
              && lib.all (files: lib.all (hasPinnedCompoundSkills files) linuxAiSkillRoots) [
                frameworkHomeFiles
                razerHomeFiles
              ];
            message = "Framework and Razer must install exactly the pinned CE skills for OpenCode, Gemini, and Antigravity";
          }
          {
            assertion =
              !(inputs ? android-skills)
              &&
                lib.all
                  (
                    files:
                    lib.all (
                      name:
                      (
                        !(lib.hasPrefix ".codex/skills/" name)
                        || builtins.elem name (map (skill: ".codex/skills/${skill}") openspecSkillNames)
                      )
                      && !(lib.hasPrefix ".agents/skills/" name)
                    ) (builtins.attrNames files)
                  )
                  [
                    frameworkHomeFiles
                    razerHomeFiles
                  ];
            message = "Android skills must be retired; Codex must use its native plugin without duplicate shared skills";
          }
          {
            assertion =
              lib.all
                (
                  home:
                  builtins.length (packagesNamed "openspec" home.home.packages) == 1
                  && lib.all (
                    root:
                    lib.all (
                      name:
                      builtins.hasAttr "${root}/${name}" home.home.file && home.home.file."${root}/${name}".recursive
                    ) openspecSkillNames
                  ) openspecSkillRoots
                )
                [
                  frameworkHome
                  razerHome
                ];
            message = "Framework and Razer must install OpenSpec and its six core skills for every configured coding agent";
          }
          {
            assertion =
              !frameworkHome.local.gemini-cli.enable
              && packagesNamed "gemini-cli" frameworkHome.home.packages == [ ]
              && !(builtins.hasAttr ".gemini/settings.json" frameworkHomeFiles);
            message = "Framework Home Manager must omit the Gemini CLI package and settings while still installing its CE skills";
          }
          {
            assertion = razerHome.programs.zen-browser.env == integratedGpuEnv;
            message = "Razer Zen must receive the exact integrated-GPU launcher environment";
          }
          {
            assertion = hasNoIntegratedGpuSessionVariables razerHome;
            message = "Razer integrated-GPU variables must not leak into the global session";
          }
          {
            assertion = builtins.length razerLlama == 1 && targetsOnlySm120 (builtins.head razerLlama);
            message = "embedded Razer Home Manager must provide CUDA llama-cpp for sm_120 only";
          }
        ]
      );
    in
    lib.assertMsg (failed == [ ]) (
      "Configuration contract failed:\n"
      + lib.concatStringsSep "\n" (map (message: "- ${message}") failed)
    );
in
{
  # NixOS configuration check
  razer14 = nixosConfigurations.razer14.config.system.build.toplevel;

  # Home Manager configuration check
  home-cachyos-framework13 = homeConfigurations.cachyos-framework13.activationPackage;

  # system-manager configuration check
  system-cachyos-framework13 = systemConfigs.cachyos-framework13;

  configuration-contract =
    assert configurationContract;
    pkgs.runCommand "configuration-contract" { } ''
      touch "$out"
    '';

  opencode-headroom-v2 =
    pkgs.runCommand "opencode-headroom-v2-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        export SSL_CERT_FILE='${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt'
        ${pkgs.python3.interpreter} ${./packages/tests/opencode-headroom-v2.py} \
          --opencode ${lib.getExe frameworkOpencode.unwrapped} \
          --headroom ${lib.getExe headroomPackage} \
          --plugin ${./dotfiles/opencode/plugins/headroom} \
          --catalog-plugin ${llmPlatformPlugin} \
          --skills ${inputs.compound-engineering}/skills
        touch "$out"
      '';

  openspec-agent-files = pkgs.runCommand "openspec-agent-files-check" { } ''
    ${pkgs.python3.interpreter} ${./packages/tests/openspec-agent-files.py} \
      ${pkgs.writeText "openspec-agent-sources.json" (
        builtins.toJSON (
          map (files: lib.mapAttrs (_: file: toString file.source) (openspecFiles files)) [
            frameworkHomeFiles
            razerHomeFiles
          ]
        )
      )}
    ${lib.getExe pkgs.openspec} --version
    touch "$out"
  '';

  headroom-cli =
    assert builtins.length frameworkHeadroom == 1 && builtins.length razerHeadroom == 1;
    assert toString headroomPackage == toString razerHeadroomPackage;
    pkgs.runCommand "headroom-cli-check"
      {
        nativeBuildInputs = [
          headroomPackage
          headroomFakeCodex
          headroomFakeOpencode
          pkgs.gnugrep
        ];
      }
      ''
            headroom --version | grep -Fq -- '0.37.0'
            headroom sg --version
            headroom diff --version
            headroom loc --version

            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$HOME/.config"
            export XDG_RUNTIME_DIR="$TMPDIR/runtime"
            export HEADROOM_TEST_CONFIG_CAPTURE="$TMPDIR/opencode-config-path"
            export HEADROOM_TEST_PORT=48787
            export HEADROOM_TEST_EXPECT_SERENA=1
            mkdir -p "$XDG_CONFIG_HOME/opencode" "$XDG_RUNTIME_DIR"
            ln -s '${headroomManagedOpencodeConfig}' "$XDG_CONFIG_HOME/opencode/opencode.json"

            headroom wrap opencode \
              --port 48787 \
              --no-proxy

            test -s "$HEADROOM_TEST_CONFIG_CAPTURE"
            session_config="$(${pkgs.coreutils}/bin/cat "$HEADROOM_TEST_CONFIG_CAPTURE")"
            test ! -e "$session_config"
            test -L "$XDG_CONFIG_HOME/opencode/opencode.json"
            ${pkgs.diffutils}/bin/cmp \
              '${headroomManagedOpencodeConfig}' \
              "$XDG_CONFIG_HOME/opencode/opencode.json"

            rm "$HEADROOM_TEST_CONFIG_CAPTURE"
        export HEADROOM_TEST_PORT=48788
        export HEADROOM_TEST_EXPECT_SERENA=0
        export HEADROOM_TEST_EXPECT_PROXY_FEATURES=1
        export HEADROOM_OFFLINE=1
            export HEADROOM_TELEMETRY=off
            export SSL_CERT_FILE='${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt'
            headroom wrap opencode \
              --port "$HEADROOM_TEST_PORT" \
              --no-serena

            test -s "$HEADROOM_TEST_CONFIG_CAPTURE"
            proxy_session_config="$(${pkgs.coreutils}/bin/cat "$HEADROOM_TEST_CONFIG_CAPTURE")"
            test ! -e "$proxy_session_config"
            test -L "$XDG_CONFIG_HOME/opencode/opencode.json"
            ${pkgs.diffutils}/bin/cmp \
              '${headroomManagedOpencodeConfig}' \
              "$XDG_CONFIG_HOME/opencode/opencode.json"
            export HEADROOM_TEST_PORT=8787
            export HEADROOM_TEST_CODEX_CAPTURE="$TMPDIR/codex-ran"
            headroom wrap codex
            test -s "$HEADROOM_TEST_CODEX_CAPTURE"

            unset HEADROOM_TEST_EXPECT_PROXY_FEATURES
            export USER=test-user
            export CODEX_HOME="$TMPDIR/codex-idempotent"
            export HEADROOM_TEST_CODEX_CAPTURE="$TMPDIR/codex-idempotent-runs"
            mkdir -p "$CODEX_HOME"
            ${pkgs.coreutils}/bin/printf '%s\n' \
              '[mcp_servers.headroom_memory]' \
              'command = "${pkgs.python3.interpreter}"' \
              'args = ["-m", "headroom.memory.mcp_server", "--user", "test-user"]' \
              'startup_timeout_sec = 30' \
              'tool_timeout_sec = 30' \
              > "$CODEX_HOME/config.toml"
            ${pkgs.coreutils}/bin/touch -d '@946684800' "$CODEX_HOME/config.toml"
            ${pkgs.coreutils}/bin/cp "$CODEX_HOME/config.toml" "$TMPDIR/codex-config.expected"

            headroom wrap codex \
              --port 48790 \
              --no-proxy \
              --no-mcp \
              --no-serena
            ${pkgs.diffutils}/bin/cmp "$TMPDIR/codex-config.expected" "$CODEX_HOME/config.toml"
            test "$(${pkgs.coreutils}/bin/stat -c '%Y' "$CODEX_HOME/config.toml")" = 946684800
            ${pkgs.python3.interpreter} -c \
              'import pathlib, tomllib; data = tomllib.loads(pathlib.Path("'"$CODEX_HOME"'/config.toml").read_text()); assert list(data["mcp_servers"]) == ["headroom_memory"], data'

            headroom wrap codex \
              --port 48790 \
              --no-proxy \
              --no-mcp \
              --no-serena
            ${pkgs.diffutils}/bin/cmp "$TMPDIR/codex-config.expected" "$CODEX_HOME/config.toml"
            test "$(${pkgs.coreutils}/bin/stat -c '%Y' "$CODEX_HOME/config.toml")" = 946684800

            HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS=9 \
              HEADROOM_TEST_EXPECT_WS_TIMEOUT=9 \
              headroom wrap codex \
              --port 48790 \
              --no-proxy \
              --no-mcp \
              --no-serena
            ${pkgs.diffutils}/bin/cmp "$TMPDIR/codex-config.expected" "$CODEX_HOME/config.toml"

            export CODEX_HOME="$TMPDIR/codex-conflicting"
            mkdir -p "$CODEX_HOME"
            ${pkgs.coreutils}/bin/printf '%s\n' \
              '[mcp_servers.headroom_memory]' \
              'command = "/user/managed/python"' \
              'args = ["-m", "another.memory.server"]' \
              > "$CODEX_HOME/config.toml"
            ${pkgs.coreutils}/bin/cp "$CODEX_HOME/config.toml" "$TMPDIR/codex-conflicting.expected"
            headroom wrap codex \
              --port 48791 \
              --no-proxy \
              --no-mcp \
              --no-serena
            ${pkgs.diffutils}/bin/cmp "$TMPDIR/codex-conflicting.expected" "$CODEX_HOME/config.toml"

            export CODEX_HOME="$TMPDIR/codex-invalid"
            mkdir -p "$CODEX_HOME"
            ${pkgs.coreutils}/bin/printf '%s\n' \
              '[mcp_servers.headroom_memory]' \
              'command = "/first/python"' \
              '[mcp_servers.headroom_memory]' \
              'command = "/duplicate/python"' \
              > "$CODEX_HOME/config.toml"
            ${pkgs.coreutils}/bin/cp "$CODEX_HOME/config.toml" "$TMPDIR/codex-invalid.expected"
            if headroom wrap codex \
              --port 48792 \
              --no-proxy \
              --no-mcp \
              --no-serena; then
              exit 1
            fi
            ${pkgs.diffutils}/bin/cmp "$TMPDIR/codex-invalid.expected" "$CODEX_HOME/config.toml"

            export CODEX_HOME="$TMPDIR/codex-fixed-port"
            export HEADROOM_TEST_PORT=48789
            export HEADROOM_TEST_EXPECT_WS_TIMEOUT=12
            export HEADROOM_TEST_EXPECT_PROXY_FEATURES=1
            export HEADROOM_TEST_CODEX_CAPTURE="$TMPDIR/codex-fixed-port-runs"
            mkdir -p "$CODEX_HOME"
            release_file="$TMPDIR/release-first-codex"
            export HEADROOM_TEST_CODEX_RELEASE_FILE="$release_file"
            cleanup_fixed_port_test() {
              ${pkgs.coreutils}/bin/touch "$release_file"
              if [ -n "''${first_wrap_pid:-}" ]; then
                wait "$first_wrap_pid" || true
              fi
            }
            trap cleanup_fixed_port_test EXIT

            ${headroomFixedPortPackage}/bin/headroom wrap codex \
              --no-mcp \
              --no-serena &
            first_wrap_pid=$!
            attempt=0
            while [ ! -s "$HEADROOM_TEST_CODEX_CAPTURE" ]; do
              attempt=$((attempt + 1))
              test "$attempt" -lt 300
              ${pkgs.coreutils}/bin/sleep 0.1
            done

            unset HEADROOM_TEST_CODEX_RELEASE_FILE
            ${headroomFixedPortPackage}/bin/headroom wrap codex \
              --no-mcp \
              --no-serena

            ${pkgs.coreutils}/bin/touch "$release_file"
            wait "$first_wrap_pid"
            first_wrap_pid=
            trap - EXIT
            test "$(${pkgs.coreutils}/bin/wc -l < "$HEADROOM_TEST_CODEX_CAPTURE")" = 2
            while IFS= read -r proxy_url; do
              case "$proxy_url" in
                http://127.0.0.1:48789/*) ;;
                *) exit 1 ;;
              esac
            done < "$HEADROOM_TEST_CODEX_CAPTURE"

            touch "$out"
      '';

  nix-format =
    pkgs.runCommand "nix-format-check"
      {
        nativeBuildInputs = [
          pkgs.findutils
          pkgs.nixfmt
        ];
      }
      ''
        find "${src}" -type f -name '*.nix' -print0 \
          | xargs -0 -r nixfmt --check
        touch "$out"
      '';

  lua-format =
    pkgs.runCommand "lua-format-check"
      {
        nativeBuildInputs = [
          pkgs.findutils
          pkgs.stylua
        ];
      }
      ''
        find "${src}" -type f -name '*.lua' -print0 \
          | xargs -0 -r stylua --check \
              --config-path "${src}/dotfiles/nvim/.stylua.toml"
        touch "$out"
      '';

  nvim-regressions =
    pkgs.runCommand "nvim-regressions"
      {
        nativeBuildInputs = [ pkgs.neovim ];
      }
      ''
        export HOME="$TMPDIR"
        cd "${src}"
        nvim --headless -u NONE -i NONE --noplugin -l tests/nvim/conform-json.lua
        nvim --headless -u NONE -i NONE --noplugin -l tests/nvim/snacks-dashboard.lua
        touch "$out"
      '';

  shell-syntax =
    pkgs.runCommand "shell-syntax-check"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.findutils
        ];
      }
      ''
        while IFS= read -r -d "" script; do
          bash -n "$script"
        done < <(find "${src}" -type f -name '*.sh' -print0)
        touch "$out"
      '';

  justfile-contract =
    pkgs.runCommand "justfile-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.just
        ];
      }
      ''
        bash "${src}/tests/justfile-contract.sh" "${src}"
        touch "$out"
      '';
}
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  orbit-secret-path-contract =
    assert orbitSecretPathContract;
    pkgs.runCommand "orbit-secret-path-contract" { } ''
      touch "$out"
    '';

  snoocert-trust =
    let
      recordingTrust = pkgs.writeShellScript "record-snoocert-trust-call" ''
        printf '%s\n' "$@" > "$SNOOCERT_TRUST_CALL"
        printf '%s\n' "$PATH" > "$SNOOCERT_TRUST_PATH"
      '';
      failingTrust = pkgs.writeShellScript "fail-snoocert-trust-call" ''
        exit 23
      '';
    in
    pkgs.runCommand "snoocert-trust-check" { } ''
      printf '%s\n' 'certificate fixture' > "$TMPDIR/certificate.pem"

      SNOOCERT_TRUST_CALL="$TMPDIR/trust-call" \
        SNOOCERT_TRUST_PATH="$TMPDIR/trust-path" \
        ${lib.escapeShellArg snoocertScript} \
        ${lib.escapeShellArg recordingTrust} \
        "$TMPDIR/certificate.pem"

      printf 'anchor\n%s\n' "$TMPDIR/certificate.pem" > "$TMPDIR/expected-trust-call"
      if ! cmp -s "$TMPDIR/expected-trust-call" "$TMPDIR/trust-call"; then
        echo "Snoocert did not pass the certificate to the configured trust command" >&2
        exit 1
      fi

      case "$(cat "$TMPDIR/trust-path")" in
        /usr/bin:/bin:*) ;;
        *)
          echo "Snoocert did not expose CachyOS trust utilities through PATH" >&2
          exit 1
          ;;
      esac

      if ${lib.escapeShellArg snoocertScript} \
        ${lib.escapeShellArg failingTrust} \
        "$TMPDIR/certificate.pem"
      then
        echo "Snoocert did not propagate a trust-command failure" >&2
        exit 1
      fi

      touch "$out"
    '';

  waybar-audio-actions =
    let
      audioClick = lib.escapeShellArg waybarAudio.on-click;
      muteClick = lib.escapeShellArg waybarAudio.on-click-right;
    in
    pkgs.runCommand "waybar-audio-actions-check"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        grep -Fq -- ${lib.escapeShellArg (lib.getExe pkgs.mixxc)} ${audioClick}
        grep -Fq -- ${lib.escapeShellArg "${pkgs.mixxc}/bin/.mixxc-wrapped"} ${audioClick}
        grep -Fq -- 'waybar-mixxc.pid' ${audioClick}
        grep -Fq -- 'kill "$running_pid"' ${audioClick}

        for argument in \
          '--width 360' \
          '--anchor top' \
          '--anchor right' \
          '--margin 48' \
          '--margin 8' \
          '--master' \
          '--icon' \
          '--per-process' \
          '--max-volume 150' \
          '--close 250'
        do
          grep -Fq -- "$argument" ${audioClick}
        done

        grep -Fq -- \
          ${lib.escapeShellArg "${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SINK@ toggle"} \
          ${muteClick}
        test ${lib.escapeShellArg (toString waybarAudio."scroll-step")} -eq 5
        touch "$out"
      '';
}
