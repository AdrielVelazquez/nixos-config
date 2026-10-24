# users/adriel/pi-baseline.nix
#
# Pi settings shared by every adriel host. Provider-specific choices (which provider, which role
# models, whether Headroom routes through LLM Platform or through `local.headroom.pi.providers`)
# stay in each host's user file.
{ config, ... }:

{
  # The standalone Pi features (UI, LSP, ghost text, workflow, OpenSpec, AST, web fetch) are on by
  # default; roles and routing follow llmPlatform, and stats follows omp.
  local.pi = {
    enable = true;
    modelRoles.planMode.instructions = builtins.readFile ../../dotfiles/pi/planning-instructions.md;
    extraSettings.defaultThinkingLevel = "high";
    # Ghost text learns tool and project words from history the user approved: earlier Pi prompts
    # (typed prompts only) and shell command names (never arguments).
    ghostText.seed = {
      piSessions = true;
      shellHistory = [
        config.programs.zsh.history.path
        "${config.home.homeDirectory}/.bash_history"
      ];
    };
  };
  local.headroom.pi.enable = true;
}
