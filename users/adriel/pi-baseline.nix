# users/adriel/pi-baseline.nix
#
# Pi settings shared by every adriel host, including Codex's Headroom route.
# Provider availability, role models and additional proxy routes stay host-specific.
{ ... }:

{
  # The standalone Pi features (UI, LSP, workflow, OpenSpec, AST, web fetch) are on by
  # default; roles and routing follow llmPlatform.
  local.pi = {
    enable = true;
    modelRoles.planMode.instructions = builtins.readFile ../../dotfiles/pi/planning-instructions.md;
    extraSettings.defaultThinkingLevel = "high";
  };
  local.headroom.pi = {
    enable = true;
    providers.openai-codex.enable = true;
  };
}
