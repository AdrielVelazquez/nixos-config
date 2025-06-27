{
  pkgs,
  config,
  lib,
  ...
}:

with lib;
{
  imports = [
    ./sops-configuration.nix
  ];

  options.within.falcon.enable = mkEnableOption "Enables falcon Settings";

  config = mkIf config.within.falcon.enable (
    let
      falcon = pkgs.callPackage ./falcon-default.nix { };
      falconCidFile = config.sops.secrets.falcon_customer_id.path;
      startPreScript = pkgs.writeScript "init-falcon" ''
        #! ${pkgs.bash}/bin/sh
        /run/current-system/sw/bin/mkdir -p /opt/CrowdStrike
        ln -sf ${falcon}/opt/CrowdStrike/* /opt/CrowdStrike
        ${falcon}/bin/fs-bash -c "${falcon}/opt/CrowdStrike/falconctl -s --cid=$(cat ${falconCidFile}) -f"
      '';
    in
    {
      within.sops.enable = true;

      boot.kernel.extraConfig = ''
        # Required BPF kernel options
        BPF y
        BPF_SYSCALL y
        DEBUG_INFO_BTF y
        TRACING y
        KPROBE_EVENTS y
        UPROBE_EVENTS y
        BPF_JIT y
        SECURITY y
        KALLSYMS_ALL y
        PROC_FS y
        BSD_PROCESS_ACCT y
        CGROUPS y
        CGROUP_BPF y
        DEBUG_INFO_BTF_MODULES y

        # Options that can be compiled as modules
        NET_CLS_BPF m
        NET_CLS_ACT m
        NET_SCH_INGRESS m
      '';
      systemd.services.falcon-sensor = {
        enable = true;
        description = "CrowdStrike Falcon Sensor";
        unitConfig.DefaultDependencies = false;
        after = [ "local-fs.target" ];
        conflicts = [ "shutdown.target" ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        serviceConfig = {
          ExecStartPre = "${startPreScript}";
          ExecStart = "${falcon}/bin/fs-bash -c \"${falcon}/opt/CrowdStrike/falcond\"";
          Type = "forking";
          PIDFile = "/run/falcond.pid";
          Restart = "no";
          TimeoutStopSec = "60s";
          KillMode = "process";
        };
        wantedBy = [ "multi-user.target" ];
      };
    }
  ); # <-- The closing parenthesis for the mkIf argument
}
