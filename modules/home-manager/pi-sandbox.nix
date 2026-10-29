{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.sandbox;
  pi = config.local.pi;
  json = pkgs.formats.json { };
  home = config.home.homeDirectory;
  prefix = "${pi.agentDir}/";
  permitted =
    name:
    lib.elem name [
      "settings.json"
      "keybindings.json"
      "mcp.json"
      "AGENTS.md"
      "web-search.json"
    ]
    || lib.hasPrefix "agents/" name
    || (
      lib.hasPrefix "extensions/" name
      && !(lib.elem name [
        "extensions/tuios-agent-state.ts"
        "extensions/tuios-outcomes.ts"
      ])
    );
  selected = lib.filterAttrs (
    name: file:
    lib.hasPrefix prefix name
    && permitted (lib.removePrefix prefix name)
    && (file.enable || name == "${pi.agentDir}/settings.json")
  ) config.home.file;
  settings = config.programs.pi-coding-agent.settings // {
    extensions = lib.filter (
      path: !(lib.hasSuffix "/tuios-agent-state.ts" path || lib.hasSuffix "/tuios-outcomes.ts" path)
    ) (config.programs.pi-coding-agent.settings.extensions or [ ]);
  };
  managedFiles =
    lib.mapAttrs' (
      name: file: lib.nameValuePair (lib.removePrefix prefix name) (toString file.source)
    ) selected
    // {
      "settings.json" = toString (json.generate "pi-sandbox-settings.json" settings);
    };
  guestPackages =
    with pkgs;
    [
      bashInteractive
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      diffutils
      git
      fd
      ripgrep
      file
      which
      procps
      util-linux
      cacert
      curl
      jq
      gnutar
      gzip
      openssh
      nodejs
      python3
      nix
      go
    ]
    ++ lib.optional pi.rtk.enable pi.rtk.package
    ++ cfg.extraPackages;
  guest = pkgs.callPackage ../../packages/pi-sandbox-guest.nix {
    inherit pkgs;
    managedFiles = cfg.guestFiles;
    homeDirectory = home;
    agentDirectory = pi.agentDir;
    piPackage = config.programs.pi-coding-agent.package;
    runtimePackages = guestPackages;
  };
  manifest = json.generate "pi-sandbox-launcher.json" {
    runtime = lib.getExe cfg.runtimePackage;
    git = lib.getExe pkgs.git;
    image = toString guest.imagePackage;
    inherit (guest) imageTag guestCommand;
    stateDir = cfg.stateDir;
    hostHome = home;
    guestHome = home;
    protectedPaths = [
      pi.agentDir
      config.xdg.configHome
      config.xdg.dataHome
      config.xdg.stateHome
      config.xdg.cacheHome
    ]
    ++ lib.mapAttrsToList (_: secret: secret.path) config.sops.secrets;
    runtimePath = lib.makeBinPath [
      cfg.runtimePackage
      pkgs.git
      pkgs.coreutils
    ];
    caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    inherit (cfg)
      cpus
      memory
      networkPolicy
      allowedHosts
      ports
      secretBindings
      ;
  };
  launcher = pkgs.writeShellScriptBin "pi-sandbox" ''
    exec ${pkgs.python3.interpreter} -I ${../../packages/pi-sandbox.py} --config ${manifest} "$@"
  '';
in
{
  options.local.pi.sandbox = {
    enable = lib.mkEnableOption "a separate whole-process managed Pi microVM launcher";
    runtimePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.microsandbox or (pkgs.callPackage ../../packages/microsandbox.nix { });
      description = "Local Microsandbox runtime with matching firmware; never a runtime installer.";
    };
    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Guest virtual CPUs.";
    };
    memory = lib.mkOption {
      type = lib.types.strMatching "[1-9][0-9]*[MG]";
      default = "4G";
      description = "Guest memory, for example 4G or 8192M.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/pi-sandbox";
      description = "Private host runtime/catalog and per-project guest state, never shared into the guest.";
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional development commands built into the guest image.";
    };
    networkPolicy = lib.mkOption {
      type = lib.types.enum [
        "public"
        "none"
      ];
      default = "public";
      description = "Public outbound access or offline; neither grants host/LAN access by default.";
    };
    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Optional outbound hostname allowlist; a nonempty list restricts outbound access.";
    };
    ports = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "127\\.0\\.0\\.1:[0-9]+:[0-9]+(/(tcp|udp))?");
      default = [ ];
      description = "Explicit loopback-only host:guest port mappings.";
    };
    secretBindings = lib.mkOption {
      default = { };
      description = "Explicit API-token bindings. Only runtime file paths enter Nix; the guest receives placeholders, not real values. SSH credentials are not supported.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            sourceFile = lib.mkOption {
              type = lib.types.strMatching "/.*";
              description = "Absolute runtime SOPS token path outside the Nix store; never a token value.";
            };
            allowedHosts = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "[a-zA-Z0-9.-]+");
              description = "Exact hosts allowed to receive this token in Authorization headers.";
            };
          };
        }
      );
    };
    guestFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = if cfg.enable then managedFiles else { };
      readOnly = true;
      internal = true;
    };
    launcherPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if cfg.enable then launcher else null;
      readOnly = true;
      internal = true;
    };
    imagePackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if cfg.enable then guest.imagePackage else null;
      readOnly = true;
      internal = true;
    };
    manifest = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = if cfg.enable then manifest else null;
      readOnly = true;
      internal = true;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pi.enable;
        message = "local.pi.sandbox requires the managed Pi configuration";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The initial Pi Microsandbox package supports x86_64 Linux only";
      }
      {
        assertion = lib.hasPrefix "${home}/" pi.agentDir;
        message = "Pi's guest agent directory must be inside its guest home";
      }
      {
        assertion = lib.hasPrefix "/" cfg.stateDir && !(lib.hasPrefix "/nix/store/" cfg.stateDir);
        message = "Pi sandbox state requires an absolute writable runtime path";
      }
    ];
    home.packages = [ launcher ];
  };
}
