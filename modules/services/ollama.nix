# modules/services/ollama.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.ollama;
  cudaEnabled = config.local.cuda.enable or false;
in
{
  options.local.ollama = {
    enable = lib.mkEnableOption "Enables Ollama AI";
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the Ollama service should start automatically at boot.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.ollama.enable = true;
      systemd.services.ollama.wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
    })

    (lib.mkIf (cfg.enable && cudaEnabled) {
      environment.systemPackages = [ pkgs.cudatoolkit ];
      services.ollama.package = pkgs.ollama-cuda;
    })
  ];
}
