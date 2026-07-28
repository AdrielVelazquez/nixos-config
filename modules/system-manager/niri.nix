# modules/system-manager/niri.nix
# System-level niri concerns for non-NixOS (e.g. CachyOS via system-manager)
#
# greetd, tuigreet, and hyprlock remain native host packages because nix-built
# PAM-aware binaries link against Nix's libpam, whose unix_chkpwd lacks setuid
# and cannot read /etc/shadow. The explicit CachyOS bootstrap recipe installs
# them; system-manager verifies them before activation.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.niri;
in
{
  options.local.niri.enable = lib.mkEnableOption "niri system-level support (PAM, greetd, hyprlock, etc.)";

  config = lib.mkIf cfg.enable {
    system-manager.preActivationAssertions.niriNativePackages = {
      enable = true;
      script = ''
        missing=0

        for executable in /usr/bin/greetd /usr/bin/tuigreet /usr/bin/hyprlock; do
          if [ ! -x "$executable" ]; then
            echo "Missing native CachyOS executable: $executable"
            missing=1
          fi
        done

        if [ ! -x /usr/bin/getent ] || ! /usr/bin/getent passwd greeter >/dev/null; then
          echo "Missing native greetd account: greeter"
          missing=1
        fi

        if [ "$missing" -ne 0 ]; then
          echo "Run 'just bootstrap-cachyos-prereqs' before activating systemConfigs.cachyos-framework13."
          exit 1
        fi
      '';
    };

    environment.etc."pam.d/hyprlock".text = ''
      auth include system-auth
    '';

    environment.etc."pam.d/greetd".text = ''
      auth include system-login
      account include system-login
      session include system-login
    '';

    environment.etc."greetd/config.toml".text = ''
      [terminal]
      vt = 1

      [default_session]
      command = "/usr/bin/tuigreet --time --remember --cmd niri-session"
      user = "greeter"
    '';

    systemd.services.greetd = {
      description = "greetd greeter daemon";
      after = [
        "systemd-user-sessions.service"
        "getty@tty1.service"
      ];
      conflicts = [ "getty@tty1.service" ];

      serviceConfig = {
        Type = "idle";
        ExecStart = "/usr/bin/greetd --config /etc/greetd/config.toml";
        Restart = "on-success";

        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "journal";

        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;

        IgnoreSIGPIPE = false;
        SendSIGHUP = true;
        TimeoutStopSec = "30s";
        KeyringMode = "shared";
      };

      wantedBy = [ "graphical.target" ];
    };
  };
}
