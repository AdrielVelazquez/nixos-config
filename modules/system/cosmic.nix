{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.cosmic;
in
{
  options.within.cosmic.enable = mkEnableOption "Enables cosmic desktopManager";
  # cosmic does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    nix.settings = {
      substituters = [ "https://cosmic.cachix.org/" ];
      trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
    };
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    systemd.user.services.add-ssh-key = {
      description = "Add my default SSH key to the GNOME Keyring agent";

      # Start this service as part of your graphical login session.
      wantedBy = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "gcr-ssh-agent.socket"
      ];

      # The gcr-ssh-agent is activated via a socket. We ensure this service
      # runs after that socket is ready.
      # While graphical-session.target is usually sufficient, this is more precise.
      wants = [ "gcr-ssh-agent.socket" ];

      # The script to execute.
      # The SSH_AUTH_SOCK variable will be correctly set by gcr-ssh-agent.
      script = ''
        # Optional: Check if the key is already loaded before adding.
        # Replace 'your_key_fingerprint' with the actual fingerprint from:
        # ssh-keygen -lf ~/.ssh/id_ed25519.pub | awk '{print $2}'
        if ! ${pkgs.openssh}/bin/ssh-add -l | /bin/grep -q 'SHA256:XkJ3aTz2KaBvwXQNnFS1eTYeLviRdnu3yHAUGB1o+jM'; then
          ${pkgs.openssh}/bin/ssh-add /home/adriel/.ssh/id_ed25519
        fi
      '';

      # Define the user under which this service will run.
      serviceConfig = {
        User = "adriel";
      };
    };
  };
}
