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
      boot.kernelPatches = [
        {
          name = "enable-custom-bpf";
          patch = null;
          extraConfig = ''
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
            NET_CLS_BPF y
            NET_CLS_ACT y
            NET_SCH_INGRESS y
          '';
        }
      ];
      # boot.kernelPatches = [
      #
      #   {
      #     name = "bpf-and-tracing-config";
      #     patch = null;
      #     extraConfig = ''
      #       # Required BPF kernel options
      #       # CONFIG_BPF=y
      #       # CONFIG_BPF_SYSCALL=y
      #       # CONFIG_DEBUG_INFO_BTF=y
      #       # CONFIG_TRACING=y
      #       # CONFIG_KPROBE_EVENTS=y
      #       # CONFIG_UPROBE_EVENTS=y
      #       # CONFIG_BPF_JIT=y
      #       # CONFIG_SECURITY=y
      #       # CONFIG_KALLSYMS_ALL=y
      #       # CONFIG_PROC_FS=y
      #       # CONFIG_BSD_PROCESS_ACCT=y
      #       # CONFIG_CGROUPS=y
      #       # CONFIG_CGROUP_BPF=y
      #       # CONFIG_DEBUG_INFO_BTF_MODULES=y
      #
      #       # Options that can be compiled as modules
      #       CONFIG_NET_CLS_BPF=m
      #       CONFIG_NET_CLS_ACT=m
      #       CONFIG_NET_SCH_INGRESS=m
      #     '';
      #   }
      # ];
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
