local pack = require 'config.pack'

pack.add {
  pack.repo 'stevearc/conform.nvim',
}

require('conform').setup {
  formatters_by_ft = {
    go = { 'gofumpt' },
    nix = { 'nixfmt' },
    python = { 'ruff_format' },
    lua = { 'stylua' },
  },
  format_on_save = {
    lsp_fallback = true,
    async = false,
    timeout_ms = 500,
  },
}

vim.keymap.set('n', '<leader>cf', function()
  require('conform').format { async = true, lsp_fallback = true }
end, { desc = 'Format current buffer [C]onform [F]ormat' })
