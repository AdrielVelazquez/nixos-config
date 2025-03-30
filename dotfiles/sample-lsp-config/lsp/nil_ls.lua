---@type vim.lsp.Config
return {
  cmd = { 'nil' },
  filetypes = { 'nix' },
  root_markers = { 'flake.nix', '.git' },
  settings = {
    ['nil'] = { formatting = { command = { 'nixfmt' } } },
  },
}
