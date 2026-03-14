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
in
{
  options.local.niri.enable = lib.mkEnableOption "niri system-level support (PAM, greetd, swaylock, etc.)";

  config = lib.mkIf cfg.enable {
    # PAM configs use absolute paths to /usr/lib/security/ so that nix-built
    # binaries (which link nix's libpam) load the host's PAM modules. This is
    # necessary because the nix-store unix_chkpwd lacks setuid and can't read
    # /etc/shadow. Flattened from CachyOS system-login + system-auth.
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
      # auth: system-login preamble + system-auth
      auth       required   /usr/lib/security/pam_shells.so
      auth       requisite  /usr/lib/security/pam_nologin.so
      auth       required   /usr/lib/security/pam_faillock.so      preauth
      -auth      [success=2 default=ignore]  /usr/lib/security/pam_systemd_home.so
      auth       [success=1 default=bad]     /usr/lib/security/pam_unix.so  try_first_pass nullok
      auth       [default=die]               /usr/lib/security/pam_faillock.so  authfail
      auth       optional   /usr/lib/security/pam_permit.so
      auth       required   /usr/lib/security/pam_env.so
      auth       required   /usr/lib/security/pam_faillock.so      authsucc

      # account: system-login preamble + system-auth
      account    required   /usr/lib/security/pam_access.so
      account    required   /usr/lib/security/pam_nologin.so
      -account   [success=1 default=ignore]  /usr/lib/security/pam_systemd_home.so
      account    required   /usr/lib/security/pam_unix.so
      account    optional   /usr/lib/security/pam_permit.so
      account    required   /usr/lib/security/pam_time.so

      # password: system-auth
      -password  [success=1 default=ignore]  /usr/lib/security/pam_systemd_home.so
      password   required   /usr/lib/security/pam_unix.so  try_first_pass nullok shadow
      password   optional   /usr/lib/security/pam_permit.so

      # session: system-login wrapping system-auth
      session    optional   /usr/lib/security/pam_loginuid.so
      session    optional   /usr/lib/security/pam_keyinit.so       force revoke
      -session   optional   /usr/lib/security/pam_systemd_home.so
      session    required   /usr/lib/security/pam_limits.so
      session    required   /usr/lib/security/pam_unix.so
      session    optional   /usr/lib/security/pam_permit.so
      session    optional   /usr/lib/security/pam_lastlog2.so      silent
      session    optional   /usr/lib/security/pam_motd.so
      session    optional   /usr/lib/security/pam_mail.so          dir=/var/spool/mail standard quiet
      session    optional   /usr/lib/security/pam_umask.so
      -session   optional   /usr/lib/security/pam_systemd.so
      session    required   /usr/lib/security/pam_env.so
    '';

    environment.etc."greetd/config.toml".text = ''
      [terminal]
      vt = 1

      [default_session]
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session"
      user = "adriel"
    '';

    environment.systemPackages = [
      pkgs.greetd.greetd
      pkgs.greetd.tuigreet
    ];

    systemd.services.greetd = {
      description = "greetd greeter daemon";
      after = [
        "systemd-user-sessions.service"
        "getty@tty1.service"
      ];
      conflicts = [ "getty@tty1.service" ];

      serviceConfig = {
        Type = "idle";
        ExecStart = "${pkgs.greetd.greetd}/bin/greetd --config /etc/greetd/config.toml";
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
