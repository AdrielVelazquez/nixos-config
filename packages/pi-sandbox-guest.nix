{
  lib,
  pkgs,
  managedFiles,
  homeDirectory,
  agentDirectory,
  piPackage,
  runtimePackages,
}:
let
  names = builtins.attrNames managedFiles;
  manifest = pkgs.writeText "pi-sandbox-managed-files.json" (builtins.toJSON names);
  snapshot = pkgs.runCommand "pi-sandbox-managed-config" { } ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (name: ''
      mkdir -p "$out"/${lib.escapeShellArg (builtins.dirOf name)}
      ln -s ${lib.escapeShellArg managedFiles.${name}} "$out"/${lib.escapeShellArg name}
    '') names}
    cp ${manifest} "$out/manifest.json"
  '';
  entry = pkgs.writeShellScriptBin "pi-sandbox-guest" ''
    set -euo pipefail
    umask 077
    export HOME=${lib.escapeShellArg homeDirectory}
    export PI_CODING_AGENT_DIR=${lib.escapeShellArg agentDirectory}
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_RUNTIME_DIR=/tmp/pi-sandbox-runtime
    export NIX_REMOTE=local
    mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    chmod 700 "$XDG_RUNTIME_DIR"
    ${pkgs.python3.interpreter} -I ${./pi-sandbox-guest.py} ${snapshot} "$PI_CODING_AGENT_DIR"
    exec ${lib.getExe piPackage} "$@"
  '';
  environment = pkgs.buildEnv {
    name = "pi-sandbox-guest-environment";
    paths = runtimePackages ++ [
      piPackage
      entry
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
    ];
  };
  tag = builtins.substring 0 24 (builtins.hashString "sha256" (builtins.toJSON imageArgs));
  nss = [
    (pkgs.writeTextDir "etc/passwd" "root:x:0:0:Sandbox:${homeDirectory}:/bin/bash\n")
    (pkgs.writeTextDir "etc/group" "root:x:0:\n")
    (pkgs.writeTextDir "etc/nsswitch.conf" "passwd: files\ngroup: files\nhosts: files dns\n")
    (pkgs.writeTextDir "etc/os-release" "ID=pi-sandbox\nNAME=\"Managed Pi microVM\"\n")
  ];
  imageArgs = {
    name = "pi-sandbox";
    compressor = "none";
    maxLayers = 32;
    contents = [
      environment
      pkgs.dockerTools.usrBinEnv
    ]
    ++ nss;
    includeNixDB = true;
    extraCommands = ''
      mkdir -p tmp workspace repos run ${lib.escapeShellArg (lib.removePrefix "/" homeDirectory)}
    '';
    fakeRootCommands = ''
      chmod 1777 tmp
    '';
    config = {
      Entrypoint = [ ];
      Cmd = [ (lib.getExe entry) ];
      WorkingDir = "/workspace";
      Env = [
        "HOME=${homeDirectory}"
        "PATH=/bin"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "LANG=C.UTF-8"
      ];
    };
  };
  image = pkgs.dockerTools.buildLayeredImage (imageArgs // { inherit tag; });
in
{
  imagePackage = image;
  imageTag = "pi-sandbox:${tag}";
  guestCommand = lib.getExe entry;
  inherit snapshot;
}
