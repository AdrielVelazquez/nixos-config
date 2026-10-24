# checks/default.nix
#
# Every check that drives the Pi and omp integrations, merged into one attribute set for checks.nix. Each file
# declares the arguments it needs and ignores the rest; add a new file to the list to register its checks.
args:
builtins.foldl' (checks: file: checks // import file args) { } [
  ./pi.nix
  ./omp.nix
  ./pi-ui.nix
  ./pi-lsp.nix
  ./pi-format.nix
  ./pi-dap.nix
  ./pi-hashline.nix
  ./pi-eval.nix
  ./pi-tools.nix
  ./pi-rtk.nix
  ./pi-checkpoints.nix
  ./pi-ghost.nix
  ./pi-model-roles.nix
  ./pi-headroom-providers.nix
  ./pi-api-keys.nix
  ./pi-razer.nix
  ./pi-stats.nix
  ./pi-omp-parity.nix
  ./pi-settings.nix
]
