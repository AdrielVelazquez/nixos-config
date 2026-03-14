# modules/system-manager/niri.nix
# System-level niri concerns for non-NixOS (e.g. CachyOS via system-manager)
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  sentinel = "/var/lib/system-manager/.greetd-setup-done";

  setupScript = pkgs.writeShellScript "setup-greetd" ''
    set -euo pipefail
    pacman -S --needed --noconfirm greetd greetd-tuigreet
    systemctl disable --now sddm 2>/dev/null || true
    systemctl enable greetd
    systemctl set-default graphical.target
    mkdir -p "$(dirname "${sentinel}")"
    touch "${sentinel}"
  '';
in
{
  options.local.niri.enable = lib.mkEnableOption "niri system-level support (PAM, greetd, swaylock, etc.)";

  config = lib.mkIf cfg.enable {
    # Uses absolute paths so nix-built swaylock (which links nix's libpam)
    # loads the system's PAM modules with a setuid-capable unix_chkpwd.
    environment.etc."pam.d/swaylock".text = ''
      auth       required   /usr/lib/security/pam_faillock.so   preauth
      -auth      [success=2 default=ignore]  /usr/lib/security/pam_systemd_home.so
      auth       [success=1 default=bad]     /usr/lib/security/pam_unix.so   try_first_pass nullok
      auth       [default=die]               /usr/lib/security/pam_faillock.so   authfail
      auth       optional   /usr/lib/security/pam_permit.so
      auth       required   /usr/lib/security/pam_faillock.so   authsucc
      account    required   /usr/lib/security/pam_unix.so
      account    optional   /usr/lib/security/pam_permit.so
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
      user = "adriel"
    '';

    systemd.services.setup-greetd = {
      description = "One-time greetd setup (install native packages, disable SDDM)";
      before = [ "greetd.service" ];

      unitConfig = {
        ConditionPathExists = "!${sentinel}";
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = setupScript;
        RemainAfterExit = true;
      };

      wantedBy = [ "graphical.target" ];
    };

    systemd.services.greetd = {
      description = "greetd greeter daemon";
      after = [
        "systemd-user-sessions.service"
        "getty@tty1.service"
        "setup-greetd.service"
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
