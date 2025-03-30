---@type vim.lsp.Config
return {
  cmd = { 'nixd' },
  filetypes = { 'nix' },
  single_file_support = true,
  root_markers = { 'flake.nix', '.git' },
}
