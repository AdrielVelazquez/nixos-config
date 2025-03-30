---@type vim.lsp.Config
return {
  cmd = { 'terraform-lsp' },
  filetypes = { 'terraform', 'hcl' },
  root_markers = { '.terraform', '.git' },
}
