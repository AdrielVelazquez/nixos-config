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
    ".codex/skills"
    ".config/opencode/skills"
  ];
  retiredPerfettoSkillNames = [
    "perfetto-sql"
    "perfetto-trace-analysis"
  ];
  frameworkSystemDocker = packagesNamed "docker" frameworkSystem.environment.systemPackages;
  frameworkSystemSteam = packagesNamed "steam" frameworkSystem.environment.systemPackages;
  frameworkHomeDocker = packagesNamed "docker" frameworkHome.home.packages;
  frameworkHomeSteam = packagesNamed "steam" frameworkHome.home.packages;
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
            assertion = !(primaryLinuxPackages ? fleet-orbit);
            message = "the primary nixpkgs input must not carry the Fleet fork";
          }
          {
            assertion = hasFleetInput && (fleetLinuxPackages.fleet-orbit.version or null) == "1.58.0";
            message = "nixpkgs-fleet must provide Fleet Orbit 1.58.0";
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
            assertion =
              builtins.hasAttr ".gemini/antigravity-cli/skills/using-superpowers" razerHomeFiles
              && razerHomeFiles.".gemini/antigravity-cli/skills/using-superpowers".recursive
              && !(builtins.hasAttr ".gemini/antigravity/skills/using-superpowers" razerHomeFiles);
            message = "Antigravity CLI must install recursive Superpowers skills in its supported global root";
          }
          {
            assertion =
              builtins.hasAttr ".gemini/antigravity-cli/skills/agp-9-upgrade" razerHomeFiles
              && razerHomeFiles.".gemini/antigravity-cli/skills/agp-9-upgrade".recursive
              && builtins.pathExists razerHomeFiles.".gemini/antigravity-cli/skills/agp-9-upgrade".source;
            message = "Antigravity CLI must install agp-9-upgrade from an existing Android skills path";
          }
          {
            assertion =
              lib.all (
                root: hasExistingRecursiveHomeFile frameworkHomeFiles "${root}/android-profiler"
              ) linuxAiSkillRoots
              && lib.all (
                root:
                lib.all (name: !(builtins.hasAttr "${root}/${name}" frameworkHomeFiles)) retiredPerfettoSkillNames
              ) (linuxAiSkillRoots ++ [ ".gemini/skills" ]);
            message = "Linux AI clients must use the existing consolidated android-profiler skill without retired Perfetto entries";
          }
          {
            assertion =
              !frameworkHome.local.gemini-cli.enable
              && packagesNamed "gemini-cli" frameworkHome.home.packages == [ ]
              && !(builtins.hasAttr ".gemini/settings.json" frameworkHomeFiles)
              && lib.all (name: name != ".gemini/skills" && !(lib.hasPrefix ".gemini/skills/" name)) (
                builtins.attrNames frameworkHomeFiles
              );
            message = "Framework Home Manager must omit Gemini CLI and its standalone configuration while using Antigravity";
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
