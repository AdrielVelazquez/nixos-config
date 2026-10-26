# users/adriel/pi-baseline.nix
#
# Pi settings shared by every adriel host. Provider-specific choices (which provider, which role
# models, whether Headroom routes through LLM Platform or through `local.headroom.pi.providers`)
# stay in each host's user file.
{ ... }:

{
  # The standalone Pi features (UI, LSP, workflow, OpenSpec, AST, web fetch) are on by
  # default; roles and routing follow llmPlatform.
  local.pi = {
    enable = true;
    modelRoles.planMode.instructions = builtins.readFile ../../dotfiles/pi/planning-instructions.md;
    extraSettings.defaultThinkingLevel = "high";
  };
  local.headroom.pi.enable = true;
}
